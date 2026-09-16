# Release handbook

Nifro distributes through GitHub Releases and the Homebrew cask in this repository.
Official releases now require Developer ID signing, Apple notarization, ticket stapling,
and Gatekeeper verification. Missing credentials or a failed build stop the workflow
before it creates a tag. Self-signed development builds remain available locally.

## Signing environment

The `release` job uses the protected GitHub environment `release-signing`. Configure its
reviewer and permitted deployment refs before dispatching it. Current configuration allows
`main` and `v*` and requires PathGao approval, including dry runs.

| Type | Name | Value |
| --- | --- | --- |
| Secret | `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate and its project-specific private key |
| Secret | `MACOS_CERTIFICATE_PASSWORD` | Password for that same export |
| Variable | `APPLE_TEAM_ID` | `GN56VLVTJ6` |
| Variable | `APPLE_SIGNING_IDENTITY` | Nifro certificate SHA-1: `57E90D936910FD25342D56B3D8E35E1CC6DF201C` |

The workflow matches the exact SHA-1, certificate type and team in the temporary keychain.
A certificate with the same display name is not interchangeable. Back up the project key and
matching export password outside the repository. `Tools/setup-signing.sh` is only for local
self-signed development and legacy exports. It cannot create an Apple-issued certificate;
do not use its exports or legacy repository-secret upload for `release-signing`.

Provide either notarization credential set as environment secrets:

| Method | Secrets |
| --- | --- |
| App Store Connect team API key | `NOTARY_KEY_P8` (base64), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` |
| Apple account | `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` (uses `APPLE_TEAM_ID` above) |

An API key takes precedence when `NOTARY_KEY_P8` is set; an incomplete API key configuration
fails instead of silently switching methods. Do not put credentials in chat, source files or logs.
As of the 2026-09-16 setup, the signing certificate is configured but notarization credentials
are still required. No notarized release has been verified by this configuration change.

## Local builds

`./Tools/build-local.sh` keeps the stable self-signed development identity and installs a test
copy on the Desktop. To build with Nifro's exact Developer ID certificate already in the local
keychain, without modifying the default development identity:

```sh
APPLE_SIGNING_IDENTITY=57E90D936910FD25342D56B3D8E35E1CC6DF201C \
APPLE_TEAM_ID=GN56VLVTJ6 \
./Tools/build-local.sh .release/Nifro-test.app
```

Build products live in `.xcode-build`. The script preserves sandbox entitlements and verifies
the signature before copying the app. A local Developer ID build is **not notarized** by this
script. Use the release workflow's dry run to exercise notarization and packaging.

## Release sequence

1. Update `MARKETING_VERSION` in `Config.xcconfig` and land the reviewed changes on `main`.
2. Dispatch `gh workflow run release.yml --ref main -f dry_run=true` and approve the environment.
   Both architectures must build, sign, notarize, staple and pass Gatekeeper. Disk images are
   retained as the `dry-run-disk-images` artifact; no tag or release is created.
3. Dispatch `gh workflow run release.yml --ref main` and approve the environment. The tag is
   created only after packaging succeeds. Existing version tags are rejected.
4. Check the generated cask pull request and verify its checksums against the release assets.
   Cask PR creation can fail after a successful release, so check it separately.

Build logs are retained as `xcodebuild-logs`, including failed runs. Temporary signing material
is cleaned up even after failure. The release signs with hardened runtime and a secure timestamp,
checks the leaf certificate fingerprint, submits each app to Apple, validates its stapled ticket,
and performs a Gatekeeper assessment before packaging the disk images.

## Transition from older releases

Version 0.9.1 introduces Developer ID signing and required notarization. Its README and cask
remove the old quarantine bypass. Publish these changes together with the verified release,
and update the cask version and checksums from its actual assets before users install it.
Users upgrading from a self-signed release may need to select local wallpaper files again.
