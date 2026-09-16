#!/bin/bash
# Build locally without opening Xcode. Full Xcode 26+ is required.
set -euo pipefail
cd "$(dirname "$0")"

mode="${1:-dev}"
if [[ $# -gt 0 ]]; then shift; fi
case "$mode" in
  -h|--help)
    cat <<'HELP'
Usage: ./build.sh [dev|ci|release] [xcodebuild arguments...]
  dev      Release-optimized, ad-hoc signed, isolated com.pathgao.nifro.dev (default)
  ci       Debug, unsigned, isolated development identity
  release  Production identity; requires APPLE_SIGNING_IDENTITY and APPLE_TEAM_ID

Output: .xcode-build/Build/Products/{Debug,Release}/Nifro.app
No installation, launch, keychain changes, or notarization is performed.
For a selected Xcode, set DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer.
HELP
    exit 0 ;;
  dev|ci|release) ;;
  *) echo "Unknown mode: $mode. See ./build.sh --help." >&2; exit 2 ;;
esac

version="$(xcodebuild -version)" || {
  echo "Full Xcode 26+ is required, including the icon and App Intents tools." >&2
  exit 1
}
major="$(sed -n '1s/Xcode \([0-9]*\).*/\1/p' <<< "$version")"
[[ "$major" =~ ^[0-9]+$ && "$major" -ge 26 ]] || {
  echo "Xcode 26+ is required. Found: $version" >&2; exit 1;
}

configuration=Release
signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
identity=(NIFRO_BUNDLE_ID=com.pathgao.nifro.dev NIFRO_URL_SCHEME=nifro-dev)
case "$mode" in
  ci) configuration=Debug; signing=(CODE_SIGNING_ALLOWED=NO) ;;
  release)
    : "${APPLE_SIGNING_IDENTITY:?Set the Developer ID certificate SHA-1}"
    : "${APPLE_TEAM_ID:?Set the Developer ID team}"
    [[ "$APPLE_SIGNING_IDENTITY" =~ ^[0-9A-F]{40}$ && "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || {
      echo "Invalid signing SHA-1 or team ID." >&2; exit 1;
    }
    identity=(NIFRO_BUNDLE_ID=com.pathgao.nifro NIFRO_URL_SCHEME=nifro)
    signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$APPLE_SIGNING_IDENTITY"
      DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER=
      ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime") ;;
esac

xcodebuild build -project Tools/Nifro.xcodeproj -scheme Nifro \
  -configuration "$configuration" -destination 'generic/platform=macOS' \
  -derivedDataPath .xcode-build "${identity[@]}" "${signing[@]}" "$@"

app=".xcode-build/Build/Products/$configuration/Nifro.app"
if [[ "$mode" != ci ]]; then
  codesign --verify --deep --strict "$app"
  for bundle in "$app" "$app/Contents/PlugIns/Share Extension.appex"; do
    codesign -d --entitlements - --xml "$bundle" 2>/dev/null \
      | plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - - | grep -qx true
  done
fi
printf '\nBuilt: %s/%s\n' "$PWD" "$app"
