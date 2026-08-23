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
| **L0** | Choose a region by moving the wallpaper, not by drawing a box on it | **Done** | See below. K2 went with it: there is no rectangle left to convert |
| **L1** | A website has a place and a size on its display, not just a display | To do | Stored as fractions, like `Zoom` stores a centre and a magnification, so a block survives a change of display |
| **L2** | A four-way grid to snap to, and free placement for anything else | To do | The grid is the affordance, not the model. Free placement is the model |
| **L3** | Whether the grid uses the whole screen or keeps clear of the Dock | To do | A setting. `pageFrame` and `visibleFrame` are both already computed |
| **L4** | Which block takes a click | To do | Browsing Mode and hold-to-interact currently mean "the wallpaper". With blocks they have to mean one of them |

### L0, in full

A region is stored as a centre and a magnification. It is *chosen* by dragging an aspect-locked
rectangle over the wallpaper — a different shape of thing, converted into the stored one at the end.
Three problems come from that gap:

- **You are drawing on the thing you are framing.** The rectangle is not the result; you look at an
  outline and imagine what it will become.
- **It is one shot.** Drawn slightly wrong means starting over. There is no way to adjust a region
  that already exists — `beginCropSelection` clears it first, on purpose, because otherwise you would
  be framing a region of a region.
- **The conversion is where K2 lives.** A rectangle measured against the window becomes a fraction
  measured against the page, and the two do not agree to the pixel.

Direct manipulation removes all three, because it *is* the stored model: drag moves the centre, scroll
or pinch changes the magnification around the pointer, and the wallpaper shows the result at every
moment because the wallpaper is the result. Return keeps it, Escape puts back what was there before.
Nothing is converted, so K2 has nowhere left to happen, and adjusting an existing region becomes the
same gesture as making one — you start from where it is instead of from nothing.

The overlay stays. Its job changes from drawing a rectangle to swallowing scroll and drag so they
reach the region instead of the page: on a page that pans itself, floor796 or a map, the gesture has
to move the frame rather than the content inside it.

This is also the interaction blocks want (L1–L3): placing and sizing a block on the desktop is the
same two gestures against a different rectangle. Building it once for regions is the reason to do it
first.

**Which gestures, and why there is no conflict.** The worry is real for a trackpad — how do you pan
and zoom with the same two fingers — but the answer is that macOS already separates them into two
different gestures, and Apple already shipped this exact interaction. An aspect-locked crop where the
frame cannot move is Photos' crop, the iOS photo crop, and every avatar picker: **the frame stays
still and the content moves underneath it**. Our frame is the screen, so it could not move even if we
wanted it to. The box we currently drag is the odd one out, not the pan-and-zoom.

| | Pan | Zoom |
|---|---|---|
| Trackpad | Two-finger scroll → `scrollWheel(with:)`, `hasPreciseScrollingDeltas == true` | Pinch → `magnify(with:)`. A different gesture, so both can even happen at once |
| Mouse | Drag, or scroll | Wheel. There is no pinch on a wheel mouse, and zoom is the thing a wheel cannot otherwise reach — the same call Apple Maps and Google Maps make |
| Keyboard | Arrow keys | `+` / `-` |

`hasPreciseScrollingDeltas` is what tells the two devices apart, so scroll can mean pan on a trackpad
and zoom on a wheel without asking the user which they have. **Drag always pans, on every device**,
so somebody who never discovers a gesture can still work the thing.

Two details the overlay has to get right. `webView.allowsMagnification` is on, so a pinch that reaches
the page zooms the page — the overlay has to swallow `magnify(with:)`, not just `scrollWheel(with:)`.
And the mode needs to say what it is: a small panel with the current magnification, Return to keep,
Escape to put back. Zoom should track the pointer rather than the centre of the screen, which is what
makes it feel like moving a page rather than operating a control.

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

## 5.5 What a page remembers, and who remembers it (the M series)

