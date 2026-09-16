# Security

## Reporting a vulnerability

Please report security issues privately through
[GitHub's private vulnerability reporting](https://github.com/PathGao/Nifro/security/advisories/new)
rather than as a public issue. That form is the only channel — there is one
maintainer and no security mailing list, and a public issue for a live
vulnerability is the one thing that cannot be undone.

Security fixes target the latest release. Give the maintainer time to investigate
and ship a fix before public disclosure; reporters can request credit. This
community project does not promise a response time.

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

## Release integrity

Official releases from v0.9.1 use Apple Developer ID signing and notarization.
Report unexpected signature, notarization or artifact-integrity failures with
the download source and exact system message. See [the release guide](../docs/RELEASE.md).

## Supported versions

The latest release only. This is a one-maintainer project and there are no
backport branches.
