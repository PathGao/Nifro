<p align="center">
  <img src="docs/assets/icon.png" alt="Nifro" width="180">
</p>

<h1 align="center">Nifro</h1>

<p align="center">
  <b>Make any website your Mac desktop wallpaper.</b><br>
  A clock, your calendar, a dashboard, a live map, a shader, a nature camera.<br>
  Anything a browser can draw, drawn behind your windows.
</p>

<p align="center">
  <a href="https://github.com/PathGao/nifro/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/PathGao/nifro?label=release&color=0453ab"></a>
  <a href="license"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/builds-arm64%20%C2%B7%20x86__64-lightgrey">
</p>

<p align="center">
  <a href="https://github.com/PathGao/nifro/releases/latest"><b>Download</b></a>
  ·
  <a href="sites/">Site list</a>
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
brew tap PathGao/tap https://github.com/PathGao/nifro
brew install --cask nifro
```

Or [download the latest release](https://github.com/PathGao/nifro/releases/latest) — take the
`arm64` build on Apple silicon and the `x86_64` build on Intel. There is no universal binary, so
nobody downloads the half they cannot run.

Homebrew is the recommended route. Builds are signed with the project's own certificate rather than
an Apple Developer ID one, which keeps the signature stable across updates but does not get them
notarized, so Gatekeeper stops a directly downloaded build until you allow it in System Settings.
The cask does that step for you. See [docs/RELEASE.md](docs/RELEASE.md).

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

**Only renders what you can see.** A wallpaper window covers the whole screen, so the page keeps
painting frames under every maximised window you open. Nifro works out how much of the wallpaper is
actually visible and shrinks the window to that, or holds the last frame when nothing shows. The
common case, where the only wallpaper left is the strip behind the Dock, is one the system's own
occlusion state never reports as hidden.

**Works out on its own whether a page needs rendering at all.** Most pages people use as wallpapers
are documents, maps and dashboards: they load, they settle, and then they are a picture. Nifro
watches what a page actually does for a minute, and if nothing moves it switches to loading,
photographing and closing the page on a schedule instead of keeping a browser open all day. It
changes its mind again if the page starts moving.

**Zoom into part of a page.** Frame a region by dragging over the wallpaper and it fills the screen,
with the navigation, borders and margins around it gone. The page still lays out at the full size of
the screen, so the site does not reflow into something other than what you framed, and the region is
re-rendered rather than scaled up, so text stays sharp. The frame is locked to the shape of your
screen, and it is stored as a place and a magnification rather than a rectangle, so the same website
zoomed the same way works on a second display of a different shape.

**One page per display.** Assign a website to a screen; each screen gets its own.

**A playlist with hours.** Rotate through the websites on a display, and let a website say when it
is allowed to be up. A schedule never leaves a display empty.

**Hold a key to use the page.** Press and hold to click, scroll and zoom; let go and it is a
wallpaper again.

**Audio per website.** A clock should never make a sound, a live stream is pointless without one.

**A curated site list.** [`sites/`](sites/) holds websites that work well as wallpapers, each with
the settings that make it work. Adding one is a single YAML file, no Swift and no Xcode. The
in-app gallery reads the list straight from this branch, so an entry merged here shows up without
waiting for a release.

**English and Simplified Chinese**, throughout the app.

## Build from source

```sh
git clone https://github.com/PathGao/nifro
cd nifro
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
