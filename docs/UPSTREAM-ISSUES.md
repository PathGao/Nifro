# Upstream Plash open issue triage

> **This file records analysis, not progress.**
>
> It says what each upstream issue is, which category it goes in, and why it goes there.
> **Whether something is done is answered only in [ROADMAP.md](ROADMAP.md)**, and nowhere else.
> "DO / LATER / REJECT / OBSOLETE" are categories, not to-do states.
>
> The triage was done against the upstream issue list at one point in time. Line numbers and reaction counts are not updated afterwards.
> An issue later implemented, overturned, or closed by upstream is not reflected here.
> For the current state, read ROADMAP; for why a call was made at the time, read this.


## 1. The full table

| # | What the user actually wants | Cost | Category | Roadmap ID |
|---|---|---|---|---|
| [196](https://github.com/sindresorhus/Plash/issues/196) | Video wallpaper should autoplay at login, without pressing play once by hand | S | OBSOLETE | — |
| [195](https://github.com/sindresorhus/Plash/issues/195) | Switching displays should not mean digging three levels into settings | S | DO | **F8** (new) |
| [193](https://github.com/sindresorhus/Plash/issues/193) | The `backdrop-filter` blur freezes while the page is not updating | M | LATER | related to the P series |
| [183](https://github.com/sindresorhus/Plash/issues/183) | A click on the wallpaper should open apps like `vscode://` | S | LATER | — |
| [182](https://github.com/sindresorhus/Plash/issues/182) | One swipe of the Mission Control gesture shows the real desktop picture underneath | L | LATER | P6 / A2 |
| [177](https://github.com/sindresorhus/Plash/issues/177) | When I am working on something else, the wallpaper should dim and go grey instead of taking attention | S | LATER | **F9** (new), rides on P1 |
| [173](https://github.com/sindresorhus/Plash/issues/173) | The custom CSS I wrote works in the browser but not in the app | S–M | DO | **F10** (new) |
| [169](https://github.com/sindresorhus/Plash/issues/169) | Google Calendar permanently shows "browser version no longer supported" at the top | S | DO | **F11** (new) |
| [164](https://github.com/sindresorhus/Plash/issues/164) | Clicking a link should navigate in place, not open a new window | S | LATER | needs more information |
| [162](https://github.com/sindresorhus/Plash/issues/162) | Shrink the page into a corner of the screen and give the rest back to the desktop | M | DO | F1 / F2 |
| [158](https://github.com/sindresorhus/Plash/issues/158) | A weather page in the wallpaper should be able to get my location | M | LATER | — |
| [154](https://github.com/sindresorhus/Plash/issues/154) | Turning it off for a moment and back on should not lose the page I was part-way through | S | DO | F7 (extended) |
| [140](https://github.com/sindresorhus/Plash/issues/140) | Hold a modifier and click a link to open it in a real browser | S | DO | **F13** (new) |
| [132](https://github.com/sindresorhus/Plash/issues/132) | Alarm sounds in the page need to actually play | ? | LATER | needs more information |
| [127](https://github.com/sindresorhus/Plash/issues/127) | Closing the lid and opening it again should not reload the page state away | S | DO | F7 (extended) |
| [125](https://github.com/sindresorhus/Plash/issues/125) | Use a camera or capture card as the wallpaper | M | **REJECT** | **X7** (new) |
| [114](https://github.com/sindresorhus/Plash/issues/114) | After the shortcut switches to browsing mode, let me type straight away without another click | S | DO | **F14** (new) |
| [93](https://github.com/sindresorhus/Plash/issues/93) | A page as a sidebar, and it has to trigger the mobile layout | M | DO | F1 / F2 |
| [88](https://github.com/sindresorhus/Plash/issues/88) | List the configured websites from Alfred and switch to one | — | OBSOLETE | — |
| [79](https://github.com/sindresorhus/Plash/issues/79) | A link that 301s off-site should also be handed to the browser | M | LATER | — |
| [76](https://github.com/sindresorhus/Plash/issues/76) | More ready-made image wallpaper sources | — | OBSOLETE | C3 / F6 |
| [50](https://github.com/sindresorhus/Plash/issues/50) | Click links and buttons on the wallpaper without entering browsing mode | L | LATER | **F15** (new) |
| [47](https://github.com/sindresorhus/Plash/issues/47) | Switching websites should fade rather than cut | M | DO | **F12** (new) |
| [41](https://github.com/sindresorhus/Plash/issues/41) | Waking with no network gives a white screen, a red icon and no content at all | M | DO | **F12** (new) |
| [39](https://github.com/sindresorhus/Plash/issues/39) | Keep zoom and scroll position across a reload | M | DO | F7 |
| [37](https://github.com/sindresorhus/Plash/issues/37) | Cookie banners and ads ruin the wallpaper | M | LATER | **F16** (new) |
| [21](https://github.com/sindresorhus/Plash/issues/21) | Do not let me watch the reload happen; show the page once it has loaded | S | DO | **F12** (new) |
| [16](https://github.com/sindresorhus/Plash/issues/16) | The wallpaper should follow the mouse without entering browsing mode | M–L | LATER | **F15** (new) |
| [15](https://github.com/sindresorhus/Plash/issues/15) | A static site should not keep a browser process running all day | L | DO | P5 / F4 |
| [11](https://github.com/sindresorhus/Plash/issues/11) | When the source site goes down, keep the last screen instead of an error dialog | M | DO | **F12** (new) |
| [9](https://github.com/sindresorhus/Plash/issues/9) | The first load should not start with a block of grey | S | DO | **F12** (new) |
| [7](https://github.com/sindresorhus/Plash/issues/7) | Make the first-run welcome presentable | S | DO | **E15** (new) |
| [5](https://github.com/sindresorhus/Plash/issues/5) | Help polish the App Store copy | — | OBSOLETE | — |
| [4](https://github.com/sindresorhus/Plash/issues/4) | Rotate through several websites, ideally on a time schedule | L | LATER | F5 (needs R1) |
| [2](https://github.com/sindresorhus/Plash/issues/2) | One page per screen | L | LATER | F3 (needs R1) |

**Category counts**: DO 17 / LATER 13 / REJECT 1 / OBSOLETE 4.

**These 35 issues compress into 8 mechanisms**:

```
F12 two web views, swapped on load ──────────┬─ #9  fade in on first load
                                             ├─ #11 keep the old content when a load fails
                                             ├─ #21 reveal only once loading has finished
                                             ├─ #41 no white screen when waking with no network
                                             └─ #47 cross-fade when switching sites

F7  session state kept ──────────────────────┬─ #39  scroll + zoom
(WKWebView.interactionState)                 ├─ #127 no reload on wake
                                             └─ #154 keep the current URL across off and on

F1/F2 cropping (page side + window side) ────┬─ #162 still covers the right-hand side after shrinking
                                             └─ #93  sidebar, and @media has to take effect

F15 limited interaction on the desktop layer ┬─ #50 clicks
                                             └─ #16 mouse movement

P5/F4 snapshot backend ────────────────────── #15
P6/A2 a real wallpaper ────────────────────── #182
F10 / F11 separate, genuine bugs ──────────── #173 / #169
```

---

## 2. DO (17)

### F12 two web views, swapped on load — #9 #11 #21 #41 #47

In one sentence: **the new page loads in a hidden web view, fades in over the old one only once it succeeds, and is thrown away whole if it fails.**

The upstream author wrote the same plan in three places, #47, #41 and #11, and five years on it has not been built. These five issues are five symptoms of one mechanism:

| issue | Symptom | With swap loading |
|---|---|---|
| #9 | A block of grey on first launch | fades in only once loaded |
| #11 | A dead link from the source site brings up a modal error dialog | on failure the new web view is discarded and the screen still shows the last one |
| #21 | The user can watch the reload happen | gone by construction, with no need for a "wait 5 seconds" setting |
| #41 | No network on wake → red icon and a blank screen | the old content stays, and one reload follows once the network is back |
| #47 | Switching websites cuts | cross-fade |

The evidence in the current code: `AppState.loadURL` has `delay(.seconds(1)) { desktopWindow.contentView?.isHidden = false }` — a hard-coded one second, still carrying a `// TODO: Fade in the web view`. `SSEvents.deviceDidWake` in `Events.swift` calls `reloadWebsite()` unconditionally, and there is no `NWPathMonitor` anywhere in the repository, so #41 is live on our baseline.

Cost M (one new file owning the lifecycle of two web views, plus an `NWPathMonitor`). Return: five issues closed at once, two of which, #11 and #41, are genuine bugs. This is the best return in the table.

### F10 custom CSS injection that stays applied — #173

CSS the user wrote for zoom.earth and Google Calendar takes effect when pasted into DevTools, but not when put in the app's CSS box. Three different people describe the same thing across the four comments (2024-12, 2026-02, 2026-03).

The mechanism: `createCSSInjectScript` at `Utilities.swift:1626` attaches a `<style>` to `document.documentElement` at `.atDocumentStart`. An SPA rewrites the whole subtree of `documentElement` when it mounts, and the injected style node is cleared away with it — hence "pasting it by hand works, one page reload and it is gone". The smallest fix: inject again at documentEnd, or use a `MutationObserver` to re-attach the style when it falls out of the document.

Note that the `SyntaxError: Can't create duplicate variable: 'style'` jiexiangfan reports in #173 **does not apply to us** — that is a regression in upstream 2.17.0, and the injection script on our baseline is wrapped in an IIFE (`Utilities.swift:1631`). That part is already OBSOLETE for us; do not follow it.

Cost S–M. High return: custom CSS is a core way this app gets used, and section 4 of ROADMAP keeps both class names specifically for five years of community Plash CSS snippets. If injection itself is broken, that compatibility decision buys nothing.

### F11 user agent policy — #169

`Utilities.swift:1406` pins the UA to `Version/18.3 Safari/605.1.15`. Google Calendar decides whether a browser is current from the version number, so the wallpaper carries a permanent "This browser version is no longer supported" banner. The reporter filed it in 2024; three more people said "same here" in 2025-03, 2025-04 and 2025-10; the last comment explains how to hide that div with CSS (`.V8Lvo { display: none }`) — after five years, covering it up is all the community has.

The author's reply, that Plash uses the built-in Safari rather than Chrome, answers a different question: the problem is not that the engine is old, it is that we report a version number that expires.

The fix (cost S): stop hard-coding the version number. Either do not override `customUserAgent` at all (WKWebView's default UA carries no `Version/x` of its own; which sites object to that needs testing), or read the version from the system Safari at runtime and build the string. Note that the existing code already has an empty-UA branch for `*.google.com` (two places in `WebViewController.swift`), but it only blanks the UA when the web view is created and `website.url.hasDomain("google.com")`; `calendar.google.com` goes through the navigation-time branch instead — worth unifying while we are in there.

### F7 extended into keeping session state — #39 #154 #127

Three issues, three ways into the same thing:

- #39 keep scroll position and zoom across a reload (the author did zoom back in 2020 — that is `zoomLevelWrapper` in our code; scroll was never done)
- #154 disabling and re-enabling from the shortcut loses the playlist position (the author replied that it should work that way)
- #127 waking from a closed lid forces a reload and the page state is gone

The author left the answer in #39 himself: `WKWebView.interactionState`. That property covers URL, history and scroll position in one go, and can be serialised to disk. No need for the 2020 approach of a JS scroll listener plus a Swift bridge.

Two more things change with it: the else branch of `AppState.isEnabled` (today `loadURL("about:blank")` plus `orderOut`) and the unconditional reload on wake in `Events.swift` — the latter should become a "reload on wake" setting, which can default to today's behaviour.

Cost S–M. Return: three issues, and the complaint in #127 is fatal for anyone using Nifro to show a page that holds state.

### F1 / F2 cropping — #162 #93

Both issues are direct evidence for the claim in section 6 of ROADMAP. Nothing left to argue, only to record:

- #162: the user shrank Google Calendar with the CSS the author gave in discussion #139, and "the blank space on the right still covers the desktop" — doing the page side without the window side is the same as not doing it.
- #93: the user wants the page as a sidebar, and points out that changing `:root { width }` in CSS changes the container and not the window, so `@media` queries do not move and what he gets is still the desktop layout. **This is the part the CSS side can never solve**; only actually shrinking the window with `window.setFrame` does it. Two comments backing it.

#93 adds a hard requirement to F1 that the CSS approach cannot meet, worth writing into F1's description in ROADMAP.

### P5 / F4 static mode — #15

The author opened this one himself in 2020, and the plan matches Backend A in ROADMAP word for word: load → screenshot → show the screenshot as the desktop → update on the reload interval. In the comments firrae asks whether taking screenshots costs more CPU, and the author answers that a shot is only taken on an interval tick, at most once a second and usually once a minute, so it costs less. Someone in the naming discussion proposed **Snapshot**.

For us: this maps straight onto P5 / F4. The direction needs no further discussion, and the implementation path is in section 2 of ROADMAP. Cost L.

### F8 display selection in the main menu — #195

The user moves between home and the office and changes "Show on" every day, but has to go into the General page of settings to do it. He almost never changes the website, only the screen.

Cost S: add a Display submenu in `Menus.swift`, still reading and writing `Defaults[.display]`.
Order matters: if F3 (multi-display) lands first, the shape of this menu changes with it, from "pick a screen" to "what goes on each screen", so either write the dozen-odd lines now and redo them at F3, or wait and do it together with F3. Either is fine; doing half is not.

### F14 actually taking focus when entering browsing mode — #114

The user writes in Nifro, and after the shortcut switches to browsing mode he still has to click the window by hand before he can type, because JS `onfocus`/`onblur` do not fire either. His workaround is to synthesise a mouse click with Alfred and AppleScript.

The code already calls `makeKeyAndOrderFront(self)` when `DesktopWindow.isInteractive = true`, but the app is an accessory app, and without `SSApp.forceActivate()` it never gets real keyboard focus. Cost S.

### F13 modifier-click opens a link in the default browser — #140

The user shows a monitoring dashboard in Nifro; links within the site always open inside Nifro, and he wants to hold shift+cmd, click, and hand one to a real browser to look into it.

The check already in `WebViewController.decidePolicyFor` is `Defaults[.openExternalLinksInBrowser] && a different host`; add "or a modifier key is currently held". Reading modifiers already has a precedent in the code (`NSEvent.modifiers != .option`). Cost S, about ten lines. It only means anything in browsing mode.

### E15 first-run welcome — #7

Upstream this one is "replace the stopgap NSAlert with a proper SwiftUI welcome window". For us it is first of all a **factual error**: the copy in `WelcomeScreen.swift` still says "droplet icon" (E13 already replaced it with the curtain-outline icon), and still explains upstream's limited multi-display support. That paragraph is now wrong and has to change.

Cost S (a copy change). Switching it to SwiftUI at the same time is optional; do not hold up the copy fix for it.

### A one-line safeguard related to #196 (categorised OBSOLETE, recorded here)

The reporter of #196 came back two days later to say that once he had played it by hand, autoplay worked from then on — that is WebKit's per-site autoplay quota, and the author could not reproduce it. The issue itself is void. But if P2 (`setAllMediaPlaybackSuspended` while occluded) is built later, confirm that video carries on playing by itself once the wallpaper is visible again, so this issue does not turn into a bug of ours.

---

## 3. LATER (13)

| # | Why not now |
|---|---|
| **#2 multi-display** | The most-requested item in the table: 47 👍, 36 comments, six years of people bumping it (the latest 2026-08-13). For five years the answer was a way around it — run several copies of Plash with different bundle ids — and the community ended up writing a `plash-cloner` script to clone the app. **But it depends on R1, the move to scenes**, and cannot be done while `AppState` is still a singleton with one window and one web view. In the order set out in section 11 of ROADMAP it is the first thing after R1, and it is our largest difference from upstream. Extra information in the comments: most people want **a different URL per screen** (ianiv's comment, +25), not the same page spread across all of them. |
| **#4 playlist** | Needs R1 as well. The comments add a request the issue body does not state: scheduling by time of day (GitHub activity in the morning, something else at night). The author's 2021 answer was that Plash is scriptable and you can rotate it from bash yourself — we have App Intents, so the same answer works for us in the short term. |
| **#182 the Mission Control gesture gives it away** | Section 2 of ROADMAP already names it. It follows directly from "it is not a real wallpaper", only P6/A2 solves it properly, and P6 is blocked on S1. Before A2, any `collectionBehavior` patch is guesswork. |
| **#177 dim / desaturate when unfocused** | The idea is right, and macOS does the same thing to its own desktop widgets. The implementation is a twenty-line rider on P1: `OcclusionMonitor` already listens for app-activation and space-switch notifications, so once "the desktop is not the active focus" is known, set `alphaValue` and inject a `filter: grayscale(1)` rule. **Do P1 first; do not build a second detection path just for this.** |
| **#193 backdrop-filter freezes** | See section 5. It is WebKit's own render throttling, not our code. It needs reproducing on our baseline first (the reporter gave a complete about:blank repro script), to confirm whether it is the other side of P4's snapshot-layer swap. No cost estimate before that. |
| **#183 URL scheme opens an app** | The closest thing in the table to a request we will not take, without crossing the line. A wallpaper page that can launch local apps is a clear attack surface, but the reporter proposed the right design himself: off by default, an allowlist, and a confirmation the first time; he also changed one line locally to check that it does not break the sandbox. It only affects people who turn the switch on. The return is small (1 👍), so it sits behind every S item. **If it is built, off by default is a hard requirement.** |
| **#158 geolocation** | The author opened this one himself, and judged it himself: it would have to be implemented by hand, he does not plan to, and he hopes Apple supports it natively (it did not after WWDC24). The workable path is injecting a `navigator.geolocation` shim into the `.page` world, backed by CoreLocation. **But that means giving location permission to a process that renders arbitrary user URLs around the clock**, which is the same argument as #125, differing only in a one-off coarse location versus a live video stream. If it is built it has to be off by default with per-site permission. One person backing it. |
| **#164 links navigating in place** | Needs more information. The request was written in 2024 (2.x), and in the current code `target=_blank` only opens a new window in browsing mode (`createWebViewWith` loads in place when `targetFrame == nil`), and back and forward gestures are already on (`allowsBackForwardNavigationGestures = true`). **The missing information**: whether what he hit was a window opening or something else. Either wait for a repro, or build it as a setting for "always navigate within the same view" (S). |
| **#132 sound in the page does not play** | Needs more information. The title says "Force mute", but the body asks for the opposite: he turned Mute audio off and the page's Web Audio (`AudioContext` plus `Audio().play()`) still makes no sound. Our `muteAudio()` only handles `<audio>`/`<video>` elements and does not reach AudioContext, so the mute setting is not the cause; more likely WebKit's autoplay policy wants a user gesture, and the desktop layer has no gesture at all. **The missing information**: whether setting `mediaTypesRequiringUserActionForPlayback = []` on our baseline unblocks AudioContext. If the only route is the private `_WKWebsiteAutoplayPolicy`, this goes straight to the X series. |
| **#79 301 redirects to external links** | A genuine bug. The `openExternalLinksInBrowser` check compares hosts only at the moment `navigationType == .linkActivated`; when the server 301s off-site the navigation type is already `.other`, so the result of the redirect stays inside Nifro. The fix is to remember that this navigation came from a user click, and compare hosts again at `didReceiveServerRedirect` or at the response stage. Cost M (state has to be carried through the navigation lifecycle), return moderate to small, so it sits behind F12 — both touch the navigation path, and changing them together costs less. |
| **#50 + #16 limited interaction on the desktop layer** | Merged into one item (F15). #50 has ten comments from users who want interactive widgets on the desktop (a calculator, buttons, a timer); #16 wants a particle or fluid background that follows the mouse (+1 ×2, hooray ×3).<br>**Upstream has already solved half of it**: the 2020 commit that stopped browsing mode covering every window, which on our baseline is `bringBrowsingModeToFront`, off by default; and `isBrowsingMode` is itself a persisted Default, so "start up in browsing mode" (imaverage's comment) already works today. What is genuinely unsolved is taking clicks without also taking selection and scrolling.<br>#16 is cheaper to implement than it looks: `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` needs no accessibility permission, and the coordinates can be turned into synthesised JS events. **But it conflicts with the position of the whole P series** — a 60 Hz global monitor plus an `evaluateJavaScript` every time. If it is built it has to be per-site, throttled, and its power cost written down in the documentation. |
| **#37 cookie banner / ad blocking** | The author opened it himself and marked it himself as a large amount of work that would not happen soon. Maintaining a full filter list ourselves is indeed not something to take on. But the middle route is cheap: `WKContentRuleListStore.compileContentRuleList` is an existing API, and we would provide only **a way to load rules** (a small built-in cookie-banner list, plus letting users point at their own rules JSON), with no promise to track any upstream rule source. Cost M. The return is real: a cookie banner does ruin a whole wallpaper. |

---

## 4. REJECT (1)

### #125 camera / capture-card input — grounds: outside what the app is for, a process-level permission surface, and better tools already exist

The request: use a camera or an HDMI capture card as the wallpaper; failing that, make pages that call `getUserMedia` work. 3 👍 and four comments, one of whom changed the Xcode project himself to confirm it works (adding `NSCameraUsageDescription`, the camera entitlement and a permission request), another running a Mac mini as a surveillance wall.

**It is technically possible** (`navigator.mediaDevices` is undefined precisely because the entitlement is missing), so the reason for declining is not difficulty:

1. **The entitlement is process-level, not per-site.** Once the camera permission is signed in, this process — which renders **whatever URL the user gives it**, around the clock — permanently has the ability to read the camera. The macOS permission prompt is only the second gate; the first gate, that the app should not have the ability at all, is one we would be giving up ourselves. The shorter a wallpaper app's entitlement list, the better: it is one of the few things a user can check.
2. **Outside what the app is for.** It is a wallpaper, not video capture software. A request the size of three people buys every user seeing Nifro ask for the camera in Privacy & Security.
3. **Better tools already exist.** Capture cards and multi-source video compositing go through OBS (virtual camera, or full-screen projection with the window kept at the back); a surveillance wall goes through a dedicated NVR client. These tools already do this, and do it better than we would.

**Suggested for the X series (X7)**, written down together with screen capture / `getDisplayMedia`, so it does not need discussing again later.

The same argument applies to #158 (location), but that one stays in LATER: a one-off coarse location and a live video stream are different sizes of risk, and weather pages are a mainstream use. Even then it would have to be off by default with per-site permission.

---

## 5. OBSOLETE (4)

| # | Why it is void |
|---|---|
| **#196 video autoplay** | The reporter's own conclusion two days later: play it once by hand and autoplay works from then on (WebKit's per-site autoplay quota), and the author could not reproduce it. The issue is a misunderstanding. The only thing to watch is that P2 does not turn it into a real bug; see the end of section 2. |
| **#88 Alfred listing the configured websites** | The author's 2021 plan was to wait for Shortcuts for Mac and return the website list through App Intents. **Our baseline already has it**: `WebsiteAppEntity` in `Intents.swift` comes with an `EnumerableEntityQuery`, paired with `SetCurrentWebsiteIntent`, so Alfred and Shortcuts can list them and switch today. No deeplink needs building. |
| **#76 more image wallpaper sources** | Upstream's approach was to invite people to each fork his `plash-bing-photo-of-the-day` repository. Our equivalent is the finished **C3 (the sites/ list, a schema and a way to submit)** and the pending **F6 (an in-app gallery)**, which is a better direction: one central list with one-click adding, rather than N scattered repositories. Void as an issue; as a request it has been absorbed into C3/F6. |
| **#5 App Store copy** | We are not going on the Mac App Store (section 1 of ROADMAP), and E12 already removed every store link and the rating prompt. |

---

## 6. Issues that are really performance issues

This section answers which issues talk about features on the surface while really talking about power and render scheduling.

```
What the user sees                What is really going on                      Our ID
──────────────────────────────────────────────────────────────────────────────────────────────
#193 backdrop-filter freezes    ← WebKit stops recomputing the backdrop        the other side of
                                  snapshot while the DOM does not update,      the P series
                                  and resumes as soon as the page moves        (see below)

#15  static sites are wasteful  ← the author's own power argument; the plan    P5 / F4
                                  is screenshots instead of live rendering

#154 wants pause, not disable   ← what he wants, suspend the renderer but      P2 / P3 / P4
                                  keep the state, is exactly what the          + F7
                                  occlusion path does

#127 do not reload on wake      ← a needless full-page rebuild (and we         P9 + F7
                                  hard-code reloadIgnoringLocalCacheData)

#21  show it once it has loaded ← the white screen and reflow during a         P9 + F12
                                  reload are the visible symptom of
                                  rebuilding the whole page every time

#196 video does not autoplay    ← the autoplay quota; also the recovery        an acceptance
                                  path to verify once P2 suspends media        check for P2

#182 gesture gives it away /    ← two downstream symptoms of the "it is        P6 / A2, F9
#177 wants dimming                not a real wallpaper" assumption

#16  mouse following            ← the cost is a 60 Hz global monitor plus      conflicts with
                                  an evaluateJavaScript every time             the P series
```

**#193 is worth a line of its own**: it is a reality check on the thinking behind our whole P series. WebKit already throttles by itself — while a page is not updating it will not even bother recomputing the backdrop. That says both that suspending inactive content is a direction the engine agrees with (support for P1–P4), and that **when P4 is built (pulling the webView out of the view tree and replacing it with a snapshot layer), pages that live on CSS animation and filters will visibly degrade**, so the snapshot layer has to be switchable off per site. The repro script is in the issue body, and it is a ready-made regression case for P4.

---

## 7. New entries suggested for ROADMAP (ready to paste)

### To add to the table in section 6, "Features (F series)"

| | Feature | Upstream issue | Status |
|---|---|---|---|
| **F8** | Display selection in the main menu | [#195](https://github.com/sindresorhus/Plash/issues/195) | To do, S. The menu changes shape once F3 lands; pick one of the two, do not do half |
| **F9** | Dim / desaturate when the desktop is not focused | [#177](https://github.com/sindresorhus/Plash/issues/177) | To do, S. Rides on P1's detection, do not build another one |
| **F10** | Custom CSS injection that stays applied: re-inject after an SPA rewrites documentElement | [#173](https://github.com/sindresorhus/Plash/issues/173) | To do, S–M. A genuine bug; hits Google Calendar and zoom.earth |
| **F11** | User agent policy: stop pinning `Version/18.3` | [#169](https://github.com/sindresorhus/Plash/issues/169) | To do, S. The hard-coded version number keeps Google Calendar warning |
| **F12** | Two web views, swapped on load: fade in only on success, keep the old content on failure | [#9](https://github.com/sindresorhus/Plash/issues/9) [#11](https://github.com/sindresorhus/Plash/issues/11) [#21](https://github.com/sindresorhus/Plash/issues/21) [#41](https://github.com/sindresorhus/Plash/issues/41) [#47](https://github.com/sindresorhus/Plash/issues/47) | To do, M. One mechanism closes 5 issues; the author wrote the plan five years ago |
| **F13** | Modifier-click opens a link in the default browser | [#140](https://github.com/sindresorhus/Plash/issues/140) | To do, S. About ten lines |
| **F14** | Actually take keyboard focus when entering browsing mode | [#114](https://github.com/sindresorhus/Plash/issues/114) | To do, S. What is missing is `SSApp.forceActivate()` |
| **F15** | Limited interaction on the desktop layer (clicks / mouse movement), per site | [#50](https://github.com/sindresorhus/Plash/issues/50) [#16](https://github.com/sindresorhus/Plash/issues/16) | To do, L. The power cost must go in the documentation |
| **F16** | A way to load content rules (cookie banners / ads), without maintaining a rule source | [#37](https://github.com/sindresorhus/Plash/issues/37) | To do, M |

### Changes to existing entries

| | Change to | Basis |
|---|---|---|
| **F7** | Keep **session state**: URL + scroll position + zoom, taken in one go with `WKWebView.interactionState`; plus a "reload on wake" setting | [#39](https://github.com/sindresorhus/Plash/issues/39) [#127](https://github.com/sindresorhus/Plash/issues/127) [#154](https://github.com/sindresorhus/Plash/issues/154). The author pointed at `interactionState` himself in a #39 comment |
| **F1** | Add a line to the passage on both sides having to change together: **the CSS side can never change `@media` queries**, only shrinking the window with `setFrame` triggers the mobile layout | [#93](https://github.com/sindresorhus/Plash/issues/93), two comments backing it |
| **F3** | Add a line: the mainstream request in the comments is **a different URL per screen**, not the same page across all of them; the community already built `plash-cloner` to clone the app as a way around it | [#2](https://github.com/sindresorhus/Plash/issues/2), 47 👍 / 36 comments / still being bumped in 2026-08 |
| **F5** | Add a line: the comments also ask for **scheduling by time of day** (different pages morning and evening) | [#4](https://github.com/sindresorhus/Plash/issues/4) |
| **P4** | Add a line: the snapshot-layer swap degrades pages that live on CSS animation and filters, so it has to be switchable off per site; the body of [#193](https://github.com/sindresorhus/Plash/issues/193) is a ready-made regression case | #193 |
| **P2** | Add an acceptance check: video has to carry on playing by itself once the wallpaper is visible again | [#196](https://github.com/sindresorhus/Plash/issues/196) |

### To add to section 7, "Engineering (E series)"

| | Item | Status |
|---|---|---|
| **E15** | First-run welcome: the current copy still says "droplet icon" and still explains upstream's multi-display limits; both are wrong | To do, S. [#7](https://github.com/sindresorhus/Plash/issues/7) |

### To add to section 10, "Explicitly not doing"

| | Proposal | Why it is declined |
|---|---|---|
| **X7** | Camera / screen capture input (`getUserMedia`, `getDisplayMedia`) | The entitlement is process-level, which permanently gives a process that renders arbitrary user URLs around the clock the ability to read the camera; the shorter a wallpaper app's permission list, the easier it is to check. Capture-card compositing goes through OBS, surveillance through an NVR client. Upstream [#125](https://github.com/sindresorhus/Plash/issues/125), 3 👍 |
