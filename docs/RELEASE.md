# Release handbook

Nifro is not on the Mac App Store. Distribution goes through **GitHub Release + Homebrew cask**.

Files involved:

| File | What it does |
| --- | --- |
| `.github/workflows/release.yml` | Triggered by pushing a `v*` tag: build → sign → (notarize) → package → create the Release → write back the cask |
| `Tools/setup-signing.sh` | Generates the self-signed certificate: installs it into the local keychain, or exports a `.p12` for CI |
| `Tools/build-local.sh` | Produces a local test build signed the same way a release is |
| `Casks/nifro.rb` | The cask definition. `version` / `sha256` are updated automatically by the workflow |
| `Config.xcconfig` | `MARKETING_VERSION`. It has to match the tag, and the workflow checks that |

---

## 1. Currently chosen: self-signed

**Nifro uses a self-signed certificate**, following AeroSpace. There is no Apple Developer Program
membership, so there is no notarization.

The workflow only looks at which kind of certificate is installed from `MACOS_CERTIFICATE_P12` and
works out which path to take on its own. The YAML does not need changing:

```
                                                       ┌─ Developer ID certificate ─→ hardened runtime + notarization + staple
  push tag v* ─→ import certificate ─→ check identity ─┤
                        │                              └─ self-signed certificate ──→ sign only, no notarization   ← the current path
                        └─ no secret ───────────────────────────────────────────────→ ad-hoc
```

### Where self-signed and ad-hoc differ

To Gatekeeper they are exactly the same: neither is notarized, and a downloaded build is stopped on
first open either way. The difference is **whether the signing identity is stable**.

Nifro is a sandboxed app, and when a user sets a local HTML file as the wallpaper what gets stored is
a **security-scoped bookmark** (`BookmarksUserDefaults` in `Nifro/Support/Extensions.swift`). The
bookmark is tied to the app's code signature:

```
ad-hoc         v0.1 signature A ──┐
               v0.2 signature B ──┴─→ a new signature every time → bookmarks break after an update → the user gets the file picker again
self-signed    v0.1 ┐
               v0.2 ┴─→ designated requirement stays certificate root = <the same certificate> → grants survive across versions
```

So the extra step here is not about looking more official. It is about not losing user settings on
update.

**Losing the certificate means changing identity.** The exported `.p12` is the only copy. Lose it and
the designated requirement changes for every later version, which amounts to putting every user
through an ad-hoc update once. Back it up.

### If an account is bought later: Developer ID + notarization

```
xcodebuild (CODE_SIGN_IDENTITY="Developer ID Application", hardened runtime)
   ↓
ditto -c -k --keepParent  →  notarize.zip
   ↓
xcrun notarytool submit --wait      (Apple runs a scan, usually 1-10 minutes)
   ↓
xcrun stapler staple Nifro.app      (staples the notarization ticket into the app, so it passes offline too)
   ↓
spctl -a -vvv --type exec           (Gatekeeper self-check; fail rather than ship a bad build)
   ↓
Nifro-x.y.z.dmg  →  GitHub Release  →  pull request with the new cask version/sha256
```

### The current path: self-signed

```
Tools/setup-signing.sh --export nifro-release.p12   ← one-off, generated locally with openssl, no account needed
   ↓  base64-encoded, then stored as a repository secret
xcodebuild (CODE_SIGN_IDENTITY="Nifro Signing")     ← the sandbox entitlements go into the signature as normal
   ↓
Nifro-x.y.z.dmg  →  GitHub Release  →  pull request with the new cask version/sha256
                                        the cask's postflight removes com.apple.quarantine
```

The `spctl` check is skipped, the workflow only prints a warning, and the release notes are marked
"not notarized" automatically.

**A free Apple ID does not count**: a free account can only sign `Apple Development` certificates,
which expire after 7 days and are valid only on the machine that made them, so they cannot be used
for distribution. A self-signed certificate has none of those limits, because it never goes near
Apple at all.

---

## 2. GitHub Secrets needed

Self-signing needs only the first two. The last four are for notarization later.

