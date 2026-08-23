#!/bin/zsh
# Creates the self-signed code-signing identity that Nifro builds are signed with.
#
#   ./Tools/setup-signing.sh                  install a local identity for your own builds
#   ./Tools/setup-signing.sh --export <path>  write a .p12 for CI to sign releases with
#   ./Tools/setup-signing.sh --export <path> --upload
#                                             …and set both repository secrets with `gh`, so
#                                             neither value is ever copied by hand
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

	# Prove the pair works before handing it over. The release workflow imports the certificate with
	# this password and nothing else; if that fails there, the failure arrives ten minutes into a
	# release with "MAC verification failed during PKCS12 import (wrong password?)" and no way to tell
	# a bad export from a mistyped secret. It costs nothing to find out here.
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
	echo "  This is the identity every official release is signed with. Losing it means later"
	echo "  releases get a different designated requirement, and every user's saved local-file"
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
		echo "  Nothing was printed, so nothing can be mispasted. Tag a release when ready."
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
