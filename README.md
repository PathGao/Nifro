<p align="center">
  <img src="assets/icon-256.png" alt="Nifro" width="180">
</p>

<h1 align="center">Nifro</h1>

<p align="center">
  <b>Make any website your Mac desktop wallpaper.</b><br>
  A clock, your calendar, a dashboard, a live map, a shader, a nature camera.<br>
  Anything a browser can draw, drawn behind your windows.
</p>

<p align="center">
  <a href="https://github.com/PathGao/Nifro/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/PathGao/Nifro?label=release&color=0453ab"></a>
  <a href="https://github.com/PathGao/Nifro/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/PathGao/Nifro/actions/workflows/ci.yml/badge.svg"></a>
  <a href="license"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/builds-arm64%20%C2%B7%20x86__64-lightgrey">
</p>

<p align="center">
  <a href="https://github.com/PathGao/Nifro/releases/latest"><b>Download</b></a>
  ·
  <a href="sites/">Site list</a>
  ·
  <a href="sites/CANDIDATES.md">Candidate sites</a>
  ·
  <a href="docs/ROADMAP.md">Roadmap</a>
  ·
  <a href="CONTRIBUTING.md">Contributing</a>
  ·
  <a href="README.zh-Hans.md">简体中文</a>
</p>

---

## Install

```sh
brew tap PathGao/tap https://github.com/PathGao/Nifro
brew install --cask nifro
```

Or [download the latest release](https://github.com/PathGao/Nifro/releases/latest) — take the
`arm64` build on Apple silicon and the `x86_64` build on Intel. There is no universal binary, so
nobody downloads the half they cannot run.

Builds are signed with the project's own certificate rather than an Apple Developer ID one, so they
are not notarized and Gatekeeper stops a directly downloaded one until you allow it in System
Settings. The cask does that for you, which is why it is the recommended route.
See [docs/RELEASE.md](docs/RELEASE.md).

Requires macOS 15 or later.

## Where this came from

Nifro is an open-source fork of [Plash](https://github.com/sindresorhus/Plash) by Sindre Sorhus,
taken from the last MIT-licensed snapshot before that project closed its source in October 2025.
Plash itself is still developed and still on the App Store; if you want the original,
[get it there](https://sindresorhus.com/plash). Nifro is not it, does not claim to be, and uses none
of its branding or artwork.

The fork exists because the app's five-year issue tracker is full of good requests that needed
changes the original could not take on, and because the code, once you read it, turns out to rest on
two assumptions worth revisiting:

- It keeps a browser rendering continuously to display content that changes once a minute.
- It is not really a wallpaper. It is a transparent window sitting just above one.

Undoing those is what this fork is about. See [docs/ROADMAP.md](docs/ROADMAP.md) for the plan and
[docs/UPSTREAM-ISSUES.md](docs/UPSTREAM-ISSUES.md) for a triage of every open upstream issue.

## What it does that Plash does not

**Only renders what you can see.** A wallpaper keeps painting frames under every window you open.
Nifro measures how much of it is actually visible and renders only that — down to the strip behind
the Dock, which macOS itself never reports as hidden.

**Works out whether a page needs rendering at all.** Most wallpapers load, settle, and then are a
picture. Nifro watches one for a minute; if nothing moves it photographs it on a schedule instead of
keeping a browser open all day, and changes its mind if the page starts moving.

**Zoom into part of a page.** Drag a rectangle over the wallpaper and that part fills the screen.
The page still lays out at full size, so the site does not reflow into something you did not frame,
and the region is re-rendered rather than scaled up, so text stays sharp.

**One page per display.** Assign a website to a screen; each screen gets its own.

**A playlist with hours.** Rotate through the websites on a display, and let a website say when it
is allowed to be up. A schedule never leaves a display empty.

**Hold a key to use the page.** Press and hold to click, scroll and zoom; let go and it is a
wallpaper again.

**Audio per website.** A clock should never make a sound, a live stream is pointless without one.

**A curated site list.** Pages that work well as wallpapers, each carrying the settings that make it
work. The in-app gallery reads it straight from this branch, so a merged entry appears without waiting
for a release. Suggesting one takes a form and the app's Copy Settings button.

**English and Simplified Chinese**, throughout the app.

## Build from source

```sh
git clone https://github.com/PathGao/Nifro
cd Nifro
open Nifro.xcodeproj
```

Needs Xcode 26 or later. Swift 6 language mode, deployment target macOS 15.

`./Tools/build-local.sh` builds and installs a test copy signed the way releases are. Do that
rather than signing a build by hand: re-signing an app after Xcode has already signed it replaces
the signature and drops the sandbox entitlement with it, and an un-sandboxed Nifro reads a
different preferences file than a real install.

The pure logic behind zooming, occlusion, scheduling, video embedding and the activity classifier
has tests that run without an app bundle or a window server:

```sh
swift test
```

## Layout

```
Nifro/
├── App/          entry point, state, events, menus, Shortcuts
├── Wallpaper/    the window, the web view, loading, snapshots
├── Visibility/   how much to render, and when to stop
├── Zoom/         zooming, the drag-to-frame overlay and per-website settings
├── Sites/        the website model and the curated list
├── Screens/      SwiftUI windows and settings
└── Support/      geometry, scheduling and shared extensions
```

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). The lowest-effort useful contribution is a site
entry. If you have a page that works well as a wallpaper, that is worth more to this project than
most code.

## License

MIT. See [license](license). Derived from [sindresorhus/Plash](https://github.com/sindresorhus/Plash)
v2.16.0, copyright Sindre Sorhus, used under the same license. The app icon and other artwork are
not derived from Plash.