| Secret | What it holds | Where it comes from | Needed for self-signing |
| --- | --- | --- | --- |
| `MACOS_CERTIFICATE_P12` | The `.p12` with the certificate and private key, **base64-encoded** | `Tools/setup-signing.sh --export … --upload` sets it | Yes |
| `MACOS_CERTIFICATE_PASSWORD` | The password for that `.p12` | The same run of the same command. **These two have to come from one run** — see B0 | Yes |
| `APPLE_TEAM_ID` | The 10-character Team ID, such as `ABCDE12345` | developer.apple.com → Membership | No |
| `NOTARY_KEY_P8` | The App Store Connect API private key `AuthKey_XXXXXXXX.p8`, **base64-encoded** | See A3 below | No |
| `NOTARY_KEY_ID` | The Key ID of that key (8 characters) | Shown on the page when the key is generated | No |
| `NOTARY_ISSUER_ID` | The Issuer ID (a UUID) | App Store Connect → Integrations → Keys, at the top of the page | No |

> An App Store Connect API key rather than "Apple ID + app-specific password": 2FA does not affect
> it, it can be revoked on its own, and it is not tied to a personal account password.

How to base64-encode (macOS):

```bash
base64 -i DeveloperID.p12       | pbcopy   # paste into MACOS_CERTIFICATE_P12
base64 -i AuthKey_XXXXXXXX.p8   | pbcopy   # paste into NOTARY_KEY_P8
```

Where to set them: repo → Settings → Secrets and variables → Actions → New repository secret.

---

## 3. What the maintainer has to do by hand (an agent cannot)

**To do now (self-signed, no Apple account needed):**

- **B0** Run this once locally. It writes the certificate, sets both repository secrets with `gh`,
  and prints neither value:

  ```bash
  ./Tools/setup-signing.sh --export ~/nifro-release.p12 --upload
  ```

  **Set them together or not at all.** Each run generates a fresh certificate and a fresh random
  password, so a certificate from one run with a password from another opens nothing — and the only
  place that shows up is ten minutes into a release, as
  `MAC verification failed during PKCS12 import (wrong password?)`, which reads like a typo. That is
  what happened on the first attempt. `--upload` pipes both straight from the run that made them, so
  they cannot drift apart. Without it the script prints them for pasting by hand, and checks the pair
  imports before it does.

  Then back `~/nifro-release.p12` up somewhere you will still find it in a year (see "Losing the
  certificate means changing identity”, above). Do **not** keep this file in the repository.

**The following are only for after a paid account is bought. Skip them for now:**

- **A1** Create the certificate in Xcode → Settings → Accounts → Manage Certificates → `+` →
  **Developer ID Application** (or go through the CSR flow at developer.apple.com → Certificates).
- **A2** Open Keychain Access, find that certificate, and right-click to export it as a `.p12`
  **together with its private key**, with a password. Exporting the certificate without the private
  key leaves CI unable to sign.
- **A3** appstoreconnect.apple.com → Users and Access → Integrations → Keys → generate an API key
  with **Developer Access / App Manager** permission and download the `.p8` (**downloadable only
  once**).
- **A4** Put the 6 secrets from the table above into the repository.
- **A5** After the first successful release, delete the whole `postflight` block from
  `Casks/nifro.rb` (once a build is notarized the quarantine attribute no longer needs stripping,
  and leaving it in is a bad signal). Moving to Developer ID changes the signing identity once, so
  local-file wallpapers a user has already granted access to break once. That is the one-off cost of
  going from self-signed to notarized, and it belongs in the release notes for that version.

**Needed on either path:**

- **B1** Create the tap repository `PathGao/homebrew-tap`, or have users tap this repository
  directly (`brew tap PathGao/tap https://github.com/PathGao/Nifro`, with the cask under `Casks/` in
  this repository, so there is no second repository to maintain — this is the lower-effort route).
- **B2** Check that the branch protection rules on `main` allow `github-actions[bot]` to push,
  the workflow can open the cask pull request. It uses the default `GITHUB_TOKEN`, so nothing has
  to be configured — but a ruleset that forbids branch creation would stop it. A failure here only
  warns; the Release itself is already published.
- **B3** ~~Line up `XCODE_SCHEME` / `BUILT_APP_NAME` at the top of the workflow~~ Done, both values
  are `Nifro`.

---

## 4. Releasing a version

```bash
# 1. Change the version number (the tag has to match it, or the workflow fails outright)
vim Config.xcconfig            # MARKETING_VERSION = 0.2.0

# 2. Commit
git commit -am "0.2.0" && git push

# 3. Tag
git tag -a v0.2.0 -m "v0.2.0" && git push origin v0.2.0
```

