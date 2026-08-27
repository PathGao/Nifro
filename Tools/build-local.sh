#!/bin/zsh
# Builds Nifro the way a release is built, and puts it on the Desktop to test.
#
# The point of going through a script is the signing. Signing the app by hand
# with `codesign --sign -` after the fact replaces the signature Xcode wrote and
# drops the entitlements with it, which silently un-sandboxes the build: it then
# reads and writes a different preferences file than a real install, so anything
# tested against it is testing the wrong app. Here Xcode signs once, with the
# entitlements, using the fixed identity from Tools/setup-signing.sh.
set -euo pipefail

IDENTITY="Nifro Signing"
DESTINATION="${1:-$HOME/Desktop/Nifro-test.app}"
DERIVED_DATA="${TMPDIR:-/tmp}/nifro-local-build"

cd "$(dirname "$0")/.."

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

xcodebuild \
	-project Nifro.xcodeproj \
	-scheme Nifro \
	-configuration Release \
	-derivedDataPath "$DERIVED_DATA" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY="$IDENTITY" \
	DEVELOPMENT_TEAM="" \
	PROVISIONING_PROFILE_SPECIFIER="" \
	build | grep -E "error:|warning: .*(deprecat|unused)|BUILD" || true

BUILT="$DERIVED_DATA/Build/Products/Release/Nifro.app"

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