Sound and the framed region belong to the website and are stored with it. Where the *page* was —
floor796's camera, a map's viewport, how far down a dashboard is scrolled — belongs to the page, and
there are four ways a page can hold it. Three of them already survive; knowing which is which is most
of the answer.

| | Where the page keeps its position | Survives a relaunch |
|---|---|---|
| **M1** | `localStorage` / IndexedDB | **Yes, already.** `WKWebViewConfiguration()` defaults to the persistent data store, so this is kept in the app's container and comes back on its own. floor796 is this case: it writes `last-pos` on every move. Settings → "Clear website data" is the one thing that throws it away |
| **M2** | The URL fragment | **Yes, now.** The address the page moved itself to is remembered beside the website's own, never over it, and used only when the two differ in nothing but the fragment. A fragment cannot 404, which is why the check stops there rather than allowing the query as well. Shares the "Put the page back where it was" switch with M3 |
| **M3** | Document scroll | **On a reload, yes** — `ScrollRestoration` captures it just before reloading and puts it back after. A hard quit loses at most the last scroll, because nothing polls in the background to support it |
| **M4** | Only in memory | **No, and there is nothing to be done.** A canvas that keeps its camera in a variable and writes it nowhere cannot be asked where it was |
| **M5** | Half in the address, half in memory | **Half.** floor796 is this, and it is worth reading its own numbers for: `restorePositionFromUrl: true`, `restorePositionFromLS: false`, and a `_matrixPosition._zoomFactor` that appears in neither. So *where* comes back — the fragment is the only route the site supports, which is exactly what M2 restores — and *how close* does not. The two together are what somebody sees, so getting one back still looks wrong |

| **M6** | Keep the page instead of remembering it | **Complete within one run of the app, and nothing beyond it.** A page that is never torn down loses nothing — position, magnification, scroll, login, animation state, whatever the site keeps and wherever it keeps it. But it is memory, so quitting, a restart, or disabling ends it as surely as a reload does. It answers "switch away and come back", which is the case people hit hourly, and it answers K3 with it, since switching back is not a page load. It does not answer "open the Mac tomorrow". One more WebContent process for as long as a page is kept, which is why it should be a per-website switch rather than a policy |

**Where this stands: nothing more for now.** M2 shipped, so position comes back and floor796's own
magnification does not. The two ways past that are both real and neither is urgent, so they are
written down rather than started:

| | | Buys | Costs |
|---|---|---|---|
| **A** | Leave it | — | Position comes back, magnification never does |
| **B** | M6, as a per-website switch | Everything survives a switch, and switching back becomes instant (K3) | One WebContent process while a page is kept; gone at quit |
| **C** | `pageWorld: true` on a site entry | The site's own magnification survives a restart | That entry loses its isolation, and it depends on floor796's private fields, so a redesign there breaks it |

B and C do not conflict. B is the better first move if either is taken: it depends on no website's
internals, it helps every site rather than one, and it closes K3 on the way. C buys a narrower thing
with a more fragile hook.

**The one route that survives a restart, and what it costs.** Custom per-site JavaScript is injected
into `.world(name: UUID())`, an isolated world, so it cannot see `window.floor796` or any other page
global — which is why a site entry cannot read the zoom, let alone put it back. Injecting into the
page's world instead would let an entry save the zoom to `localStorage` and restore it on load, and
`localStorage` is on disk, so that is the only answer here that outlives the app. M6 does not: it is
memory, and memory ends when the app does.

The cost was overstated when this was first written. The app's own scripts — the audio control —
live in `.defaultClient` and would stay isolated either way, so what changes is only whether a
website's own entry can touch that website's globals. The entry is already wrapped in an IIFE, so it
leaks nothing into the page by accident, and it runs on the page it was written for and nowhere else.
The honest risk is the reverse direction: a page could redefine what an entry reaches for. For a
wallpaper that buys an attacker nothing an ordinary page cannot already do to itself.

