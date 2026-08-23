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
  <a href="https://github.com/PathGao/Nifro/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/PathGao/Nifro/actions/workflows/ci.yml/badge.svg?branch=main&amp;event=push"></a>
  <a href="license"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <a href="#install"><img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple"></a>
</p>

<p align="center">
  <a href="https://github.com/PathGao/Nifro/releases/latest/download/Nifro-arm64.dmg"><img alt="Download for Apple silicon" src="https://img.shields.io/badge/Download-Apple%20silicon-0453ab?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/PathGao/Nifro/releases/latest/download/Nifro-x86_64.dmg"><img alt="Download for Intel" src="https://img.shields.io/badge/Download-Intel-4a4a4a?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://github.com/PathGao/Nifro/releases">Releases</a>
  ·
  <a href="sites/">Adding a site</a>
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
brew trust --cask PathGao/tap/nifro
brew install --cask nifro
```

> [!NOTE]
> Homebrew will not load a cask from outside its own repositories until you say you trust it, because
> a cask can run code after installing. This one runs a single command — it clears the "downloaded
> from the internet" mark macOS puts on the app, which is what lets it open without being turned
> away. Read the whole thing in [Casks/nifro.rb](Casks/nifro.rb) before you trust it.
>
> Plain `brew install --cask nifro`, with no tap and nothing to trust, needs Nifro to be in
> Homebrew's own cask repository, which has a popularity threshold this project has not reached.

### Or download a disk image

| Chip | Download | |
|---|---|---|
| **Apple silicon** | [`Nifro-arm64.dmg`](https://github.com/PathGao/Nifro/releases/latest/download/Nifro-arm64.dmg) | M1 and later |
| **Intel** | [`Nifro-x86_64.dmg`](https://github.com/PathGao/Nifro/releases/latest/download/Nifro-x86_64.dmg) | |

There is no universal binary, so nobody downloads the half they cannot run. Both links always point
at the newest build.

> [!IMPORTANT]
> **The first launch will be refused.** Builds are signed with the project's own certificate rather
> than an Apple Developer ID one, so they are not notarized, and macOS answers a downloaded copy with
> *"Apple could not verify Nifro is free of malware"* — a dialog offering only **Move to Trash** and
> **Cancel**. Neither is the way through. It is:
>
> 1. Press **Cancel**. Not Move to Trash.
> 2. Open **System Settings → Privacy & Security** and scroll to the bottom.
> 3. Press **Open Anyway** on the line naming Nifro, and confirm with your password or Touch ID.
> 4. Press **Open** in the last dialog.
>
> Once, for good — macOS remembers. Control-click → Open, which used to be the shortcut, no longer
> works: Apple removed that route in macOS 15. Installing with brew skips all of it, which is what
> makes brew the recommended one. See [docs/RELEASE.md](docs/RELEASE.md).

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

Undoing those is what this fork is about, and the first one has been harder than it looks: two
rendering backends, occlusion measurement and automatic still detection were all built, and every one
of them turned out to own an answer that Browsing Mode also owns. They came back out — 811 lines — and
go back in one piece at a time, each with a measurement first. [docs/ROADMAP.md](docs/ROADMAP.md) §4
has what that cost and what has to be true before any of it returns;
[docs/UPSTREAM-ISSUES.md](docs/UPSTREAM-ISSUES.md) triages every open upstream issue.

## What it does that Plash does not

**Frame part of a page by moving it.** Drag or two-finger scroll the wallpaper, pinch to zoom, and
what you leave on screen is the region. You aim at the result rather than at the thing you are
framing, and it starts from the region a website already has, so it adjusts as well as creates. The
page still lays out at full size, so the site does not reflow into something you did not frame, and
the region is re-rendered rather than scaled up, so text stays sharp.

**A region survives moving to another display.** It is stored as a place and a magnification rather
than a rectangle, so a screen of a different shape works out its own rectangle around the same part
of the page.

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

The pure logic has tests that run without an app bundle or a window server — the crop and zoom
geometry, the menu bar strip and what the colour band samples from it, schedule windows, which
website is current on which display, video embedding, URL commands and menu word wrapping:

```sh
swift test
```

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). The lowest-effort useful contribution is a site
entry. If you have a page that works well as a wallpaper, that is worth more to this project than
most code.

## License

MIT. See [license](license). Derived from [sindresorhus/Plash](https://github.com/sindresorhus/Plash)
v2.16.0, copyright Sindre Sorhus, used under the same license. The app icon and other artwork are
not derived from Plash.
