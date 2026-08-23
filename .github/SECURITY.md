# Security

## Reporting a vulnerability

Please report security issues privately through
[GitHub's private vulnerability reporting](https://github.com/PathGao/Nifro/security/advisories/new)
rather than as a public issue. That form is the only channel — there is one
maintainer and no security mailing list, and a public issue for a live
vulnerability is the one thing that cannot be undone.

Expect a first reply within a week. If a report holds up, the fix ships in the
next release and the advisory is published with it, crediting you unless you
ask otherwise.

## What is in scope

Nifro renders arbitrary web pages, chosen by the user, in a `WKWebView` behind
their windows. The interesting boundary is between that page and the machine:

- A page escaping the web view, or reaching anything outside the app sandbox.
- A site entry in `sites/` whose CSS or JavaScript does something other than
  lay out the page — exfiltrating data, calling out to a third party, or
  reading the user's other websites' settings. Entries are pasted into other
  people's machines, so this is treated as a security bug, not a content
  dispute.
- The `nifro://` URL scheme, and the Shortcuts and Share Extension entry
  points: anything reachable from another application that changes state
  without the user's involvement.
- The release pipeline: a signed build that is not what this repository says
  it is.

## What is not

- A page the user deliberately loaded doing something the user asked for. The
  app runs pages the user chose, with the JavaScript the user pasted; that is
  the feature.
- Anything that requires the attacker to already have the user's account.
- Gatekeeper warnings on directly downloaded builds. That is expected and
  documented in [docs/RELEASE.md](../docs/RELEASE.md) — builds are self-signed and
  not notarized. Homebrew is the supported route.

## Supported versions

The latest release only. This is a one-maintainer project and there are no
backport branches.