The workflow covers the rest: build, sign, notarize, package, create the Release, write back
`Casks/nifro.rb`.

When it fails, start with the `xcodebuild-log` artifact in Actions.

---

## 5. What users end up with

### If it gets notarized later

| Install route | What the user sees |
| --- | --- |
| `brew install --cask PathGao/tap/nifro` | Opens straight after installing, no prompt |
| Download the disk image and double-click | First open asks "Nifro is an app downloaded from the Internet. Are you sure you want to open it?" → click Open → done |

### Now (self-signed, not notarized)

| Install route | What the user sees |
| --- | --- |
| `brew install --cask PathGao/tap/nifro` | Opens straight after installing, no prompt (the cask's `postflight` has already removed the quarantine attribute) |
| Download the disk image and double-click | **Blocked**: "Nifro can't be opened because Apple cannot check it for malicious software", with only a Move to Trash and a Done button |

Users who download the disk image directly need one extra step. Wording for the install section of the
README:

> The first time you open it, macOS says "Nifro can't be opened because Apple cannot check it for
> malicious software". That is because Nifro is not notarized by Apple (notarization needs a
> developer account at $99 a year). Installing with Homebrew does not hit this prompt.
>
> To allow it by hand, either:
>
> 1. Open the blocked app once → System Settings → Privacy & Security → scroll to the bottom →
>    click Open Anyway.
> 2. Or run this in a terminal:
>    ```bash
>    xattr -dr com.apple.quarantine /Applications/Nifro.app
>    ```

**Do not send users off to turn off SIP or run `spctl --master-disable`**, that lowers the security
level of the whole machine and is not the way to solve this.

---

## 6. How this relates to AeroSpace

The reference is [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace). What it actually
does:

- **Signing**: `build-release.sh` runs `codesign -s "aerospace-codesign-certificate"`, a
  **self-signed certificate** in the maintainer's own keychain, not a Developer ID. CI (`build.yml`)
  uses `./build-release.sh --codesign-identity -`, with a comment saying outright that the
  certificate is not on GH Actions. Nifro goes one step further: the certificate is exported as a
  `.p12` and stored as a repository secret, so CI has the same one, and an official release does not
  change signing identity depending on whose machine built it.
- **Notarization**: not done. The README says so explicitly.
- **Releasing**: **no release workflow**. `.github/workflows/` holds only `build.yml` and two issue
  bots. Actual releases come from the maintainer running `script/publish-release.sh` locally: tag,
  `open` a browser, **drag the zip onto the GitHub Release page by hand**, press return to continue.
- **cask**: its own tap (`nikitabobko/homebrew-tap`), with `Casks/aerospace.rb` generated by
  `script/build-brew-cask.sh` and then `cp`ed over. No livecheck, and `version` is a hard-coded
  literal. `xattr -d com.apple.quarantine` in `postflight` is what gets brew users past Gatekeeper.

Where Nifro deviates:

| Item | AeroSpace | Nifro | Why |
| --- | --- | --- | --- |
| Release trigger | Local script + manual upload | GitHub Actions on a tag | Releasing locally needs the maintainer's machine to be in the right state, and is not reproducible |
| Signing | Self-signed certificate (local only) | Self-signed certificate (one certificate shared by local builds and CI) | The two are equivalent to Gatekeeper, but a fixed identity is what keeps sandbox bookmarks alive across versions, and it is only fixed if CI has it too |
| Notarization | Not done | Not done now, switch left in place | No notarization at this stage either. The workflow switches on the certificate type, so buying an account later changes one secret and nothing else |
| cask version | Generated by hand, then cp | CI opens a pull request against `Casks/` in this repository | One fewer tap repository to maintain, one fewer manual step |
| livecheck | None | Present | 4 lines, lets `brew livecheck` check for itself, and useful if this ever goes upstream to homebrew-cask |
| CLI / manpage / shell completion | Present | None | Nifro is only a GUI app + ShareExtension |

Kept from AeroSpace: no fastlane, only `xcodebuild` + `codesign` + `notarytool` and a little shell,
and the cask's `postflight` stripping the quarantine attribute.

Not kept: AeroSpace ships a zip, this ships a disk image. A zip expands to a bare `.app` in Downloads
with nothing to say it belongs in `/Applications`; a disk image with a symlink beside the app says it
without a word.
