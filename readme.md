# Nifro

**Make any website your Mac desktop wallpaper.**

A clock, your calendar, a dashboard, a live map, a shader — anything a browser can draw, drawn behind your windows.

---

## Where this came from

Nifro is an open-source fork of [Plash](https://github.com/sindresorhus/Plash) by Sindre Sorhus, taken from the last MIT-licensed snapshot before that project closed its source in October 2025. Plash itself is still developed and still on the App Store; if you want the original, [get it there](https://sindresorhus.com/plash). Nifro is not it, does not claim to be, and uses none of its branding or artwork.

The fork exists because the app's five-year issue tracker is full of good requests that need changes the original could not take on — and because the code, once you read it, turns out to be built on two assumptions worth revisiting:

- It keeps a browser rendering continuously to display content that changes once a minute.
- It is not really a wallpaper. It is a transparent window sitting just above one.

Undoing those is what this fork is about. See [docs/ROADMAP.md](docs/ROADMAP.md) for the plan and [docs/UPSTREAM-ISSUES.md](docs/UPSTREAM-ISSUES.md) for a triage of every open upstream issue.

## What is different so far

**Stops rendering when nobody is looking.** The window covers your whole screen, so the page keeps painting frames under every maximized window you open. Nifro works out how much of the wallpaper is actually visible and freezes it on its last frame when it is not — including the common case where the only wallpaper left showing is the strip behind the Dock and the menu bar, which the system's own occlusion state does not report as hidden.

**Cropping.** Show one rectangle of a page and nothing else — cut away the navigation bar, the borders, the surrounding furniture. The window shrinks to the cropped region, so the rest of your desktop stays visible and stays clickable. This is the half that matters and the half that CSS cannot do.

**A curated site list.** [`sites/`](sites/) holds websites that work well as wallpapers, each with the settings that make it work. Adding one is a single YAML file — no Swift, no Xcode.

## Install

```sh
brew tap PathGao/tap https://github.com/PathGao/nifro
brew install --cask nifro
```

Homebrew is the recommended route. Until the project has an Apple Developer ID certificate, a directly downloaded build is unsigned and Gatekeeper will refuse to open it without a trip through System Settings; the cask handles that for you. See [docs/RELEASE.md](docs/RELEASE.md) for the details.

Requires macOS 15 or later. Universal builds for Apple silicon and Intel.

## Build from source

```sh
git clone https://github.com/PathGao/nifro
cd nifro
open Nifro.xcodeproj
```

Needs Xcode 26 or later. The project uses the Swift 6 language mode and targets macOS 15.

The pure geometry behind cropping and coverage detection has tests that run without an app bundle:

```sh
swift test
```

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md). The lowest-effort useful contribution is a site entry — if you have a page that works well as a wallpaper, that is worth more to this project than most code.

## License

MIT. See [license](license). Derived from [sindresorhus/Plash](https://github.com/sindresorhus/Plash) v2.16.0, copyright Sindre Sorhus, used under the same license. The app icon and other artwork are not derived from Plash.