So the shape to build, if this is wanted, is a per-entry opt-in — `pageWorld: true` in the site
schema, isolated by default — rather than changing the world for everything. Whoever reviews an entry
then sees which ones asked for it, and the rest keep the boundary they have.

**M2 is built.** The manual version already existed — "Update Website to Current" in
the menu points the stored website at the address currently loaded — which is proof both that people
want it and that the mechanism works. The automatic version has to avoid the bug that item caused
once: it fired on every website with a host page and turned one of them into a GitHub 404. So the
last-loaded address is remembered *beside* the stored one rather than overwriting it, and is only
used when it differs from the stored address in nothing but the fragment or the query. Anything more
than that is a different page, and loading a different page than the one somebody typed is how the
404 happened.

Worth saying out loud in the app somewhere, too: **a website's own settings are remembered per
website; where the page is inside itself is up to the page.** That is why two sites that look alike
behave differently, and nothing currently explains it.

---

## 5.6 Multiple displays: built, never tested (the D series)

**Every part of this was written on a one-display machine and has never been run on two.** It is not
a known bug list; it is a list of claims nobody has checked. Two of them have since been checked by
reading and turned out to be false — see D9 and D10, both now fixed — which is worth knowing before
trusting the rest of the column. The centre-and-magnification design
exists *because* of the second display — a rectangle framed on one screen cannot come out right on
another shape — so the one feature most argued for is the one with the least evidence behind it.

| | The claim | What would show it is wrong |
|---|---|---|
| **D1** | A different website on each display | Two websites with different `display` values give two scenes. A website whose display is `nil` follows Settings, so two of those land on one screen and one of them is not shown. **Partly answered by D9/D10:** which website each display picks is now per display and tested; whether each display then *renders* the right one is still unseen |
| **D2** | A region framed on one display comes out right on the other | The point of `Zoom`. On a second display of a different aspect the region should be the shape of *that* display, around the same part of the page. Framed on 16:10, shown on 16:9, and nobody has looked |
| **D3** | Framing happens on the display the website is on | `beginCropSelection` picks the scene by website and puts the overlay on that window. On the wrong screen, the frame would be moved against a page the user cannot see |
| **D4** | The menu bar band, on a display with no menu bar | `installMenuBarBandIfNeeded` refuses when `menuBarHeight` is 0, which is a second display unless "Displays have separate Spaces" is on. That switch changes the answer, and both states need looking at |
| **D5** | Plugging and unplugging while it runs | `rebuildScenes` runs on a display change: scenes for displays that went away are torn down, new ones built. A laptop that docks and undocks does this several times a day |
| **D6** | Different scale factors and different sizes side by side | The page lays out at each screen's `pageFrame`, so a Retina and a non-Retina display should each get their own. Never seen |
| **D7** | Where the page was, with the same website on two displays | Both the scroll position and the remembered address are keyed by URL, not by display, so two scenes showing one website would write over each other. `displaysInUse` suggests one website reaches one display, which would make this impossible — but "suggests" is the whole problem with this section |
| ~~D8~~ | ~~"Show on every Space" and the playlist, per display~~ | **Answered by D9, and it did not work.** Two scenes rotating on their own timers could not have worked on any machine: the mark they rotate is one flag cleared list-wide. Fixed and covered by `CurrentWebsiteTests`. "Show on every Space" per display is still unwatched |
| **D9** | ~~One `isCurrent` flag, cleared list-wide, behind a per-display rotation~~ | **Fixed.** `advance(on:)` and `scheduled(for:)` group by display, but `makeCurrent` cleared the flag on every website. Each display's playlist tick therefore wiped the other display's mark; that display read "nothing is current", started counting from index 0, and never moved past the first website in its list. The same flag was what Next, Previous, Random, Sound, Choose Region and Show on all acted through, so every one of them silently acted on whichever screen last held it. Now per display, with the rule as plain functions in `Support/Rotation.swift` so the two-display case is checked by `swift test` rather than by owning two displays |
| **D10** | ~~Each scene's web view configured from the list-wide current website~~ | **Fixed.** `createWebView` read `WebsitesController.shared.current` for the custom CSS, the custom JavaScript, inverted colours, print styles and the Google user-agent special case, and all of it is baked in at creation and never revisited. On one display the list-wide current is the scene's own, which is why it never showed. On two, the second display's page ran the first display's code. Same for the audio setting, the self-signed-certificate answer, and "Update Website to Current" in the page's own context menu. Scenes are now handed their website in `init`, before the web view exists |
| ~~D11~~ | ~~A page laid out for the display it started on, after it moves~~ | **Checked, and it was not happening.** `PageView` did cache `pageSize`, the region and the magnification from `init`, but a display change runs `NSScreen.publisher` → `rebuildScenes` → `installContentView`, and assigning `content` rebuilds the view before `layout()` can run on the stale numbers. So the cache was never read after it went stale. Removed anyway: `layOutContent` now derives from `bounds`, because a cached copy of a value the view is handed live is a trap for whoever adds the next reason to resize a wallpaper window. Worth recording that the original claim was reasoned from one file and did not survive reading the callers |

