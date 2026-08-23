<!--
Nothing below is required. These are the sections a useful pull request here
tends to have, offered so you don't have to reverse-engineer them. Delete any
that don't apply, rename them to say what you actually found, and write prose
rather than filling in fields.

Adding a site to sites/? Only "What this is" matters — say what the site is and
what settings you used, and ignore the rest.
-->

## What this is

What changes, and `Closes #123` if there's an issue. If someone reported it,
say who and where.

## Mechanism

Why the old behaviour happened — the specific line, default or assumption
responsible — rather than what you did about it. `WKWebView`, AppKit window
levels and Spaces all have defaults that surprise people, so naming the one
you hit is the most valuable part of the description. If you measured
something, paste the numbers.

## Scope

What you deliberately left alone, and why. Anything you noticed while working
and chose not to fix here belongs in this section too. A small fix plus a note
about the larger problem is easier to review, and easier to revert, than both
at once.

## Verification

`swift test` covers the pure logic — the crop and zoom geometry, the menu bar strip, schedule
windows, which website is current on which display, video embedding and URL commands. Anything that
needs a window server or a web view has no automated coverage at all, so say what you ran by hand.

- Which macOS version and hardware you ran it on.
- The websites you tried it against, by URL.
- Whether you tested with more than one display, and with browsing mode both
  on and off, if your change goes anywhere near either.
- That `swiftlint` passed — it runs as a build phase, so a clean build is
  enough.

And what you *didn't* verify: macOS versions or hardware you couldn't try,
paths you reasoned about rather than ran. That's more useful to a reviewer
than a list with no gaps in it.

## Screenshots

For anything visible, before and after. Drag images straight into the
description.
