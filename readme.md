# Nifro

**Make any website your Mac desktop wallpaper.**

A clock, your calendar, a dashboard, a live map, a shader, a nature camera. Anything a browser can
draw, drawn behind your windows.

---

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

**Cropping.** Show one rectangle of a page and nothing else, framed by dragging over the wallpaper.
The window shrinks to the cropped region, so the rest of your desktop stays visible and stays
clickable. That second half is the one CSS cannot do.

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

## Install

```sh
brew tap PathGao/tap https://github.com/PathGao/nifro
brew install --cask nifro
```

Homebrew is the recommended route. Until the project has an Apple Developer ID certificate, a
directly downloaded build is unsigned and Gatekeeper will refuse to open it without a trip through
System Settings; the cask handles that for you. See [docs/RELEASE.md](docs/RELEASE.md).

Requires macOS 15 or later. Separate builds for Apple silicon and Intel rather than one universal
binary, so nobody downloads the half they cannot run.

## Build from source

```sh
git clone https://github.com/PathGao/nifro
cd nifro
open Nifro.xcodeproj
```

Needs Xcode 26 or later. Swift 6 language mode, deployment target macOS 15.

The pure logic behind cropping, occlusion, scheduling, video embedding and the activity classifier
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
├── Crop/         cropping and the drag-to-frame overlay
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