Ordinary use finds these faster than reasoning does, so this is a list to walk once with a second
display attached rather than work to schedule.

---

## 5.7 The site catalogue: nobody has reviewed it (the S series)

Three lists, one pipeline, and a maintainer who has not looked at any of it. What is actually there
today:

```
sites/CANDIDATES.md      119 links, of which 111 have never been made to work
      ↓  somebody works out the settings and checks they hold
sites/*.yml               38 entries, schema-checked, offered in the app's Site Gallery
      ↓  picked as one of the few worth shipping
featured: true             8 entries, installed on first launch
```

The pipeline is right and the numbers are the problem. Every one of the 38 was written by an agent
from a link and a guess, and the 8 that install themselves on a stranger's first launch are the first
impression of the whole app.

| | Item | Status | Notes |
|---|---|---|---|
| **S1** | The maintainer reviews the 8 featured | To do. **This one first** | They are what a new user sees before deciding whether the app is any good. Eight pages is an evening, and it is the highest-value hour in this section |
| **S2** | The maintainer reviews the other 30 | To do | Lower stakes — somebody has to go looking for these — but they carry the same claim, that the settings on them are right |
| **S3** | 111 candidates have never been graduated | To do, forever | Not a backlog to burn down. A link is cheap and an entry is work, so the pool being larger than the catalogue is the normal state, not a debt |
| **S4** | Which of the three lists is the source of truth for a reader | Unclear, and that is the "complicated" part | `CANDIDATES.md` is a pool, `sites/*.yml` is the catalogue, `NOT-INCLUDED.md` is the refusals, and the README's nav points at the directory rather than at any of them. A reader landing on `sites/` sees the contributor guide first and has to work out which of its neighbours is the list of what the app actually offers |

**What would simplify S4 without another file.** The Site Gallery in the app already shows exactly the
38, with their settings, filterable by tag — it is the readable list, and it is in the one place where
picking something has an effect. So the repository does not need a fourth rendering of the same data;
it needs the two markdown files to say plainly what they are for and to stop reading like alternatives
to the app.

---

## 6. Known and not yet fixed (the K series)

Reported while using the app, reproduced, and left alone for now. Each is written down rather than
fixed so that the first release is a thing that exists.

