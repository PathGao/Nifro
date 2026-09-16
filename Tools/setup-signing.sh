#!/bin/zsh
# Creates a stable self-signed identity for local development and legacy builds.
# Usage: no arguments installs locally; --export <path.p12> exports a fresh identity;
# --export <path.p12> --upload also replaces the legacy repository signing secrets.
# Do not use these exports for the release-signing environment: official releases
# require the project's Apple-issued Developer ID certificate.
set -euo pipefail

IDENTITY="Nifro Signing"
KEYCHAIN="$HOME/Library/Keychains/nifro-signing.keychain-db"
KEYCHAIN_PASSWORD="nifro-signing"

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

	# Verify the exported certificate and password are a usable pair before handing them over.
	probe="$WORK/probe.keychain-db"
	security create-keychain -p probe "$probe"
	if ! security import "$destination" -k "$probe" -P "$password" -T /usr/bin/codesign >/dev/null 2>&1; then
		security delete-keychain "$probe" 2>/dev/null || true
		echo "✗ The certificate just written cannot be imported with the password just generated." >&2
		exit 1
	fi
	security delete-keychain "$probe"

	base64 -i "$destination" | tr -d '\n' > "$WORK/certificate.b64"

	echo "✓ Wrote $destination"
	echo
	echo "  This is a self-signed development identity. Losing it means later"
	echo "  builds get a different designated requirement, and saved local-file"
	echo "  wallpaper stops being readable. Keep a copy somewhere you will still have in a year."
	echo

	if [[ "${3:-}" == "--upload" ]]; then
		# Piped, never pasted. The two values have to come from the same run of this script, and
		# every way of moving them by hand is a way of pairing a new certificate with an old
		# password — which is exactly what happened the first time, and it only showed up as a
		# failed release.
		gh secret set MACOS_CERTIFICATE_P12 < "$WORK/certificate.b64"
		printf '%s' "$password" | gh secret set MACOS_CERTIFICATE_PASSWORD
		echo "✓ Set MACOS_CERTIFICATE_P12 and MACOS_CERTIFICATE_PASSWORD on the repository."
		echo "  These legacy self-signed secrets cannot satisfy the official release workflow."
		exit 0
	fi

	echo "  Re-run with --upload to set both repository secrets directly, which is the only way"
	echo "  that cannot pair one run's certificate with another run's password. To do it by hand:"
	echo "  Repo → Settings → Secrets and variables → Actions"
	echo "    MACOS_CERTIFICATE_PASSWORD  $password"
	echo "    MACOS_CERTIFICATE_P12       the single line below, all of it"
	echo
	cat "$WORK/certificate.b64"
	echo
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
