# Contributing to Nifro

Nifro exists because the app it forked from had five years of users and no
external contributors. That is a fixable problem, and most of the fix is
lowering the cost of a first contribution rather than asking for more effort
from contributors. So: small pull requests are welcome, half-finished ideas in
issues are welcome, and you do not need to write Swift to contribute anything
at all.

## The easiest contribution: add a website

The `sites/` directory is a list of websites that work well as wallpapers,
with the settings that make them work — reload interval, the CSS that crops
the page down to the interesting part, any JavaScript needed to scroll or
dismiss a banner.

Adding one needs no Xcode, no Swift and no build. Two routes, both equally
welcome:

- Open a [Site submission issue](https://github.com/PathGao/Nifro/issues/new?template=site_submission.yml)
  and fill in the URL and your settings. Someone else will land it.
- Or open a pull request against `sites/` directly. Copy an existing entry,
  change the values, done.

Please don't submit a site whose settings include a login, a token or an API
key, or JavaScript that sends anything anywhere. Those cannot go in a list
other people will paste into their own machine.

## Reporting a bug

Use the [bug report form](https://github.com/PathGao/Nifro/issues/new?template=bug_report.yml).
The two fields people most often leave out are the URL it happens on and
whether custom CSS or JavaScript is set on that site — those two answers
resolve a large share of reports on their own, which is why the form asks for
them up front.

One problem per issue. Problems appended to an existing thread get lost while
the first one is being discussed.

## Building it

You need Xcode. Nothing else is required to build — dependencies come in
through Swift Package Manager and Xcode resolves them on first open.

```
git clone https://github.com/PathGao/Nifro.git
open Nifro/Nifro.xcodeproj
```

Then build and run the `Plash` scheme. (The Xcode project, its targets and the
source directory still carry the upstream name. Renaming them is a large,
noisy, conflict-prone diff, so it is being done deliberately rather than in
passing — don't rename them as part of an unrelated change.)

- **Swift 6 language mode.** Concurrency errors are errors, not warnings. If
  you hit one, the fix is almost always to move the work onto the actor that
  owns the state rather than to add `@unchecked Sendable`.
- **Deployment target: macOS 15.0.** New API is available and you should use
  it. There is no back-compatibility to preserve.
- **SwiftLint** runs as a build phase, so a clean build means a clean lint.
  Install it with `brew install swiftlint`; without it the build phase warns
  and continues. The rules live in `.swiftlint.yml`, which uses `only_rules`
  — the enabled set is exactly what is listed there. If a rule is genuinely
  wrong for your code, say so in the pull request rather than adding a
  `swiftlint:disable` in silence.
- Match the style of the file you're in. Indentation and line endings are
  covered by `.editorconfig`.

The pure logic behind cropping, occlusion and scheduling has tests that run without an
app bundle or a window server:

```sh
swift test
```

Everything else has no automated coverage, so the burden of showing a change works
falls on the description of what you ran. See below.

## Where things live

```
Nifro/
├── App/          entry point, state, events, menus, Shortcuts
├── Wallpaper/    the window, the web view, loading, snapshots
├── Visibility/   how much to render, and when to stop
├── Crop/         cropping and the drag-to-frame overlay
├── Sites/        the website model and the curated list
├── Screens/      SwiftUI windows and settings
└── Support/      geometry, scheduling and shared extensions
```

`Support/` is mostly inherited from Plash and shared across the author's apps. Changing it makes
future comparison with upstream harder, so prefer adding beside it over editing inside it.

Adding a file means adding it to the Xcode project as well. The project uses old-style file
references, so a file has to appear in four places in `project.pbxproj`. Xcode does this for you;
adding the file on disk alone compiles nothing and reports no error.

## Pull requests

Write the description as prose about the change, not a log of your afternoon.
The three things a reviewer needs:

1. **What changed**, in a sentence or two.
2. **Why this way** — the mechanism behind the old behaviour, and what makes
   this the right place to fix it. `WKWebView`, AppKit window levels and
   Spaces all have defaults that surprise people; naming the one you hit is
   usually the most useful sentence in the whole description.
3. **What you traded away** — what you left alone on purpose, what you're
   unsure about, which macOS versions or display setups you couldn't test.

Stating the gaps is worth more than a description with no gaps in it. Nobody
has every display configuration.

The pull request template has these as headings. Delete the ones that don't
apply.

Small and focused beats large and complete. If you find a second problem while
fixing the first, mention it in the description or open an issue — a pull
request that does one thing gets reviewed; one that does four gets postponed.

## Relationship to Plash

Nifro is an independent fork of [Plash](https://github.com/sindresorhus/Plash)
by Sindre Sorhus, taken from the last MIT-licensed release (v2.16.0) before
Plash went closed source in October 2025. The fork exists because the MIT
licence permits it, and it stands on years of someone else's work. We are
grateful for that work and we are not competing with it.

What follows from that:

- **Nifro is not Plash and must never claim to be.** Contributions that
  reintroduce the Plash name, icon, artwork, App Store identity or website as
  Nifro's own will be rejected. This is not negotiable, and it applies to
  passing details — a stray "Plash" in user-visible strings, a screenshot of
  the upstream app in our README — as much as to the obvious cases. The
  internal target and directory names are the one exception, and are being
  renamed on their own schedule.
- **Don't file our bugs upstream, and don't file upstream's bugs here.**
  Report bugs you see in Nifro here. Post-2.16.0 Plash is a different program
  and we can't fix it.
- **Code from closed-source Plash releases is not acceptable**, in any form,
  including reimplementations written while reading it. Anything after
  v2.16.0 is not ours to take. If you want a feature that Plash added later,
  describe the behaviour you want and we will build it independently.
- Fixes and ideas that originate upstream from the MIT era are fine — that is
  what the licence is for. Note where they came from so the history stays
  honest.

## Licence

Contributions are made under the repository's MIT licence, the same one Nifro
inherited. There is no CLA and no bot to sign.
