# Nifro Roadmap and Working Ledger

> This file is the source of truth for this project. If the scope changes, change it here, do not keep a second copy somewhere else.
> The community-facing English write-up lives in the README; this one is our own working document.

---

## 1. What this is

Nifro is an open-source fork of [sindresorhus/Plash](https://github.com/sindresorhus/Plash).

```
2020-01  Plash goes open source (MIT), showing any web page as a macOS desktop wallpaper
   │
   │     5 years, 4k stars, 158 forks, 0 outside code contributions
   │
2025-10-29  The author deletes the source and squashes the git history into a single "Init" commit
   │         The readme's own words: no contributions came in, App Store clones had to be dealt with, keeping it open source was not worth it
   │
2026-05-05  App Store v2.17.2, still updated with the source closed
   │
2026-08     We pull the last MIT snapshot from before the closure out of a fork, and branch off Nifro
```

**Baseline**: `mattdanielbrown/Plash` @ `364f3e1` (2025-06-10, v2.16.0), MIT license intact. This is the final state of upstream before the source closed.

**Distribution**: Homebrew cask + GitHub Release, not the Mac App Store.

---

## 2. The core judgement

The problem with this app is not code quality. It is two structural assumptions:

### Assumption one: a browser that never stops

It uses a resident WebContent process to show content that **changes once a minute** (clocks, weather, calendars, dashboards).

### Assumption two: it is not a real wallpaper

It is a transparent borderless window on the `.desktop` layer. The consequence the upstream FAQ admits itself: the menu bar cannot pick up its colour. Downstream of that are the Mission Control gesture giving the game away (#182), the way Stage Manager treats it as a window rather than as a background, and that run of `collectionBehavior` patches in `DesktopWindow.swift`.

### The fix: two backends

```
                    ┌─ Backend A "snapshot" ← the default
                    │    offscreen WKWebView ──takeSnapshot──┬─→ A1 the desktop window's CALayer
Website             │    web process suspended once drawn    │      (transparency / zoom / multiple displays kept)
  backend: snapshot │                                        └─→ A2 NSWorkspace
        or live ────┤                                               .setDesktopImageURL
                    │                                               ↑ becomes a real wallpaper
                    └─ Backend B "live" ← on demand
                         the window + resident webview we have now
                         left for the pages that really do need animation / interaction
```

A2 settles in one go: the menu bar picking up colour, Mission Control and Stage Manager behaviour, the picture surviving after the app quits, and idle power that really is 0. The price is no interaction and a floor on how often it can refresh. **This route has not been verified yet — it needs `setDesktopImageURL` tried under the sandbox.**

The 24 real entries in sites/ are already sorted along this line: 18 snapshot, 6 live (screensavers, WebGL fluids, continuous 3D scenes).

---

## 3. Status at a glance

```
Upstream issue triage   35 → DO 17 / LATER 13 / REJECT 1 / OBSOLETE 4
                        See UPSTREAM-ISSUES.md. The 35 compress into only 8 mechanisms
Blocked                 1 — P6, until setDesktopImageURL is verified under the sandbox
```

---

## 4. Power (the P series)

Upstream stops for three reasons only: manually disabled, screen locked, on battery (`AppState.swift:125`). **Nothing about occlusion at all.**

| | Optimisation | Status | Notes |
|---|---|---|---|
| **P6** | The real-wallpaper route (A2) | **Blocked, until `setDesktopImageURL` is verified under the sandbox** | The biggest payoff and the biggest risk |
| ~~P7~~ | ~~Go opaque when the content fills the screen~~ | **Not doing** | The saving cannot be measured, and it would need a user switch that turns the screen black on a page with a transparent background. Settings whose payoff is unclear do not get added |
| ~~P9~~ | ~~Configurable reload strategy~~ | **Not doing** | No issue ever asked for it, I thought it up myself |

---

## 5. Regions: more than one page on a screen (the L series)

Today a website gets a display. The next thing worth having is a website getting *part* of one, so a
screen can hold several — left and right, or a full-height page on the left with two stacked on the
right.

Not free placement. Anything can go anywhere is a layout editor, and a layout editor is a bigger
project than this whole app: drag handles, collision, z-order, snapping, persistence per display
size, and a settings screen nobody can hold in their head. What is proposed instead is a small set of
splits, chosen from a menu, each region behaving exactly like a display does now.

```
one              left / right        left, and right split
┌───────────┐    ┌─────┬─────┐       ┌─────┬─────┐
│           │    │     │     │       │     │  B  │
│     A     │    │  A  │  B  │       │  A  ├─────┤
│           │    │     │     │       │     │  C  │
└───────────┘    └─────┴─────┘       └─────┴─────┘
```

**Why this is worth doing.** Combined with zooming, a region turns a website into a desktop tile. The
case that makes it concrete: the number people actually want on their desktop — how much of this
month's Codex or Claude usage is gone — exists only as a figure on a web page. There is no widget for
it and there will not be one. Zoom to the figure, put it in a corner region, and the rest of the
screen carries something else. That is a class of thing, not one example: a build dashboard, a
deployment status, a countdown, a single number from a page nobody will ever ship an app for.

| | Item | Status | Notes |
|---|---|---|---|
| **L1** | A website occupies a region of a display rather than the whole display | To do | The model change: `WallpaperScene` is keyed by `Display`, and a region means several per display. `Display` stops being the key |
| **L2** | A fixed set of splits, offered in the menu | To do | Halves, thirds, and one-plus-two-stacked. Fixed fractions, so the same choice survives a different display size the way `Zoom` does |
| **L3** | Which region takes a click | To do | Browsing Mode and hold-to-interact currently mean "the wallpaper". With regions they have to mean one of them |

**The three things that make this harder than it looks**, named now so they are not discovered later:

- **Two things sizing one window.** The occlusion policy owns the window's frame today
  (`DesktopWindow.reducedRegion`). A region owns it too. That is the same collision that made cropping
  and the visibility policy fight until cropping stopped moving the window at all — so a region has to
  be the window's *base* frame, with occlusion shrinking inside it, never the other way round.
- **One web process per region.** Three regions is three `WKWebView`s and three web processes. The
  whole P series exists to avoid paying for rendering nobody is looking at, and this multiplies the
  bill. It makes the snapshot backend more important, not less: a tile showing one number is the
  clearest case in the app for photographing a page instead of running it.
- **Regions are not a layout the user drew.** They are fractions of a display. Storing them as
  fractions, like `Zoom` stores a centre and a magnification, is what keeps a two-region setup
  working when the display changes or the laptop is unplugged from the monitor.

---

## 6. Engineering (the E series)

| | Item | Status |
|---|---|---|
| ~~E16~~ | ~~Universal binary~~ | **Not doing** (your call). One thin build per architecture instead |

---

## 7. Signing and distribution

From looking into what [AeroSpace](https://github.com/nikitabobko/AeroSpace) actually does:

| | AeroSpace | Nifro | Reason |
|---|---|---|---|
| Signing | A self-signed certificate on the machine | Developer ID / ad-hoc | To Gatekeeper a self-signed certificate is exactly the same as ad-hoc, so it is a wasted step |
| Notarization | Not done | Done once there is an account | Nifro is a sandboxed GUI app, and its users are not in the habit of typing `xattr` the way tiling WM users are |
| Releasing | A local script plus dragging the zip by hand | A tag triggers Actions | Releasing from a local machine is not reproducible |
| cask | A separate tap repository | `Casks/` in this repository, written back by CI | One less repository to maintain |
| livecheck | None | Yes | Useful later if this goes to the main homebrew-cask repository |

**Design**: one workflow that picks its path from whether `secrets.MACOS_CERTIFICATE_P12` exists. Releases work right now without a paid account; buying one later takes 6 secrets plus deleting the `postflight` block from the cask, and not one line of YAML changes.

The difference for users:

| | Installed with brew | Downloaded zip, double-clicked |
|---|---|---|
| With an account (notarized) | Nothing | One "downloaded from the internet" confirmation |
| Without an account (ad-hoc) | Nothing (postflight strips the quarantine attribute) | **Blocked outright**, with only "Move to Trash / Cancel" |

So while there is no account, the README's install section has to put brew first. The full manual is in `docs/RELEASE.md`.

---

## 8. Explicitly not doing (do not raise again)

| | Proposal | Why it was turned down |
|---|---|---|
| **X1** | Change web engine (Electron / Tauri / CEF) | WKWebView is a system process shared with Safari; anything else costs more. The problem is scheduling, not the engine |
| **X2** | Rewrite in pure SwiftUI | The `NSMenu` + `NSWindow` we have is fast and correct; moving to `MenuBarExtra` would be a step back |
| **X3** | Tuist / XcodeGen | `project.pbxproj` is only 694 lines, nowhere near the size where conflicts become a disaster |
| **X4** | A dependency injection framework, a plugin system | There is no second implementation, so there is nothing to base the abstraction on |
| **X5** | Use only the CLT as a type-checking gate | **Tried, failed**: KeyboardShortcuts uses `#Preview`, that macro plugin ships only with Xcode, and the Command Line Tools cannot build the dependency module. Xcode has to be installed |
| **X7** | Camera / screen capture input (`getUserMedia`, `getDisplayMedia`) | The entitlement is per process, which means permanently giving a process that renders arbitrary user URLs around the clock the ability to reach the camera; the shorter a wallpaper app's permission list, the easier it is to check. Capture-card compositing belongs in OBS, surveillance in an NVR client. Upstream [#125](https://github.com/sindresorhus/Plash/issues/125). Note that it **is technically doable**; the reason for refusing is not difficulty |

---

## 9. Reviewed and deliberately left alone (with the data)

The conclusions left behind by two rounds of machine review (the tidy gate, the duplication scan). **What was ruled out is easier to lose than what was built**, so this section matters as much as the work itself: it stops someone raising the same thing next round.
The original reports, line numbers and all, exist only in git history (they were `docs/TIDY-REPORT.md` and `docs/DUPLICATION-REPORT.md`, deleted when this section was written), and the line numbers have gone stale from later refactoring, so do not change code against them.

| | Candidate | Data | Why it stays |
|---|---|---|---|
| R1 | `SecurityScopedBookmarkManager`, 176 lines | Serves 1 to 3 call sites | It sits on the sandbox trust boundary. Replacing it is an equivalent rewrite, and no check would catch getting it wrong |
| R2 | `Cache` + `SimpleImageCache`, 270 lines | Same | Same |
| R3 | `WebsiteIconFetcher`, 200 lines | Same | Same |
| N1 | A batch of hand-written loops replaced by regexes or the standard library | — | An equivalent rewrite. The code being replaced carries domain rules, and we have no assertion that could go red |
| N2 | A batch of changes whose only verification was "it type-checks" | — | There is no answer to "which check would go red" |
| N3 | Two animation durations, 0.25 / 0.35, that look like duplication | 2 places | One is an opacity transition, the other a content fade-in: **they change for different reasons**. Merging them manufactures coupling |
| N4 | Narrowing the visibility of `Website.InvertColors` | Tried twice, red twice | The conformance is declared at the top level rather than inside the type's scope, and the stored property that uses it is read from other files |
| N5 | Narrowing `WallpaperContent` / `RenderingMode` | — | Symbol counting says they only appear in this file, but they are the **types** of two internal properties read across files. Plain counting cannot see that reference edge |