| | What happens | What is known about it |
|---|---|---|
| **K1** | A YouTube video cannot be shrunk back into the YouTube page, so there is no way to sign in | The address is rewritten to the player-only page and framed by a host page, because YouTube's player answers "error 153" when it is the document rather than a frame in one. That gets the video on the wallpaper and takes the site with it: there is no page around the player to navigate, and Browsing Mode has nothing to click into. Bilibili's player is a normal page and does not have this problem, which is why the two behave differently. Whatever the fix is, it has to keep 153 away |
| ~~K2~~ | ~~A framed region does not land exactly where it was framed~~ | **Fixed by L0.** The gap was the conversion: a rectangle measured against the window became a fraction measured against the page, and the two did not agree to the pixel. Moving the page changes the stored value directly, so there is no conversion and nothing to be a point out. The region also survives however the mode is left now, and no longer reloads the page it is framing |
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
| ~~E17~~ | ~~Three families of per-page `UserDefaults` keys grow without bound~~ | **Measured, and they do not.** On a real install after real use: `com.pathgao.nifro.plist` is 4378 bytes, 21 keys, and **zero** of all three families. The reasoning that said "one key per page ever visited" was wrong about every one of them — `scrollPosition_` is only written from `reload()` and only when the position is not `[0, 0]`, `lastAddress_` needs the page to carry a fragment, and `zoomLevel_` needs somebody to pick Zoom In from the context menu. Growth follows what the user does to a page, and a wallpaper is a thing nobody touches. No pruning, and the reason is now a number instead of a guess |
| ~~E18~~ | ~~`forgetWherePagesWere` cannot be tested~~ | **Replaced with something that cannot be forgotten instead.** A test was the wrong tool: the failure to guard against is "a fourth kind of per-page record is added and the sweep is not told", and a test of the sweep's filter cannot see a prefix that was never handed to it. The three prefixes are now cases of `PerPageDefaults`, which also builds the keys, so a fourth kind has to be a case to get a key at all — and the sweep is `allCases`. `UserDefaults.standard` is still named directly and the sweep still has no test; it no longer needs one |
| ~~E20~~ | ~~`nifro://reload` did nothing but put up an alert~~ | **Fixed.** `URLCommands` read `urlComponents.path`, and only `nifro:reload` puts the word there — `nifro://reload` puts it in the *host* with an empty path, so the command fell through to "The command “” is not supported". That message names nothing and is the same one a real typo gets, so there was no way to tell "wrong number of slashes" from "no such command". Both spellings are accepted now, plus `nifro:///reload`, and the extraction is a pure function in `Support/URLCommand.swift` with the three spellings pinned. Found by using it: the alert in the screenshot was four of these stacked up |
| **E21** | `nifro://` is registered to stale copies of the app | LaunchServices has this scheme against at least five builds on this machine, including one in `~/.Trash` and several in derived-data directories. `open "nifro:reload"` picks one of them, not necessarily the installed app. Nothing in the repo causes it — it is what building a signed app repeatedly does — but anyone testing URL commands has to use `open -a <path>` or they will be driving a build from three weeks ago. Worth a line in whatever document tells someone how to test this |
| **E19** | The first page of the session is loaded by the content-rules subscription | Nothing in `didLaunch` loads anything. `Defaults.publisher(.contentRulesURL)` sends its current value on subscribe, and the handler is what puts the first wallpaper up. It happens to be the right order — pages come up with the blocklist already compiled — but nothing says so, and anyone changing that subscription takes the wallpaper away at launch with no clue pointing back here. Left alone rather than restructured because the ordering is load-bearing and cannot be checked without running the app; there is now a comment on the subscription saying it |

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

**Release immutability is off, on purpose for now.** The switch is in Settings → General, under a
Releases heading that is not in the sidebar, and it forbids changing a published release's assets and
tags. It is the right end state and the wrong one today: the two download links in the README only
work because the v0.1.0 assets were *renamed* after publishing, to drop the version from the file
name. Turn it on once a few releases have gone out without needing to be touched afterwards.

### Knowing there is a new version (the U series)

Nothing in the app knows a release exists. There is no Sparkle, no check, no menu item — the only
upgrade path is `brew upgrade`, and only for people who installed that way. Somebody who took a disk
image from the README stays on the version they took until they happen to visit the repository
again. For a menu bar app that runs from login and is rarely opened on purpose, "they happen to
visit" is close to never.

