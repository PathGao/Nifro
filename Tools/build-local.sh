#!/bin/zsh
# Builds a sandboxed local test copy. Set APPLE_SIGNING_IDENTITY (SHA-1) and
# APPLE_TEAM_ID to use Developer ID; otherwise use the local self-signed identity.
set -euo pipefail

IDENTITY="${APPLE_SIGNING_IDENTITY:-Nifro Signing}"
TEAM_ID="${APPLE_TEAM_ID:-}"
DESTINATION="${1:-$HOME/Desktop/Nifro-test.app}"
DERIVED_DATA=".xcode-build"

cd "$(dirname "$0")/.."

signing_args=()
if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
	[[ "$IDENTITY" =~ ^[0-9A-F]{40}$ && "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || {
		echo "APPLE_SIGNING_IDENTITY must be a SHA-1 and APPLE_TEAM_ID must be set." >&2
		exit 1
	}
	security find-identity -v -p codesigning | grep -E "^[[:space:]]*[0-9]+\) $IDENTITY \"Developer ID Application: .* \($TEAM_ID\)\"$" >/dev/null || {
		echo "The specified Developer ID identity is unavailable." >&2
		exit 1
	}
	signing_args+=(ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
else
	TEAM_ID=""
	if ! security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
		echo "→ Signing identity missing, creating it."
		./Tools/setup-signing.sh
	fi

	# A locked signing keychain still lists its identity, so the check above passes and codesign then
	# fails halfway through with `errSecInternalComponent` after putting a keychain prompt on screen.
	# Unlocking here is what keeps a build from ever asking for a password. If the passphrase no longer
	# matches — an older script wrote a different one — the keychain is rebuilt, since all it holds is a
	# self-signed local certificate that setup-signing.sh makes from scratch anyway.
	KEYCHAIN="$HOME/Library/Keychains/nifro-signing.keychain-db"
	if [[ -f "$KEYCHAIN" ]] && ! security unlock-keychain -p "nifro-signing" "$KEYCHAIN" 2>/dev/null; then
		echo "→ Signing keychain will not unlock, rebuilding it."
		security delete-keychain "$KEYCHAIN"
		./Tools/setup-signing.sh
	fi
	security set-keychain-settings "$KEYCHAIN"  # No auto-lock, so the next build does not prompt either.
fi

xcodebuild \
	-project Nifro.xcodeproj \
	-scheme Nifro \
	-configuration Release \
	-derivedDataPath "$DERIVED_DATA" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY="$IDENTITY" \
	DEVELOPMENT_TEAM="$TEAM_ID" \
	PROVISIONING_PROFILE_SPECIFIER="" \
	"${signing_args[@]}" \
	build | awk '/error:|warning: .*(deprecat|unused)|BUILD/'

BUILT="$DERIVED_DATA/Build/Products/Release/Nifro.app"

codesign --verify --deep --strict "$BUILT"

# The sandbox is the whole reason this script exists. A build that lost it looks
# fine and behaves differently, so fail here rather than let it get tested.
if ! codesign -d --entitlements - --xml "$BUILT" 2>/dev/null | plutil -p - | grep -q "app-sandbox"; then
	echo "✗ Built app has no sandbox entitlement. Not installing." >&2
	exit 1
fi

osascript -e 'quit app "Nifro"' 2>/dev/null || true
sleep 1
rm -rf "$DESTINATION"
cp -R "$BUILT" "$DESTINATION"

echo "✓ $DESTINATION"
codesign -dv "$DESTINATION" 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier)"
