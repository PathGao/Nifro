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

## 2. The plan this project started with, and what happened to it

It began from two structural complaints about upstream, and one design that was going to answer both.

**One: a browser that never stops.** A resident WebContent process for content that changes once a
minute — clocks, weather, calendars, dashboards.

**Two: it is not a real wallpaper.** It is a transparent borderless window on the `.desktop` layer.
Upstream's own FAQ admits the consequence: the menu bar cannot pick up its colour. Downstream of that
are the Mission Control gesture giving the game away (Plash#182), Stage Manager treating it as a
window, and the run of `collectionBehavior` patches in `DesktopWindow.swift`.

The answer was two backends: a `snapshot` one that renders a page offscreen, photographs it and lets
the web process go — either into the window's layer, or (**A2**) through
`NSWorkspace.setDesktopImageURL`, which would make it a genuine macOS wallpaper — and a `live` one,
the resident web view we have now, kept for pages that really do animate.

**None of it survived, and the reasons are worth keeping:**

| What was claimed | What was found |
|---|---|
| A snapshot renderer can photograph any page | It cannot photograph the interesting ones. A window that is not on screen makes WebKit report `visibilityState: hidden`, so `requestAnimationFrame` never runs and anything drawing to a canvas photographs blank. Measured on one page: offscreen, `canvas=none`, 4 tiles, 232KB; on screen, `canvas=2790×1538`, 44 tiles, 2452KB. Overriding `document.hidden` in JavaScript does not help — the decision is below it |
| Two backends can coexist | Each owned the answer to "what is being rendered right now", which is the same answer Browsing Mode changes. Entering Browsing Mode reloaded, leaving it reloaded again, both showed the desktop while they did, and a snapshot finishing could take the page out from under someone reading it. Every fix exposed the next |
| The menu bar problem needs a real wallpaper | It did not. The page is kept out of the menu bar strip and an opaque band takes the website's colour, which is the part anyone actually wanted |

So the machinery came out — around 2400 lines across two removals — and the app went back to what
upstream does: one live page that stops only when disabled, when the screen is locked, or on battery.
**A2 is refused outright now; see X8.** Power comes back one piece at a time under the conditions in
section 4, and it comes back around the live page rather than instead of it.

---

## 3. Status at a glance

```
Upstream issue triage   35 → DO 17 / LATER 13 / REJECT 1 / OBSOLETE 4
                        See UPSTREAM-ISSUES.md. The 35 compress into only 8 mechanisms
Blocked                 nothing
```

---

## 4. Power (the P series)

> **All of this is currently out of the code.** Two rendering backends, occlusion measurement and
> automatic still detection were built, and every one of them turned out to own the answer to "what
> is being rendered right now" — which is the same answer Browsing Mode changes. Entering Browsing
> Mode reloaded, leaving it reloaded again, and both showed the desktop while they did; a snapshot
> finishing could take the page out from under someone reading it; disabling left a colour band
> behind. Each was fixable and each fix exposed the next one, because the machinery was deciding
> something the interaction also decides.
>
> So it came out — 811 lines, back to what upstream does: the page renders, and stops only when
> disabled, when the screen is locked, or on battery. The interaction is the thing this app is; power
> is an optimisation of it, and an optimisation whose benefit was never measured cleanly. It goes
> back in one piece at a time, each with a measurement first and a way to turn it off.
>
> What has to be true before any of it returns:
>
> 1. A measurement of the cost it claims to remove, taken while the machine is otherwise idle, on the
>    state it actually targets — a covered wallpaper, not a browsing session.
> 2. One owner for "what is being rendered". Browsing Mode changing it is the case that broke every
>    version of this.
> 3. A way for the user to turn it off that does not require understanding it.



Upstream stops for three reasons only: manually disabled, screen locked, on battery (`AppState.swift:125`). **Nothing about occlusion at all.**

| | Optimisation | Status | Notes |
|---|---|---|---|
| ~~P7~~ | ~~Go opaque when the content fills the screen~~ | **Not doing** | The saving cannot be measured, and it would need a user switch that turns the screen black on a page with a transparent background. Settings whose payoff is unclear do not get added |
| ~~P9~~ | ~~Configurable reload strategy~~ | **Not doing** | No issue ever asked for it, I thought it up myself |

---

## 5. Blocks: a page as a piece of the desktop (the L series)

Zooming already answers *which part of a page*. It puts that part on the whole screen. The remaining
half of the idea is *where on the desktop it goes* — because a zoomed-in fragment of a page is
usually not something you want at full-screen size. It is something you want in a corner.

So: a website becomes a block. The block's content is what zooming already produces. The block's
place and size are new, and free — with a four-way grid offered so that placing one is a choice
between four obvious answers rather than an exercise in dragging.

```
today                        a block                     the grid
┌───────────────────┐        ┌───────────────────┐       ┌─────────┬─────────┐
│                   │        │            ┌────┐ │       │         │         │
│   zoomed region   │        │   desktop  │ A  │ │       │    1    │    2    │
│   fills the       │        │            └────┘ │       ├─────────┼─────────┤
│   whole screen    │        │  ┌────┐           │       │    3    │    4    │
│                   │        │  │ B  │           │       │         │         │
└───────────────────┘        │  └────┘           │       └─────────┴─────────┘
                             └───────────────────┘        snapped, and optionally
                                                          keeping clear of the Dock
```

The grid's quadrants can be taken from the whole screen or from the area the Dock leaves — a setting,
because the answer depends on where somebody keeps their Dock and whether it hides itself. That
distinction already exists in the code (`screen.pageFrame` against `visibleFrame`); it has never been
offered to the user.

**Why this is worth doing.** A block plus a zoom turns a website into a desktop widget. The case that
makes it concrete is a number that only exists on a web page — how much of this month's Codex or
Claude usage is gone. Nobody is going to ship a widget for that. Zoom to the figure, put the block in
a corner, and the rest of the desktop is still the desktop. That is a class of thing rather than one
example: a build dashboard, a deploy status, a countdown, one number from a page nobody will ever
write an app for.

**Most of this already exists**, which is the main argument for doing it. A scene already owns a
window; `Zoom` already picks the part of the page; `DesktopWindow` already sets an arbitrary frame;
several scenes already run at once. Until this week a crop *did* shrink the window to itself — that
behaviour was removed because a crop was doing two jobs at once and the visibility policy was
fighting it for control of the frame. This brings the second job back as a thing of its own, with an
owner.

| | Item | Status | Notes |
|---|---|---|---|
| **L1** | A website has a place and a size on its display, not just a display | To do | Stored as fractions, like `Zoom` stores a centre and a magnification, so a block survives a change of display |
| **L2** | A four-way grid to snap to, and free placement for anything else | To do | The grid is the affordance, not the model. Free placement is the model |
| **L3** | Whether the grid uses the whole screen or keeps clear of the Dock | To do | A setting. `pageFrame` and `visibleFrame` are both already computed |
| **L4** | Which block takes a click | To do | Browsing Mode and hold-to-interact currently mean "the wallpaper". With blocks they have to mean one of them |

**The three things that make this harder than it looks**, named now so they are not discovered later:

- **Two things sizing one window.** The visibility policy owns the window's frame today
  (`DesktopWindow.reducedRegion`). A block owns it too. That is exactly the collision that made
  cropping and the visibility policy fight until cropping stopped moving the window at all — so a
  block has to be the window's *base* frame, with occlusion shrinking inside it, never the reverse.
- **One web process per block.** Three blocks is three `WKWebView`s and three web processes. The whole
  P series exists to avoid paying for rendering nobody is looking at, and this multiplies the bill. It
  makes the snapshot backend more important rather than less: a block showing one number is the
  clearest case in the app for photographing a page instead of running it.
- **A block is not a window the user can grab.** There are no title bars down there and adding them
  would make the wallpaper into an app. Placing one has to happen the way framing a region does — over
  the wallpaper, with the desktop still visible behind it — or from a menu of grid positions.

---

## 6. Known and not yet fixed (the K series)

Reported while using the app, reproduced, and left alone for now. Each is written down rather than
fixed so that the first release is a thing that exists.

| | What happens | What is known about it |
|---|---|---|
| **K1** | A YouTube video cannot be shrunk back into the YouTube page, so there is no way to sign in | The address is rewritten to the player-only page and framed by a host page, because YouTube's player answers "error 153" when it is the document rather than a frame in one. That gets the video on the wallpaper and takes the site with it: there is no page around the player to navigate, and Browsing Mode has nothing to click into. Bilibili's player is a normal page and does not have this problem, which is why the two behave differently. Whatever the fix is, it has to keep 153 away |
| **K2** | A framed region does not land exactly where it was framed, and part of it can end up under the menu bar | The page lays out in the screen minus the menu bar strip, and the selection is drawn over that same area, so the two should agree exactly. They do not: `DesktopWindow.setFrame` adds a point of height on purpose, and the overlay measures against the window while the region is measured against the page. The edges of what somebody drew are the whole point of drawing it — this is the one to fix first. Two neighbouring faults are fixed: the region was dropped for the seconds a website switch took, and it did not come back after the app was disabled and enabled |
| **K3** | Switching website can take several seconds | It is a page load, and swap loading keeps the previous page up for all of it, so nothing is broken — but nothing tells the user it is working either, and a few seconds of an unchanged wallpaper after choosing a website reads as the choice not having registered |
| **K4** | Nothing is done to reduce what the app costs when nobody is looking at it | Deliberate, for now. See the note under "Power" — the machinery came out because it owned an answer the interaction also owns, and it comes back one piece at a time, each with a measurement first |
| **K5** | No way to choose the app's language from inside the app | It follows the system. macOS has a per-app setting for this — System Settings → General → Language & Region → Applications — and it works today, but nobody finds it, and a person running their Mac in English who wants Nifro in Chinese has no reason to think the answer is three levels into System Settings. A picker in Settings that writes `AppleLanguages` and offers to relaunch would cost little |
| **K6** | The wording is right in places and thin in others | Every setting now says what it does, but they were written one at a time and it shows: some explain the mechanism, some explain the consequence, and a few explain both at different lengths. Worth one pass that reads them as a set rather than as twenty separate answers |
| **K7** | Nothing anywhere handles HDR | Not one line of the app touches it: a page's HDR content is whatever WebKit decides to do with it, and no measurement has been taken of what that is. A wallpaper is the one surface on a Mac that is on screen all day, so getting this wrong is visible all day. It needs a real HDR source and a look at what actually reaches the display before it is worth designing anything |
| **K8** | A Bilibili entry has a generic icon where a YouTube entry has the video's own cover | YouTube publishes a cover at a fixed address derived from the video id, so it costs nothing. Bilibili's is behind `api.bilibili.com`, which is a network request and a JSON field (`data.pic`) rather than a URL you can build. Worth doing, but it is the first place the app would call a site's API rather than just load a page |

---

## 7. Engineering (the E series)

| | Item | Status |
|---|---|---|
| ~~E16~~ | ~~Universal binary~~ | **Not doing** (your call). One thin build per architecture instead |

---

## 8. Signing and distribution

From looking into what [AeroSpace](https://github.com/nikitabobko/AeroSpace) actually does:

| | AeroSpace | Nifro | Reason |
|---|---|---|---|
| Signing | A self-signed certificate on the machine | The same, `Nifro Signing` | To Gatekeeper the two are the same, but the identity is not: a stable certificate keeps the app's designated requirement stable, and the security-scoped bookmarks that hold local-file wallpapers are tied to it. Ad-hoc changes identity every build and breaks them |
| Notarization | Not done | Done once there is an account | Nifro is a sandboxed GUI app, and its users are not in the habit of typing `xattr` the way tiling WM users are |
| Releasing | A local script plus dragging the zip by hand | A tag triggers Actions, one dmg per architecture | Releasing from a local machine is not reproducible |
| cask | A separate tap repository | `Casks/` in this repository, written back by CI | One less repository to maintain |
| livecheck | None | Yes | Useful later if this goes to the main homebrew-cask repository |

**Design**: one workflow that picks its path from whether `secrets.MACOS_CERTIFICATE_P12` exists. Releases work right now without a paid account; buying one later takes 6 secrets plus deleting the `postflight` block from the cask, and not one line of YAML changes.

The difference for users:

| | Installed with brew | Downloaded dmg, double-clicked |
|---|---|---|
| With an account (notarized) | Nothing | One "downloaded from the internet" confirmation |
| Without an account (ad-hoc) | Nothing (postflight strips the quarantine attribute) | **Blocked outright**, with only "Move to Trash / Cancel" |

So while there is no account, the README's install section has to put brew first. The full manual is in `docs/RELEASE.md`.

**Two things about the tap, both deliberate for now:**

The cask lives in this repository, so installing means naming the tap URL: `brew tap PathGao/tap
https://github.com/PathGao/Nifro && brew install --cask nifro`. The shorthand `brew install --cask
PathGao/tap/nifro` resolves to a repository literally named `homebrew-tap`, which would be a second
repository to own, plus a token here with write access to it. Worth doing for one reason rather than
for the shorthand: tapping clones this repository, all 6 MB of source and images, onto every user's
machine and refetches it on every `brew update`. A dedicated tap repository is a few kilobytes. Do it
when there are enough users for that to be somebody else's bandwidth rather than a tidiness argument.

Plain `brew install --cask nifro`, with no tap at all, means being in Homebrew's own cask repository.
That has a notability threshold — 75 stars, or 30 forks, or 30 watchers. Two stars today. It is a
milestone to notice rather than a task to schedule.

### Knowing there is a new version (the U series)

Nothing in the app knows a release exists. There is no Sparkle, no check, no menu item — the only
upgrade path is `brew upgrade`, and only for people who installed that way. Somebody who took a disk
image from the README stays on the version they took until they happen to visit the repository
again. For a menu bar app that runs from login and is rarely opened on purpose, "they happen to
visit" is close to never.

| | Item | Status | Notes |
|---|---|---|---|
| **U1** | Check for a new version and say so | To do. **Do this one first** | One request to `/repos/PathGao/Nifro/releases/latest`, compare `tag_name` against `SSApp.version`, and put "Version 0.2.0 is available" in the menu, linking to the release. No dependency, no entitlement, no keys, no infrastructure — the release API is public and already there. It tells a brew user to run `brew upgrade` and a direct-download user that there is anything to download. Needs a cadence that is not a poll on every menu open, and a way to turn it off |
| **U2** | Download and install it too (Sparkle) | Not now | Much more than U1 looks. Sparkle needs an appcast feed to publish and an EdDSA key pair to sign updates with — a second signing identity to keep for the life of the app, on top of the certificate. A sandboxed app cannot replace itself either; that goes through Sparkle's installer XPC service, which is more entitlements on an app whose short entitlement list is a feature |
| **U3** | Tell Homebrew the app updates itself | Only with U2 | The moment the app can replace its own bundle, the cask has to say `auto_updates true`. Without it `brew upgrade` and the app fight over the same bundle, and brew's idea of the installed version goes stale. U1 alone does not need this, which is another reason to start there |

The first version to benefit from U1 is the one after it ships — 0.1.0 users will not be told about
0.2.0 by an app that could not check. That is an argument for doing it early rather than for doing
it well.

---

## 9. Explicitly not doing (do not raise again)

| | Proposal | Why it was turned down |
|---|---|---|
| **X1** | Change web engine (Electron / Tauri / CEF) | WKWebView is a system process shared with Safari; anything else costs more. The problem is scheduling, not the engine |
| **X2** | Rewrite in pure SwiftUI | The `NSMenu` + `NSWindow` we have is fast and correct; moving to `MenuBarExtra` would be a step back |
| **X3** | Tuist / XcodeGen | `project.pbxproj` is only 694 lines, nowhere near the size where conflicts become a disaster |
| **X4** | A dependency injection framework, a plugin system | There is no second implementation, so there is nothing to base the abstraction on |
| **X5** | Use only the CLT as a type-checking gate | **Tried, failed**: KeyboardShortcuts uses `#Preview`, that macro plugin ships only with Xcode, and the Command Line Tools cannot build the dependency module. Xcode has to be installed |
| **X7** | Camera / screen capture input (`getUserMedia`, `getDisplayMedia`) | The entitlement is per process, which means permanently giving a process that renders arbitrary user URLs around the clock the ability to reach the camera; the shorter a wallpaper app's permission list, the easier it is to check. Capture-card compositing belongs in OBS, surveillance in an NVR client. Upstream [#125](https://github.com/sindresorhus/Plash/issues/125). Note that it **is technically doable**; the reason for refusing is not difficulty |
| **X8** | The real-wallpaper route: render the page to an image and hand it to `NSWorkspace.setDesktopImageURL` (was P6) | Never built, and now refused rather than blocked. It ends the app. A wallpaper set this way is a picture: no clicks, no Browsing Mode, no scrolling, no hold-to-interact, no logging into anything — and interaction is what this app is. Refreshing it means re-rendering and setting it again, which macOS cross-fades, so a clock would cross-fade the whole desktop once a minute. The renderer it needs is the offscreen one that photographs blank for exactly the pages worth putting up (see section 2). Against that: the menu bar colour, which is already solved; Mission Control and Stage Manager behaviour; the picture surviving after the app quits; and idle power, which nobody has measured. A tool that turns a web page into a wallpaper image is a real idea — it is just a different program, and it does not need a menu bar app at all |

---

## 10. Reviewed and deliberately left alone (with the data)

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
| N6 | A cross-fade when switching website, instead of the straight swap | 1 place | Both pages would have to be in the window at once, which means a container view and a second answer to what `window.contentView` holds — the exact ambiguity that cost a blank wallpaper before. Two loaded pages can just change places. Revisit only if the straight swap reads as abrupt |