| | Item | Status | Notes |
|---|---|---|---|
| **U1** | Check for a new version and say so | To do. **Do this one first** | One request to `/repos/PathGao/Nifro/releases/latest`, compare `tag_name` against `SSApp.version`, and put "Version 0.2.0 is available" in the menu, linking to the release. No dependency, no entitlement, no keys, no infrastructure — the release API is public and already there. It tells a brew user to run `brew upgrade` and a direct-download user that there is anything to download. Needs a cadence that is not a poll on every menu open, and a way to turn it off |
| **U2** | Download and install it too (Sparkle) | Not now | Much more than U1 looks. Sparkle needs an appcast feed to publish and an EdDSA key pair to sign updates with — a second signing identity to keep for the life of the app, on top of the certificate. A sandboxed app cannot replace itself either; that goes through Sparkle's installer XPC service, which is more entitlements on an app whose short entitlement list is a feature. **And the feed URL is permanent from the first version that ships with it**: Markpad is on its second repository owner and its release workflow still asserts that the *old* URL serves this project's feed, because every install up to v2.7.0 asks that address and nothing else. Renaming this repository once was free; it stops being free the day an update feed points into it |
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
| R4 | `sites/index.json`, fetched from `main` when the gallery opens | 1 place | It is a code path into the user's web view that does not go through a release. An entry carries `css` and `javaScript`, and adding one is a merge on `main` rather than a build, a notarisation or a version bump — so a bad entry reaches every installed copy the next time somebody opens the gallery. CONTRIBUTING asks contributors not to submit JavaScript that sends anything anywhere, which is a policy and not a control. Kept because the alternative loses the thing it is for: entries contributed between releases showing up without an app update. Worth knowing that the site list is release-grade surface and reviewing it as such |
| ~~R5~~ | ~~`Nifro/Support/Extensions.swift`, 3600 lines, a third of the app~~ | — | **Split, after the argument for keeping it whole turned out to be invented.** The four things in it that are not extensions — `SimpleImageCache`, `WebsiteIconFetcher`, `SecurityScopedBookmarkManager`, `ScrollableTextView`, 776 lines — are now their own files, and the rest is 2810 lines of actual extensions. The reason first given for not doing it was that the file is cheap to diff against upstream: **there is no upstream remote**, no commit has ever merged from Plash, and the file has been edited 17 times here. Registering a file in `project.pbxproj` by hand is four lines, which had just been done for `Rotation.swift`. What is still true: **nothing in the file is dead.** A reading-based claim that 200 lines were unreachable was checked with `periphery` and was wrong — each of those types is reached from a live extension a few hundred lines away, which is itself an argument for the file being too big to reason about by eye |
| R6 | `DesktopWindow.reducedRegion` and `CGRect.screenFrame(inScreen:)` | 1 read, 0 writes | Nothing assigns `reducedRegion`; the visibility policy that used to came out with the power machinery. Kept because shrinking the window to part of the desktop is the L series and this is the shape it needs. `periphery` cannot see it, because the property is read. The doc comment now says it is never written, which matters to anything reasoning about where the wallpaper window is |
| N4 | Narrowing the visibility of `Website.InvertColors` | Tried twice, red twice | The conformance is declared at the top level rather than inside the type's scope, and the stored property that uses it is read from other files |
| ~~N5~~ | ~~Narrowing `WallpaperContent` / `RenderingMode`~~ | — | Still true of `WallpaperContent`. `RenderingMode` is **gone**: narrowing it was the wrong question. It was two cases computed from `website?.allowsInteraction` and read at exactly one comparison, so it was a `Bool` with an enum around it, and the compiler is the check that the collapse is faithful |
| N6 | A cross-fade when switching website, instead of the straight swap | 1 place | Both pages would have to be in the window at once, which means a container view and a second answer to what `window.contentView` holds — the exact ambiguity that cost a blank wallpaper before. Two loaded pages can just change places. Revisit only if the straight swap reads as abrupt |
