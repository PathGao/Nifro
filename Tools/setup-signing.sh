#!/bin/zsh
# Creates the self-signed code-signing identity that Nifro builds are signed with.
#
#   ./Tools/setup-signing.sh                  install a local identity for your own builds
#   ./Tools/setup-signing.sh --export <path>  write a .p12 for CI to sign releases with
#
# Nifro is sandboxed and keeps security-scoped bookmarks for local files a user picks as a
# wallpaper. Those bookmarks are tied to the app's code signature, so ad-hoc signing — a fresh
# signature every build — drops them on every update and re-opens the file picker. A fixed
# certificate keeps the designated requirement the same across versions, so the grants survive.
#
# Free, offline, idempotent. It is not a substitute for Apple notarization: a downloaded build
# still shows Gatekeeper's "unverified developer" prompt on first launch. Only a paid Developer
# ID certificate can remove that, and the release workflow switches to notarizing on its own if
# it finds one in the same secret.
set -euo pipefail

IDENTITY="Nifro Signing"
KEYCHAIN="$HOME/Library/Keychains/nifro-signing.keychain-db"
KEYCHAIN_PASSWORD="nifro-signing"

# One definition of what the certificate is. The export and the local install have to produce the
# same kind of certificate, or a release would be signed by something the maintainer never tested.
make_certificate() {
	local directory="$1" password="$2"
	openssl req -x509 -newkey rsa:2048 -keyout "$directory/key.pem" -out "$directory/cert.pem" \
		-days 3650 -nodes \
		-subj "/CN=$IDENTITY/O=Nifro" \
		-addext "keyUsage=critical,digitalSignature" \
		-addext "extendedKeyUsage=critical,codeSigning" \
		-addext "basicConstraints=critical,CA:false" 2>/dev/null
	openssl pkcs12 -export -legacy -inkey "$directory/key.pem" -in "$directory/cert.pem" \
		-out "$directory/identity.p12" -passout pass:"$password" -name "$IDENTITY" 2>/dev/null
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ "${1:-}" == "--export" ]]; then
	destination="${2:?usage: $0 --export <path.p12>}"
	password="$(openssl rand -base64 24)"
	make_certificate "$WORK" "$password"
	cp "$WORK/identity.p12" "$destination"

	echo "✓ Wrote $destination"
	echo
	echo "  This is the identity every official release is signed with. Losing it means later"
	echo "  releases get a different designated requirement, and every user's saved local-file"
	echo "  wallpaper stops being readable. Keep a copy somewhere you will still have in a year."
	echo
	echo "  Repo → Settings → Secrets and variables → Actions:"
	echo "    MACOS_CERTIFICATE_P12       $(base64 -i "$destination" | tr -d '\n' | cut -c1-24)…  (full value below)"
	echo "    MACOS_CERTIFICATE_PASSWORD  $password"
	echo
	echo "  Full base64 of the certificate:"
	base64 -i "$destination"
	exit 0
fi

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
	echo "✓ Signing identity already installed."
	exit 0
fi

make_certificate "$WORK" "$KEYCHAIN_PASSWORD"

security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"  # No auto-lock, so builds never prompt.
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1
EXISTING=$(security list-keychains -d user | sed 's/"//g' | xargs)
security list-keychains -d user -s "$KEYCHAIN" ${=EXISTING}

echo "✓ Created signing identity '$IDENTITY'. Tools/build-local.sh now uses it."
