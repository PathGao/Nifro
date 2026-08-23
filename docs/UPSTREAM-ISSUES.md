# Upstream Plash open issue triage

> **This file records analysis, not progress.**
>
> It says what each upstream issue is, which category it goes in, and why it goes there.
> "DO / LATER / REJECT / OBSOLETE" are categories, not to-do states, and none of them says whether
> anything has been built. What Nifro does today is in the [README](../README.md); what shipped in
> which version is in the [releases](https://github.com/PathGao/Nifro/releases); what is still
> planned is in [ROADMAP.md](ROADMAP.md). This file answers a different question: why each request
> got the call it got.
>
> The one exception is the last column of the table, which names the file each answer landed in. It
> is there because reasoning that describes finished work as pending is worse than no reasoning at
> all, and there is no way to tell the two apart without a pointer into the code.
>
> The triage was done against the upstream issue list at one point in time. Reaction counts are not
> updated afterwards, and an issue later closed or answered by upstream is not reflected here.


## 1. The full table

| # | What the user actually wants | Cost | Category | Where it stands |
|---|---|---|---|---|
| [196](https://github.com/sindresorhus/Plash/issues/196) | Video wallpaper should autoplay at login, without pressing play once by hand | S | OBSOLETE | — |
| [195](https://github.com/sindresorhus/Plash/issues/195) | Switching displays should not mean digging three levels into settings | S | DO | **Built.** A Display submenu in `Menus.swift`, `addDisplayItemIfNeeded` |
| [193](https://github.com/sindresorhus/Plash/issues/193) | The `backdrop-filter` blur freezes while the page is not updating | M | LATER | Open. See section 6 |
| [183](https://github.com/sindresorhus/Plash/issues/183) | A click on the wallpaper should open apps like `vscode://` | S | LATER | Open |
| [182](https://github.com/sindresorhus/Plash/issues/182) | One swipe of the Mission Control gesture shows the real desktop picture underneath | L | **REJECT** | X8 in ROADMAP section 9 — the only fix was the real-wallpaper route, and that route ends the app |
| [177](https://github.com/sindresorhus/Plash/issues/177) | When I am working on something else, the wallpaper should dim and go grey instead of taking attention | S | LATER | **Built.** `Visibility/DimWhenUnfocused.swift` |
| [173](https://github.com/sindresorhus/Plash/issues/173) | The custom CSS I wrote works in the browser but not in the app | S–M | DO | **Built.** `Support/Extensions.swift`, `createCSSInjectScript` |
| [169](https://github.com/sindresorhus/Plash/issues/169) | Google Calendar permanently shows "browser version no longer supported" at the top | S | DO | **Built.** `Support/Extensions.swift`, `SSWebView.safariUserAgent` |
| [164](https://github.com/sindresorhus/Plash/issues/164) | Clicking a link should navigate in place, not open a new window | S | LATER | Open, needs a repro |
| [162](https://github.com/sindresorhus/Plash/issues/162) | Shrink the page into a corner of the screen and give the rest back to the desktop | M | DO | Open. The L series, ROADMAP section 5 |
| [158](https://github.com/sindresorhus/Plash/issues/158) | A weather page in the wallpaper should be able to get my location | M | LATER | Open |
| [154](https://github.com/sindresorhus/Plash/issues/154) | Turning it off for a moment and back on should not lose the page I was part-way through | S | DO | **Part built.** `Wallpaper/ScrollRestoration.swift` puts the address and the scroll back; the page itself still reloads |
| [140](https://github.com/sindresorhus/Plash/issues/140) | Hold a modifier and click a link to open it in a real browser | S | DO | **Built.** `Wallpaper/WebViewController.swift`, the Command/Option branch |
| [132](https://github.com/sindresorhus/Plash/issues/132) | Alarm sounds in the page need to actually play | ? | LATER | Open, needs more information |
| [127](https://github.com/sindresorhus/Plash/issues/127) | Closing the lid and opening it again should not reload the page state away | S | DO | **Built.** The `reloadOnWake` setting, `App/Events.swift` |
| [125](https://github.com/sindresorhus/Plash/issues/125) | Use a camera or capture card as the wallpaper | M | **REJECT** | X7 in ROADMAP section 9 |
| [114](https://github.com/sindresorhus/Plash/issues/114) | After the shortcut switches to browsing mode, let me type straight away without another click | S | DO | **Built.** `AppState.isBrowsingMode` calls `SSApp.forceActivate()` |
| [93](https://github.com/sindresorhus/Plash/issues/93) | A page as a sidebar, and it has to trigger the mobile layout | M | DO | Open. The L series, ROADMAP section 5 |
| [88](https://github.com/sindresorhus/Plash/issues/88) | List the configured websites from Alfred and switch to one | — | OBSOLETE | — |
| [79](https://github.com/sindresorhus/Plash/issues/79) | A link that 301s off-site should also be handed to the browser | M | LATER | Open |
| [76](https://github.com/sindresorhus/Plash/issues/76) | More ready-made image wallpaper sources | — | OBSOLETE | Absorbed into `sites/` and the Site Gallery |
| [50](https://github.com/sindresorhus/Plash/issues/50) | Click links and buttons on the wallpaper without entering browsing mode | L | LATER | **Built.** `Website.allowsInteraction`, per website |
| [47](https://github.com/sindresorhus/Plash/issues/47) | Switching websites should fade rather than cut | M | DO | **Answered, not as asked.** A straight swap, no fade; see `SwapLoading.adopt` and ROADMAP N6 |
| [41](https://github.com/sindresorhus/Plash/issues/41) | Waking with no network gives a white screen, a red icon and no content at all | M | DO | **Part built.** `Wallpaper/SwapLoading.swift` keeps the old page up; nothing retries when the network returns |
| [39](https://github.com/sindresorhus/Plash/issues/39) | Keep zoom and scroll position across a reload | M | DO | **Built.** `Wallpaper/ScrollRestoration.swift` |
| [37](https://github.com/sindresorhus/Plash/issues/37) | Cookie banners and ads ruin the wallpaper | M | LATER | **Built.** `Wallpaper/ContentRules.swift` |
| [21](https://github.com/sindresorhus/Plash/issues/21) | Do not let me watch the reload happen; show the page once it has loaded | S | DO | **Built.** `Wallpaper/SwapLoading.swift` |
| [16](https://github.com/sindresorhus/Plash/issues/16) | The wallpaper should follow the mouse without entering browsing mode | M–L | LATER | Open |
| [15](https://github.com/sindresorhus/Plash/issues/15) | A static site should not keep a browser process running all day | L | DO | **Built and removed.** ROADMAP sections 2 and 4 |
| [11](https://github.com/sindresorhus/Plash/issues/11) | When the source site goes down, keep the last screen instead of an error dialog | M | DO | **Built.** `Wallpaper/SwapLoading.swift` |
| [9](https://github.com/sindresorhus/Plash/issues/9) | The first load should not start with a block of grey | S | DO | Open. Swap loading is scoped to replacing a page; the first load of a session still goes straight into the window |
| [7](https://github.com/sindresorhus/Plash/issues/7) | Make the first-run welcome presentable | S | DO | **Part built.** The copy in `Screens/WelcomeScreen.swift` is current; it is still an `NSAlert` |
| [5](https://github.com/sindresorhus/Plash/issues/5) | Help polish the App Store copy | — | OBSOLETE | — |
| [4](https://github.com/sindresorhus/Plash/issues/4) | Rotate through several websites, ideally on a time schedule | L | LATER | **Built.** `Sites/Playlist.swift` and `Support/Schedule.swift`, both per display |
| [2](https://github.com/sindresorhus/Plash/issues/2) | One page per screen | L | LATER | **Built.** One `WallpaperScene` per display. ROADMAP section 5.6 |

**Category counts**: DO 17 / LATER 12 / REJECT 2 / OBSOLETE 4, 35 in total. This file is the count; ROADMAP points here rather than keeping its own.

The last column is the only part of this table that goes stale, and it is the only part that is about progress rather than analysis. Nineteen of the 35 have been built since the triage was written, which is why it is here at all: without it a reader has to open the code to find out that half the reasoning below describes work that is done.

**These 35 issues compress into 8 mechanisms**:

```
Swap loading, two web views ─────────────────┬─ #11 keep the old content when a load fails
(Wallpaper/SwapLoading.swift)                ├─ #21 reveal only once loading has finished
                                             ├─ #41 no white screen when waking with no network
                                             ├─ #47 switching sites, answered as a straight swap
                                             └─ #9  first load of a session, still not covered

Session state kept ──────────────────────────┬─ #39  scroll, and zoom
(Wallpaper/ScrollRestoration.swift,          ├─ #127 no reload on wake
 the reloadOnWake setting)                   └─ #154 keep the address across off and on

Blocks: a page as a piece of the desktop ────┬─ #162 still covers the right-hand side after shrinking
(the L series, still to do)                  └─ #93  sidebar, and @media has to take effect

Interaction on the desktop layer ────────────┬─ #50 clicks, per website
(Website.allowsInteraction)                  └─ #16 mouse movement, still open

The snapshot backend (built, then removed) ── #15
A real wallpaper (refused, X8) ────────────── #182
Two separate, genuine bugs ────────────────── #173 CSS injection / #169 user agent
```

---

## 2. DO (17)

### Two web views, swapped on load — #9 #11 #21 #41 #47

In one sentence: **the new page loads in a hidden web view, fades in over the old one only once it succeeds, and is thrown away whole if it fails.**

The upstream author wrote the same plan in three places, #47, #41 and #11, and five years on it has not been built. These five issues are five symptoms of one mechanism:

| issue | Symptom | With swap loading |
|---|---|---|
| #9 | A block of grey on first launch | fades in only once loaded |
| #11 | A dead link from the source site brings up a modal error dialog | on failure the new web view is discarded and the screen still shows the last one |
| #21 | The user can watch the reload happen | gone by construction, with no need for a "wait 5 seconds" setting |
| #41 | No network on wake → red icon and a blank screen | the old content stays, and one reload follows once the network is back |
| #47 | Switching websites cuts | cross-fade |

Cost M (one new file owning the lifecycle of two web views, plus an `NWPathMonitor`). Return: five issues closed at once, two of which, #11 and #41, are genuine bugs. This is the best return in the table.

**Built, as `Wallpaper/SwapLoading.swift`, and three of the five predictions above did not survive contact.** Worth recording, because they are the parts a reader would otherwise assume:

- **#47 did not get a cross-fade, and should not.** The fade that was written took the new content from transparent to opaque, but the page it replaced had already been taken out by then, so what showed through for a third of a second was the desktop. Two pages that have both finished loading can just change places. A real cross-fade needs both in the window at once, which means a container view and a second answer to what `window.contentView` holds — the same ambiguity that produced a blank wallpaper once already. Recorded as N6 in ROADMAP, to be revisited only if the plain swap reads as abrupt.
- **#9 is not covered.** Swap loading is scoped to *replacing* a page: it needs something already on screen worth protecting. The first load of a session goes straight into the window, on purpose, because there is nothing to protect and no reason to put the one path that has to work behind new machinery. So the grey block on first launch is still there, and closing #9 is a separate piece of work.
- **#41 is half covered.** The blank desktop is gone, because a failed load changes nothing on screen and the error goes to the menu bar tooltip. There is still no `NWPathMonitor`, so nothing retries when the network comes back; the wallpaper stays on the last page that worked until the next reload tick.

#11 and #21 are closed outright.

### Custom CSS injection that stays applied — #173

CSS the user wrote for zoom.earth and Google Calendar takes effect when pasted into DevTools, but not when put in the app's CSS box. Three different people describe the same thing across the four comments (2024-12, 2026-02, 2026-03).

The mechanism: `createCSSInjectScript` attaches a `<style>` to `document.documentElement` at `.atDocumentStart`. An SPA rewrites the whole subtree of `documentElement` when it mounts, and the injected style node is cleared away with it — hence "pasting it by hand works, one page reload and it is gone". The smallest fix: inject again at documentEnd, or use a `MutationObserver` to re-attach the style when it falls out of the document.

Note that the `SyntaxError: Can't create duplicate variable: 'style'` jiexiangfan reports in #173 **does not apply to us** — that is a regression in upstream 2.17.0, and the injection script on our baseline is wrapped in an IIFE. That part is already OBSOLETE for us; do not follow it.

Cost S–M. High return: custom CSS is a core way this app gets used, and the app injects both `is-nifro-app` and `is-plash-app` specifically so five years of community Plash CSS snippets keep working. If injection itself is broken, that compatibility decision buys nothing.

**Built**, in `Support/Extensions.swift`, `createCSSInjectScript`, taking the `MutationObserver` route rather than the documentEnd one: a re-attach that only watches `childList` on the root, and re-appending the same element is a move rather than a duplicate. Note the file: there is no `Utilities.swift` in the app any more (only in `ShareExtension/`), which is where the earlier line numbers in this section pointed.

### User agent policy — #169

The user agent used to pin `Version/18.3 Safari/605.1.15`. Google Calendar decides whether a browser is current from the version number, so the wallpaper carried a permanent "This browser version is no longer supported" banner. The reporter filed it in 2024; three more people said "same here" in 2025-03, 2025-04 and 2025-10; the last comment explains how to hide that div with CSS (`.V8Lvo { display: none }`) — after five years, covering it up is all the community has.

The author's reply, that Plash uses the built-in Safari rather than Chrome, answers a different question: the problem is not that the engine is old, it is that we report a version number that expires.

The fix (cost S): stop hard-coding the version number. Either do not override `customUserAgent` at all (WKWebView's default UA carries no `Version/x` of its own; which sites object to that needs testing), or read the version from the system Safari at runtime and build the string. Note that the existing code already has an empty-UA branch for `*.google.com` (two places in `WebViewController.swift`), but it only blanks the UA when the web view is created and `website.url.hasDomain("google.com")`; `calendar.google.com` goes through the navigation-time branch instead — worth unifying while we are in there.

**Built**, as `SSWebView.safariUserAgent` in `Support/Extensions.swift`, the second route with a cheaper source than Safari itself: Safari's marketing version has tracked the macOS major version since macOS 26, so the string is built from `ProcessInfo.operatingSystemVersion.majorVersion` and nothing has to be read off disk. The `*.google.com` branches are still two places in `WebViewController.swift`; unifying them was not done.

### Keeping session state — #39 #154 #127

Three issues, three ways into the same thing:

- #39 keep scroll position and zoom across a reload (the author did zoom back in 2020 — that is `zoomLevelWrapper` in our code; scroll was never done)
- #154 disabling and re-enabling from the shortcut loses the playlist position (the author replied that it should work that way)
- #127 waking from a closed lid forces a reload and the page state is gone

The author left the answer in #39 himself: `WKWebView.interactionState`. That property covers URL, history and scroll position in one go, and can be serialised to disk.

Cost S–M. Return: three issues, and the complaint in #127 is fatal for anyone using Nifro to show a page that holds state.

**Built, and not with `interactionState`.** The reason is in `Wallpaper/ScrollRestoration.swift`: applying an interaction state drives a navigation, so a stale or rejected blob leaves a blank wallpaper with no obvious way back. Scroll restoration fails safe — if it does not work the page is merely at the top — which is the property that matters on a surface nobody is watching when it breaks. So the three issues are answered separately:

- **#39** is `ScrollRestoration.swift`: the document scroll is captured just before a reload and put back after, and the address the page moved itself to is remembered beside the stored one. Zoom was already there as `zoomLevelWrapper`.
- **#127** is the `reloadOnWake` key in `App/Constants.swift`, defaulting to true, with a switch in Settings. The unconditional reload in `Events.swift` is now behind it.
- **#154** is answered in part. The address and the scroll come back, but disabling still calls `suspend()`, which releases the web view, so the page itself reloads. Keeping the page alive instead is M6 in ROADMAP, and it is a per-website switch rather than a policy because it costs a WebContent process for as long as it is held.

The two changes this section predicted alongside did not happen and should not be looked for. `AppState.isEnabled`'s else branch does not load `about:blank`; the comment in `WebViewController.swift` records that as the upstream approach and says why this app replaces the web view with a fresh unloaded one instead, so the WebContent process exits rather than sitting on its memory for the life of the app.

### Cropping, page side and window side — #162 #93

Both issues are direct evidence for the claim in ROADMAP section 5, "Blocks: a page as a piece of the desktop". Nothing left to argue, only to record:

- #162: the user shrank Google Calendar with the CSS the author gave in discussion #139, and "the blank space on the right still covers the desktop" — doing the page side without the window side is the same as not doing it.
- #93: the user wants the page as a sidebar, and points out that changing `:root { width }` in CSS changes the container and not the window, so `@media` queries do not move and what he gets is still the desktop layout. **This is the part the CSS side can never solve**; only actually shrinking the window with `window.setFrame` does it. Two comments backing it.

#93 adds a hard requirement the CSS approach cannot meet: it is the reason L1 in ROADMAP is a real window frame rather than a stylesheet. Neither issue is answered yet. Zoom picks *which part* of a page; the L series is *where on the desktop it goes*, and `DesktopWindow.reducedRegion` is the property that will carry it — currently read and never written, which is recorded as R6 in ROADMAP so nobody deletes it as dead.

### Static mode — #15

The author opened this one himself in 2020, and the plan is the snapshot backend described in ROADMAP section 2: load → screenshot → show the screenshot as the desktop → update on the reload interval. In the comments firrae asks whether taking screenshots costs more CPU, and the author answers that a shot is only taken on an interval tick, at most once a second and usually once a minute, so it costs less. Someone in the naming discussion proposed **Snapshot**.

**This was built here, measured, and taken out again — around 2400 lines across two removals.** The direction is not pending; it is closed, and the measurements are the reason. Two of them:

- **A snapshot renderer cannot photograph the pages worth photographing.** A window that is not on screen makes WebKit report `visibilityState: hidden`, so `requestAnimationFrame` never runs and anything drawing to a canvas comes out blank. On one page: offscreen, `canvas=none`, 4 tiles, 232KB; on screen, `canvas=2790×1538`, 44 tiles, 2452KB. Overriding `document.hidden` from JavaScript does not help, because the decision is below it.
- **Two backends cannot coexist**, because each owned the answer to "what is being rendered right now", which is the same answer Browsing Mode changes. Entering Browsing Mode reloaded, leaving it reloaded again, both showed the desktop while they did, and a snapshot finishing could take the page out from under someone reading it.

The full accounting is in ROADMAP sections 2 and 4, including the three conditions any of it has to meet before it comes back. **Do not re-propose the snapshot backend as the answer to #15 without reading them.** #15 remains a real complaint with no cheap answer, which is a different thing from an unstarted plan.

### Display selection in the main menu — #195

The user moves between home and the office and changes "Show on" every day, but has to go into the General page of settings to do it. He almost never changes the website, only the screen.

Cost S: add a Display submenu in `Menus.swift`, still reading and writing `Defaults[.display]`.
Order matters: if #2 (one page per screen) lands first, the shape of this menu changes with it, from "pick a screen" to "what goes on each screen", so either write the dozen-odd lines now and redo them at #2, or wait and do the two together. Either is fine; doing half is not.

**Built**, as `addDisplayItemIfNeeded` in `Menus.swift`, and the ordering worry turned out to be moot: multi-display landed first, so the menu was written once against scenes rather than twice.

### Actually taking focus when entering browsing mode — #114

The user writes in Nifro, and after the shortcut switches to browsing mode he still has to click the window by hand before he can type, because JS `onfocus`/`onblur` do not fire either. His workaround is to synthesise a mouse click with Alfred and AppleScript.

The code already calls `makeKeyAndOrderFront(self)` when `DesktopWindow.isInteractive = true`, but the app is an accessory app, and without `SSApp.forceActivate()` it never gets real keyboard focus. Cost S.

**Built**, and it was exactly that one call: `AppState.isBrowsingMode`'s `didSet` calls `SSApp.forceActivate()`.

### Modifier-click opens a link in the default browser — #140

The user shows a monitoring dashboard in Nifro; links within the site always open inside Nifro, and he wants to hold shift+cmd, click, and hand one to a real browser to look into it.

The check already in `WebViewController.decidePolicyFor` is `Defaults[.openExternalLinksInBrowser] && a different host`; add "or a modifier key is currently held". Reading modifiers already has a precedent in the code (`NSEvent.modifiers != .option`). Cost S, about ten lines. It only means anything in browsing mode.

**Built**, in `WebViewController.decidePolicyFor`, as its own branch ahead of the settings check rather than an extra clause inside it: Command or Option held sends the link out whatever the settings say, which is also the only way to open a *same-site* link externally without changing a setting first.

### First-run welcome — #7

Upstream this one is "replace the stopgap NSAlert with a proper SwiftUI welcome window". For us it was first of all a factual error: the copy said "droplet icon" after the icon had been replaced with the curtain outline, and explained upstream's limited multi-display support.

**The copy is fixed.** `Screens/WelcomeScreen.swift` now points at the menu bar icon, Browsing Mode and the Site Gallery, with nothing in it that the app contradicts. It is still two stacked `NSAlert`s, which is the part upstream was actually asking about, and it is still worth doing — a modal alert on first launch is a poor first impression of an app whose whole pitch is what the desktop looks like. Cost S, and nothing depends on it.

### A one-line safeguard related to #196 (categorised OBSOLETE, recorded here)

The reporter of #196 came back two days later to say that once he had played it by hand, autoplay worked from then on — that is WebKit's per-site autoplay quota, and the author could not reproduce it. The issue itself is void. But if suspending media playback while the wallpaper is covered is ever built — it was, and it came out with the rest of the power machinery — confirm that video carries on playing by itself once the wallpaper is visible again, so this issue does not turn into a bug of ours.

---

## 3. LATER (12)

**Five of the twelve have since been built.** They are listed first, briefly, because the reasoning that put them here was about sequencing rather than about whether they were worth doing, and sequencing arguments stop being interesting once the work exists.

| # | Why it was LATER | Where it landed |
|---|---|---|
| **#2 multi-display** | The most-requested item in the table: 47 👍, 36 comments, six years of people bumping it. For five years the answer was a way around it — run several copies of Plash with different bundle ids — and the community ended up writing a `plash-cloner` script to clone the app. It was blocked on `AppState` being a singleton with one window and one web view. Most people wanted **a different URL per screen** (ianiv's comment, +25), not one page spread across all of them, and that is what was built | One `WallpaperScene` per display, each with its own website. **Written on a one-display machine and never run on two** — see the D series, ROADMAP section 5.6, which is a list of unchecked claims rather than a list of known bugs |
| **#4 playlist** | Blocked behind multi-display for the same reason. The comments add a request the issue body does not state: scheduling by time of day, GitHub activity in the morning and something else at night. The author's 2021 answer was that Plash is scriptable and you can rotate it from bash | `Sites/Playlist.swift`, with the hour arithmetic as a free function in `Support/Schedule.swift` so a window that wraps midnight is testable without a clock. Rotation and the schedule are one mechanism, because both answer "which of this display's websites should be showing right now". Both are per display |
| **#177 dim / desaturate when unfocused** | The idea is right, and macOS does the same thing to its own desktop widgets. It was parked as a rider on the occlusion detection the power machinery was going to provide | `Visibility/DimWhenUnfocused.swift`, and it needed no occlusion detection at all: "focused" is the Finder being frontmost, which is what clicking the desktop does. The power machinery it was waiting on has since been deleted, so waiting would have meant waiting forever |
| **#50 clicks on the wallpaper** | Ten comments from users who want interactive widgets on the desktop — a calculator, buttons, a timer. Half was already solved upstream: the 2020 commit that stopped browsing mode covering every window, here `bringBrowsingModeToFront`, off by default; and `isBrowsingMode` is a persisted Default, so "start up in browsing mode" already worked. What was unsolved is taking clicks without also taking selection and scrolling | `Website.allowsInteraction`, a per-website switch, carried into `DesktopWindow.allowsPassiveInteraction` by `WallpaperScene`, which is just `ignoresMouseEvents` inverted. Per website rather than global, because a page that swallows clicks is a wallpaper you cannot click past |
| **#37 cookie banner / ad blocking** | The author opened it himself and marked it himself as a large amount of work that would not happen soon. Maintaining a filter list is indeed not something to take on | `Wallpaper/ContentRules.swift`, taking exactly the middle route this entry argued for: `WKContentRuleListStore.compileContentRuleList` against a URL the user points at, no rules of our own, and a fetch that fails leaves the previously compiled list in place rather than dropping protection |

**The other seven:**

| # | Why not now |
|---|---|
| **#193 backdrop-filter freezes** | See “Issues that are really performance issues” below. It is WebKit's own render throttling, not our code. It needs reproducing on our baseline first; the reporter gave a complete about:blank repro script. Kept in LATER rather than closed because the same throttling is what would degrade any future attempt to replace a live page with a still, and this issue is the ready-made regression case for it. No cost estimate before a repro. |
| **#183 URL scheme opens an app** | The closest thing in the table to a request we will not take, without crossing the line. A wallpaper page that can launch local apps is a clear attack surface, but the reporter proposed the right design himself: off by default, an allowlist, and a confirmation the first time; he also changed one line locally to check that it does not break the sandbox. It only affects people who turn the switch on. The return is small (1 👍), so it sits behind every S item. **If it is built, off by default is a hard requirement.** |
| **#158 geolocation** | The author opened this one himself, and judged it himself: it would have to be implemented by hand, he does not plan to, and he hopes Apple supports it natively (it did not after WWDC24). The workable path is injecting a `navigator.geolocation` shim into the `.page` world, backed by CoreLocation. **But that means giving location permission to a process that renders arbitrary user URLs around the clock**, which is the same argument as #125, differing only in a one-off coarse location versus a live video stream. If it is built it has to be off by default with per-site permission. One person backing it. |
| **#164 links navigating in place** | Needs more information. The request was written in 2024 (2.x), and in the current code `target=_blank` only opens a new window in browsing mode (`createWebViewWith` loads in place when `targetFrame == nil`), and back and forward gestures are already on (`allowsBackForwardNavigationGestures = true`). **The missing information**: whether what he hit was a window opening or something else. Either wait for a repro, or build it as a setting for "always navigate within the same view" (S). |
| **#132 sound in the page does not play** | Needs more information. The title says "Force mute", but the body asks for the opposite: he turned Mute audio off and the page's Web Audio (`AudioContext` plus `Audio().play()`) still makes no sound. Our `muteAudio()` only handles `<audio>`/`<video>` elements and does not reach AudioContext, so the mute setting is not the cause; more likely WebKit's autoplay policy wants a user gesture, and the desktop layer has no gesture at all. **The missing information**: whether setting `mediaTypesRequiringUserActionForPlayback = []` on our baseline unblocks AudioContext. If the only route is the private `_WKWebsiteAutoplayPolicy`, this goes straight to the X series. |
| **#79 301 redirects to external links** | A genuine bug. The `openExternalLinksInBrowser` check compares hosts only at the moment `navigationType == .linkActivated`; when the server 301s off-site the navigation type is already `.other`, so the result of the redirect stays inside Nifro. The fix is to remember that this navigation came from a user click, and compare hosts again at `didReceiveServerRedirect` or at the response stage. Cost M (state has to be carried through the navigation lifecycle), return moderate to small. Swap loading has since landed on the same navigation path, so the cheap moment to do this together has passed; it is now its own piece of work. |
| **#16 mouse following on the desktop layer** | The other half of #50, and the half that did not come with it. #50 was about clicks and is done; this is about a particle or fluid background that tracks the pointer (+1 ×2, hooray ×3). It is cheaper to implement than it looks: `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` needs no accessibility permission, and the coordinates can be turned into synthesised JS events. **The cost is the problem, not the mechanism** — a 60 Hz global monitor plus an `evaluateJavaScript` every time, on a surface that is meant to be cheap to leave running. If it is built it has to be per site like `allowsInteraction`, throttled, and its power cost written down where a user choosing it can see it |

---

## 4. REJECT (2)

### #182 the Mission Control gesture shows the real desktop underneath — grounds: the only fix ends the app

The wallpaper is a window on the `.desktop` layer, so a Mission Control swipe slides it aside and shows the actual desktop picture behind it. Stage Manager treats it as a window for the same reason. Both are symptoms of one thing: it is not really the wallpaper.

The only fix is to make it really the wallpaper — render the page to an image and hand that to `NSWorkspace.setDesktopImageURL`. That was P6 in the roadmap for a long time, marked blocked rather than refused. It is refused now, as **X8**: a wallpaper set that way is a picture, so clicks, Browsing Mode, scrolling and signing into anything all go, and those are what this app is. See the roadmap for the full argument.

What was worth having out of it has been taken separately: the menu bar picks up the website's colour, from a band, without the page ever being behind the menu bar.

### #125 camera / capture-card input — grounds: outside what the app is for, a process-level permission surface, and better tools already exist

The request: use a camera or an HDMI capture card as the wallpaper; failing that, make pages that call `getUserMedia` work. 3 👍 and four comments, one of whom changed the Xcode project himself to confirm it works (adding `NSCameraUsageDescription`, the camera entitlement and a permission request), another running a Mac mini as a surveillance wall.

**It is technically possible** (`navigator.mediaDevices` is undefined precisely because the entitlement is missing), so the reason for declining is not difficulty:

1. **The entitlement is process-level, not per-site.** Once the camera permission is signed in, this process — which renders **whatever URL the user gives it**, around the clock — permanently has the ability to read the camera. The macOS permission prompt is only the second gate; the first gate, that the app should not have the ability at all, is one we would be giving up ourselves. The shorter a wallpaper app's entitlement list, the better: it is one of the few things a user can check.
2. **Outside what the app is for.** It is a wallpaper, not video capture software. A request the size of three people buys every user seeing Nifro ask for the camera in Privacy & Security.
3. **Better tools already exist.** Capture cards and multi-source video compositing go through OBS (virtual camera, or full-screen projection with the window kept at the back); a surveillance wall goes through a dedicated NVR client. These tools already do this, and do it better than we would.

**Recorded as X7 in ROADMAP section 9**, written down together with screen capture / `getDisplayMedia`, so it does not need discussing again later.

The same argument applies to #158 (location), but that one stays in LATER: a one-off coarse location and a live video stream are different sizes of risk, and weather pages are a mainstream use. Even then it would have to be off by default with per-site permission.

---

## 5. OBSOLETE (4)

| # | Why it is void |
|---|---|
| **#196 video autoplay** | The reporter's own conclusion two days later: play it once by hand and autoplay works from then on (WebKit's per-site autoplay quota), and the author could not reproduce it. The issue is a misunderstanding. The only thing to watch is that suspending media playback does not turn it into a real bug; see the end of “DO” above. |
| **#88 Alfred listing the configured websites** | The author's 2021 plan was to wait for Shortcuts for Mac and return the website list through App Intents. **Our baseline already has it**: `WebsiteAppEntity` in `Intents.swift` comes with an `EnumerableEntityQuery`, paired with `SetCurrentWebsiteIntent`, so Alfred and Shortcuts can list them and switch today. No deeplink needs building. |
| **#76 more image wallpaper sources** | Upstream's approach was to invite people to each fork his `plash-bing-photo-of-the-day` repository. Our equivalent is `sites/` — a schema-checked list with a way to submit — and the in-app Site Gallery that reads it (`Screens/SiteGalleryScreen.swift`, backed by `Sites/SiteCatalog.swift`). Both exist. That is a better direction than N scattered repositories: one central list with one-click adding, and entries contributed between releases show up without an app update. Void as an issue, and absorbed as a request. |
| **#5 App Store copy** | We are not going on the Mac App Store; see ROADMAP section 1, and section 8 for how distribution works instead. Every store link and the rating prompt were removed with the fork. |

---

## 6. Issues that are really performance issues

Several issues talk about a feature on the surface while really talking about power and render scheduling. That reading was the argument for the power machinery, and the machinery has since been built and removed (ROADMAP sections 2 and 4). What the reading was worth is in the one issue that turned out to be a check on it rather than a case for it.

**#193 is worth a line of its own**: it is a reality check on the thinking that produced the P series, and it points both ways at once. WebKit already throttles by itself — while a page is not updating it will not even bother recomputing the backdrop. So suspending inactive content is a direction the engine agrees with, and at the same time **anything that replaces a live page with a still will visibly degrade the pages that live on CSS animation and filters**. Those are the same pages people put on a wallpaper.

That is the shape of the whole finding recorded in ROADMAP section 2: the offscreen renderer photographed blank for exactly the pages worth photographing. #193 said so from the outside before the measurement said so from the inside. If a still-based path is ever tried again, it has to be switchable off per site, and the repro script in this issue's body is the regression case that goes with it.
