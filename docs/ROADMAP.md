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

**Two: it is not a real wallpaper.** A transparent borderless window on the `.desktop` layer.
Upstream's own FAQ admits the consequence: the menu bar cannot pick up its colour. Downstream of that,
the Mission Control gesture giving the game away (Plash#182), Stage Manager treating it as a window,
and the run of `collectionBehavior` patches in `DesktopWindow.swift`.

The answer was two backends: a `snapshot` one that renders a page offscreen, photographs it and lets
the web process go — into the window's layer, or (**A2**) through `NSWorkspace.setDesktopImageURL`, a
genuine macOS wallpaper — and a `live` one, the resident web view we have now, for pages that really
do animate.

**None of it survived, and the reasons are worth keeping:**

| What was claimed | What was found |
|---|---|
| A snapshot renderer can photograph any page | It cannot photograph the interesting ones. A window that is not on screen makes WebKit report `visibilityState: hidden`, so `requestAnimationFrame` never runs and anything drawing to a canvas photographs blank. Measured on one page: offscreen, `canvas=none`, 4 tiles, 232KB; on screen, `canvas=2790×1538`, 44 tiles, 2452KB. Overriding `document.hidden` in JavaScript does not help — the decision is below it |
| Two backends can coexist | Each owned the answer to "what is being rendered right now", which is what Browsing Mode changes. Entering Browsing Mode reloaded, leaving reloaded again, both showed the desktop while they did, and a snapshot finishing could take the page out from under someone reading it. Every fix exposed the next |
| The menu bar problem needs a real wallpaper | It did not. The page is kept out of the menu bar strip and an opaque band takes the website's colour, which is the part anyone actually wanted |

So the machinery came out — around 2400 lines across two removals, of which §4's 811 is one — and the app went back to what
upstream does: one live page that stops only when disabled, when the screen is locked, or on battery.
**A2 is refused outright now; see X8.** Power comes back one piece at a time under the conditions in
section 4, around the live page rather than instead of it.

---

## 3. Status at a glance

```
Upstream issue triage   35 issues, compressing into 8 mechanisms
                        The counts live in UPSTREAM-ISSUES.md, not here, because two copies
                        of one number is how they came to disagree
Blocked                 nothing
Open bugs               K1, K3, K5-K14, K16-K19. K9-K14 were found by reading this document
                        against the code rather than by using the app; none had been noticed in
                        use. K16-K19 came the other way round — from the panel being used on two
                        displays for an afternoon
```

Every section here was checked against the code it describes. Seven claims turned out false and are
struck through in place rather than deleted: L0's Photos-crop premise and its pointer-anchored zoom,
D2's "nobody has looked", D5's "scenes for displays that went away are torn down", D7's guarantee,
D8's "still unwatched", and this section's own rule about counts in prose. One pattern in the misses:
**"nobody has looked" was repeatedly written where "nobody has read the callers" was the truth**, and
reading the callers cost less than the hardware it was waiting for.

---

## 4. Power (the P series)

> **All of this is currently out of the code.** Two rendering backends, occlusion measurement and
> automatic still detection were built, and each owned the answer to "what is being rendered right
> now" — the collision in section 2, plus one more: disabling left a colour band behind. Each was
> fixable and each fix exposed the next.
>
> So it came out — 811 lines. The interaction is what this app is; power is an optimisation of it, and
> one whose benefit was never measured cleanly. It goes back a piece at a time, each with a
> measurement first and a way to turn it off. What has to be true before any of it returns:
>
> 1. A measurement of the cost it claims to remove, taken while the machine is otherwise idle, on the
>    state it actually targets — a covered wallpaper, not a browsing session.
> 2. One owner for "what is being rendered". Browsing Mode changing it is the case that broke every
>    version of this.
> 3. A way for the user to turn it off that does not require understanding it.

Upstream stops for three reasons only: manually disabled, screen locked, on battery. **Nothing about occlusion at all**, which is the baseline any of this has to beat.

**Two of the ideas are refused rather than deferred**, and they are the two that never had an issue behind them. *Go opaque when the content fills the screen*: the saving cannot be measured, and it needs a user switch that turns the screen black on a page with a transparent background. Settings whose payoff is unclear do not get added. *A configurable reload strategy*: nobody ever asked for it, it was thought up here, and it is a setting in search of a complaint.

---

## 5. Blocks: a page as a piece of the desktop (the L series)

Zooming already answers *which part of a page*, and puts that part on the whole screen. The other half
is *where on the desktop it goes* — a zoomed-in fragment is usually not something you want at
full-screen size. It is something you want in a corner.

So: a website becomes a block. Its content is what zooming already produces; its place and size are
new, and free — with a four-way grid offered so that placing one is a choice between four obvious
answers rather than an exercise in dragging.

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

The grid's quadrants can come from the whole screen or from the area the Dock leaves — a setting,
because the answer depends on where somebody keeps their Dock and whether it hides itself. The
distinction already exists in the code (`screen.pageFrame` against `visibleFrame`); it has never been
offered to the user.

**Why this is worth doing.** A block plus a zoom turns a website into a desktop widget. The concrete
case is a number that only exists on a web page — how much of this month's Codex or Claude usage is
gone. Nobody will ship a widget for that. Zoom to the figure, put the block in a corner, and the rest
of the desktop is still the desktop. A class of thing: a build dashboard, a deploy status, a
countdown, one number from a page nobody will ever write an app for.

**Most of this already exists**, the main argument for doing it. A scene owns a window; `Zoom` picks
the part of the page; `DesktopWindow` sets an arbitrary frame; several scenes run at once. Until this
week a crop *did* shrink the window to itself; that was removed (see the first of the three problems
below). This brings the second job back with an owner.

| | Item | Status | Notes |
|---|---|---|---|
| **L0** | Choose a region by moving the wallpaper, not by drawing a box on it | **Done** | See below. K2 went with it: there is no rectangle left to convert |
| **L1** | A website has a place and a size on its display, not just a display | To do | Stored as fractions, like `Zoom` stores a centre and a magnification, so a block survives a change of display |
| **L2** | A four-way grid to snap to, and free placement for anything else | To do | The grid is the affordance, not the model. Free placement is the model |
| **L3** | Whether the grid uses the whole screen or keeps clear of the Dock | To do | A setting. `pageFrame` and `visibleFrame` are both already computed |
| **L4** | Which block takes a click | To do | Browsing Mode and hold-to-interact currently mean "the wallpaper". With blocks they have to mean one of them |

### L0, in full

A region is stored as a centre and a magnification. It used to be *chosen* by dragging an
aspect-locked rectangle over the wallpaper, converted into the stored shape at the end. Three problems
came from that gap:

- **You are drawing on the thing you are framing.** The rectangle is not the result; you look at an
  outline and imagine what it will become.
- **It is one shot.** Drawn slightly wrong means starting over, and an existing region cannot be
  adjusted — `beginCropSelection` clears it first, on purpose, because otherwise you would be framing
  a region of a region.
- **The conversion is where K2 lives.** A rectangle measured against the window becomes a fraction
  measured against the page, and the two do not agree to the pixel.

Direct manipulation removes all three because it *is* the stored model: drag moves the centre, scroll
or pinch changes the magnification, and the wallpaper shows the result at every moment. Return keeps
it, Escape puts back what was there. Nothing is converted, so K2 has nowhere to happen, and adjusting
a region is the same gesture as making one.

The overlay stays, its job changed from drawing a rectangle to swallowing scroll and drag so they
reach the region instead of the page: on a page that pans itself, floor796 or a map, the gesture has
to move the frame, not the content inside it.

Blocks want the same interaction (L1–L3): placing and sizing a block is these two gestures against a
different rectangle. Building it once for regions is the reason to do it first.

**Which gestures, and why there is no conflict.** The worry is real for a trackpad — how do you pan
and zoom with the same two fingers — but macOS already separates them into two gestures. ~~And Apple
already shipped this exact interaction: an aspect-locked crop where the frame cannot move is Photos'
crop, the iOS photo crop and every avatar picker, where the frame stays still and the content moves
underneath it.~~ **That was written before L0 shipped, and L0 shipped the other way round.** Moving
the content is wrong here for a reason that does not apply to a photograph: a web page can pan and
zoom itself, so on floor796 or a map a moving picture has two readings, and the page's own
magnification multiplies with the frame's. A still page and a moving frame has one reading. The
gesture-conflict argument survives and the table below is what shipped, but the premise is the
opposite of the code; `Zoom/CropSelectionView.swift` carries the reasoning that replaced it.
**Anything in the L series inheriting "the same two gestures against a different rectangle" has to
inherit the shipped model, not this paragraph.**

| | Pan | Zoom |
|---|---|---|
| Trackpad | Two-finger scroll → `scrollWheel(with:)`, `hasPreciseScrollingDeltas == true` | Pinch → `magnify(with:)`. A different gesture, so both can even happen at once |
| Mouse | Drag, or scroll | Wheel. There is no pinch on a wheel mouse, and zoom is what a wheel cannot otherwise reach — the call Apple Maps and Google Maps make |
| Keyboard | Arrow keys | `+` / `-` |

`hasPreciseScrollingDeltas` tells the two devices apart, so scroll means pan on a trackpad and zoom on
a wheel without asking the user which they have. **Drag always pans, on every device**, so somebody
who never discovers a gesture can still work the thing.

Two details the overlay has to get right. `webView.allowsMagnification` is on, so a pinch reaching the
page zooms the page — the overlay has to swallow `magnify(with:)`, not just `scrollWheel(with:)`. And
the mode needs to say what it is: a small panel with the current magnification, Return to keep, Escape
to put back. ~~Zoom should track the pointer rather than the centre of the screen~~ — **refuted by the
same reversal.** `Geometry.resizedFrame(byGrowing:)` grows around the frame's own middle on purpose:
the page does not move, only the frame does, and anchoring the size change to the pointer slides the
frame out from under it. Pointer-anchored zoom feels right when the picture is moving and wrong when
it is not.

**The three things that make this harder than it looks**, named now so they are not discovered later:

- **Two things sizing one window.** The visibility policy owns the window's frame today
  (`DesktopWindow.reducedRegion`). A block owns it too — the collision that made cropping and the
  visibility policy fight until cropping stopped moving the window at all. So a block has to be the
  window's *base* frame, with occlusion shrinking inside it, never the reverse.
- **One web process per block.** Three blocks is three `WKWebView`s and three web processes. The P
  series exists to avoid paying for rendering nobody looks at, and this multiplies the bill. It makes
  the snapshot backend more important rather than less: a block showing one number is the clearest
  case in the app for photographing a page instead of running it.
- **A block is not a window the user can grab.** No title bars down there, and adding them would make
  the wallpaper into an app. Placing one has to happen the way framing a region does — over the
  wallpaper, desktop still visible behind it — or from a menu of grid positions.

---

## 5.5 What a page remembers, and who remembers it (the M series)

Sound and the framed region belong to the website and are stored with it. Where the *page* was —
floor796's camera, a map's viewport, how far down a dashboard is scrolled — belongs to the page, and
there are four ways a page can hold it. Three already survive; knowing which is which is most of the
answer.

| | Where the page keeps its position | Survives a relaunch |
|---|---|---|
| **M1** | `localStorage` / IndexedDB | **Yes, but not for the reason this row used to give, and the guarantee is narrower now.** It said `WKWebViewConfiguration()` defaults to the persistent store. It no longer does: `createWebView` assigns `DiskBudget.store(for: website.id)`, so each website gets its own persistent store, and floor796 still gets its `last-pos` back. What changed is the scope — **`localStorage` is partitioned by website entry now, not by origin.** Two entries pointing at one site (one per display, say) no longer share a login or a saved position, and deleting an entry and adding the same URL back starts empty, because `removeOrphanedStores` collects the old store at the next launch. That is the price of making a website's disk cost die with the website. The upside on the same trade: "Clear website data" is no longer the *only* way to reclaim it — deleting the website does, without signing the user out of the ones they kept |
| **M2** | The URL fragment | **Yes, now.** The address the page moved itself to is remembered beside the website's own, never over it, and used only when the two differ in nothing but the fragment. A fragment cannot 404, which is why the check stops there rather than allowing the query as well. Shares the "Put the page back where it was" switch with M3 |
| **M3** | Document scroll | **On a reload, yes** — `ScrollRestoration` captures it just before reloading and puts it back after. A hard quit loses at most the last scroll, because nothing polls in the background to support it |
| **M4** | Only in memory | **No, and there is nothing to be done.** A canvas that keeps its camera in a variable and writes it nowhere cannot be asked where it was |
| **M5** | Half in the address, half in memory | **Half.** floor796 is this, and its own numbers are worth reading: `restorePositionFromUrl: true`, `restorePositionFromLS: false`, and a `_matrixPosition._zoomFactor` in neither. So *where* comes back — the fragment is the only route the site supports, which is what M2 restores — and *how close* does not. The two together are what somebody sees, so getting one back still looks wrong |
| **M6** | Keep the page instead of remembering it | **Complete within one run of the app, nothing beyond it.** A page never torn down loses nothing — position, magnification, scroll, login, animation state, whatever the site keeps and wherever it keeps it. But it is memory, so quitting, a restart or disabling ends it as surely as a reload does. It answers "switch away and come back", the case people hit hourly, and answers K3 with it, since switching back is not a page load. It does not answer "open the Mac tomorrow". One more WebContent process for as long as a page is kept, which is why it should be a per-website switch rather than a policy |

**Where this stands: nothing more for now.** M2 shipped, so position comes back and floor796's own
magnification does not. The two ways past that are both real and neither is urgent:

| | | Buys | Costs |
|---|---|---|---|
| **A** | Leave it | — | Position comes back, magnification never does |
| **B** | M6, as a per-website switch | Everything survives a switch, and switching back becomes instant (K3) | One WebContent process while a page is kept; gone at quit |
| **C** | `pageWorld: true` on a site entry | The site's own magnification survives a restart | That entry loses its isolation, and it depends on floor796's private fields, so a redesign there breaks it |

B and C do not conflict. B is the better first move if either is taken: it depends on no website's
internals, helps every site rather than one, and closes K3 on the way. C buys a narrower thing with a
more fragile hook.

**C is the only route that survives a restart.** Custom per-site JavaScript is injected into
`.world(name: UUID())`, an isolated world, so it cannot see `window.floor796` or any other page
global, which is why a site entry cannot read the zoom, let alone put it back. Injecting into the
page's world would let an entry save the zoom to `localStorage`, which is on disk, so it outlives the
app; M6 does not, being memory. The cost was overstated when this was first written: the app's own
scripts — the audio control — live in `.defaultClient` and stay isolated either way, so what changes
is only whether a website's own entry can touch that website's globals. The entry is already wrapped
in an IIFE, leaks nothing into the page by accident, and runs on the page it was written for and
nowhere else. The honest risk is the reverse direction: a page could redefine what an entry reaches
for, which for a wallpaper buys an attacker nothing an ordinary page cannot already do to itself. So:
a per-entry opt-in, `pageWorld: true` in the site schema, isolated by default, rather than changing
the world for everything. Whoever reviews an entry then sees which ones asked for it.

**M2 is built.** The manual version already existed — "Update Website to Current" in the menu points
the stored website at the address currently loaded — proof both that people want it and that the
mechanism works. The automatic version had to avoid the bug that item caused once: it fired on every
website with a host page and turned one of them into a GitHub 404. Hence remembering the last-loaded
address beside the stored one rather than over it, and only using it when the two differ in nothing
but the fragment. Anything more is a different page, and loading a different page than the one
somebody typed is how the 404 happened. (This paragraph used to say "the fragment or the query" and
M2's row said "the fragment"; `ScrollRestoration.addressToLoad` compares
`normalized(removeFragment: true)` on both sides and passes nothing for `removeQuery`, which defaults
to false — so the query is compared and the row was the right one.)

Worth saying out loud in the app somewhere, too: **a website's own settings are remembered per
website; where the page is inside itself is up to the page.** That is why two sites that look alike
behave differently, and nothing currently explains it.

---

## 5.6 Multiple displays: built, never tested (the D series)

**Every part of this was written on a one-display machine and has never been run on two.** Not a known
bug list; a list of claims nobody has checked — and D5, D9, D10 and D11 were checked by reading, turned out
false, and are fixed, which is worth knowing before trusting the rest of the column. The
centre-and-magnification design exists *because* of the second display — a rectangle framed on one
screen cannot come out right on another shape — so the feature most argued for has the least evidence
behind it.

| | The claim | What would show it is wrong |
|---|---|---|
| **D1** | A different website on each display | Two websites with different `display` values give two scenes. A website whose display is `nil` follows Settings, so two of those land on one screen and one is not shown. **Partly answered by D9/D10:** which website each display picks is now per display and tested; whether each display then *renders* the right one is still unseen |
| **D2** | A region framed on one display comes out right on the other | **The geometry half has been looked at, and it holds.** `CurrentWebsiteTests` covers framed-on-16:10-shown-on-16:9: `Zoom.region(inPageOfSize:)` derives the region's shape from the page size it is *shown* at, so the region is always the shape of the current display, and `magnification` is recovered from the clamped region. What is unseen needs two displays and is smaller than it was: whether `pageLayoutSize` picks up the new screen's `pageFrame` after a move, and whether `PageView.layOutContent` re-derives from `bounds` after `installContentView` |
| **D3** | Framing happens on the display the website is on | **The start is fine; the finish has a hole.** `beginCropSelection` matches the scene by website id, and `currentWebsite` *is* `primaryScene.website`, so the normal path cannot pick the wrong scene. But `finishCropSelection` finds its way back by `croppingSceneDisplay` with a `?? primaryScene` fallback — so if that display is unplugged mid-drag, the *main* scene gets its level and interactivity restored while the framed scene stays at `.floating` with `alphaValue = 1`. The only path in the app that can pin a window above everything permanently. See K12 |
| **D4** | The menu bar band, on a display with no menu bar | `installMenuBarBandIfNeeded` refuses when `menuBarHeight` is 0, which is a second display unless "Displays have separate Spaces" is on. That switch changes the answer, and both states need looking at |
| **D5** | ~~Plugging and unplugging while it runs~~ | **Checked by reading; false in three separate ways. Now K13, K14, K15.** "Scenes for displays that went away are torn down" is not what happens: `displaysInUse` reads `website.effectiveDisplay` without asking whether that display is attached, so `rebuildScenes` keeps the departed scene as wanted, and `DesktopWindow.setFrame` and `WallpaperScene.screen` both fall back to `.main` — two full-screen wallpaper windows stacked on the built-in display, each with its own timers and menu-bar band. `Display.withFallbackToMain` exists for this and is called from Settings only. A laptop hits it whenever undocked, and **two displays are not needed to reproduce**: attach one, point a website at it, unplug |
| **D6** | Different scale factors and different sizes side by side | The page lays out at each screen's `pageFrame`, so a Retina and a non-Retina display should each get their own. Never seen |
| **D7** | Where the page was, with the same website on two displays | **The guard argued for here does not guard this.** `displaysInUse` deduplicates by *website entry*, so it guarantees one **entry** reaches one display. The three per-page families are keyed by **URL** — two entries with different ids and the same URL, one per display, is legal, and they overwrite each other's `scrollPosition_`, `lastAddress_` and `zoomLevel_`. Since PR #10 the data stores are keyed by `website.id`, so the app runs two persistence schemes on two coordinate systems. Re-keying them to `website.id` settles both, at the cost of dropping saved positions once |
| ~~D8~~ | ~~"Show on every Space" and the playlist, per display~~ | **Answered by D9, and it did not work.** Two scenes rotating on their own timers could not have worked on any machine: the mark they rotate is one flag cleared list-wide. Fixed and covered by `CurrentWebsiteTests`. ~~"Show on every Space" per display is still unwatched~~ — **it does not need watching, it needs reading, and it was broken: K15 — which is now struck through, because the setting went and `.canJoinAllSpaces` moved into `DesktopWindow.init`.** `DesktopWindow.init` does not include `.canJoinAllSpaces` in its `collectionBehavior`; the only thing that adds it is the `Defaults.publisher(.showOnAllSpaces)` handler, iterating the scenes existing at the moment it fires. Launch order makes that correct at launch and wrong for every scene built afterwards |
| **D9** | ~~One `isCurrent` flag, cleared list-wide, behind a per-display rotation~~ | **Fixed.** `advance(on:)` and `scheduled(for:)` group by display, but `makeCurrent` cleared the flag on every website, so each display's playlist tick wiped the other's mark; that display read "nothing is current", counted from index 0, and never moved past its first website. Next, Previous, Random, Sound, Choose Region and Show on all acted through the same flag, so each acted silently on whichever screen last held it. Per display now, the rule as plain functions in `Support/Rotation.swift` so `swift test` covers the two-display case instead of owning two displays |
| **D10** | ~~Each scene's web view configured from the list-wide current website~~ | **Fixed.** `createWebView` read `WebsitesController.shared.current` for custom CSS, custom JavaScript, inverted colours, print styles and the Google user-agent case — baked in at creation, never revisited. On one display that is the scene's own website, so it never showed; on two, the second display's page ran the first's code. Same for the audio setting, the self-signed-certificate answer and "Update Website to Current" in the page's context menu. Scenes are handed their website in `init` now, before the web view exists |
| ~~D11~~ | ~~A page laid out for the display it started on, after it moves~~ | **Checked, and it was not happening.** `PageView` did cache `pageSize`, the region and the magnification from `init`, but a display change runs `NSScreen.publisher` → `rebuildScenes` → `installContentView`, and assigning `content` rebuilds the view before `layout()` can run on the stale numbers, so the cache was never read after it went stale. Removed anyway: `layOutContent` derives from `bounds` now, because a cached copy of a value the view is handed live is a trap for whoever adds the next reason to resize a wallpaper window. The original claim was reasoned from one file and did not survive reading the callers |

Ordinary use finds these faster than reasoning does — but four (D5, D9, D10, D11) were found by reading, not by using,
and D2 and D8 turned out not to need a second display at all (section 3 has what kept going wrong).
What is genuinely left needs hardware: D1, D4, D6, and the two remaining halves of D2.

---

## 5.7 The site catalogue: nobody has reviewed it (the S series)

Three lists, one pipeline, and a maintainer who has not looked at any of it:

```
sites/CANDIDATES.md      a link pool, larger than the catalogue and meant to stay that way
      ↓  somebody works out the settings and checks they hold
sites/*.yml               schema-checked entries, offered in the app's Site Gallery
      ↓  picked as one of the few worth shipping
featured: true             8 entries, installed on first launch
```

The pipeline is right and the numbers are the problem. Every entry was written by an agent from a link
and a guess, and the 8 that install themselves on a stranger's first launch are the first impression
of the whole app.

| | Item | Status | Notes |
|---|---|---|---|
| **S1** | The maintainer reviews the 8 featured | To do. **This one first** | What a new user sees before deciding whether the app is any good. Eight pages is an evening, and the highest-value hour in this section |
| **S2** | The maintainer reviews the other 30 | To do | Lower stakes — somebody has to go looking for these — but they carry the same claim, that the settings on them are right |
| **S3** | Most of the candidate pool has never been graduated | To do, forever | Not a backlog to burn down. A link is cheap and an entry is work, so the pool being larger than the catalogue is the normal state, not a debt. The exact count is deliberately not written here: it moves with every contribution, and a number in prose is a number that goes wrong. **This rule was written and then broken in this same section** — the counts three paragraphs up had drifted on all three figures by the time anyone checked them. They are gone now rather than corrected, which is what the rule said to do in the first place |
| **S4** | Which of the three lists is the source of truth for a reader | Half answered | `CANDIDATES.md` is a pool, `sites/*.yml` is the catalogue, `NOT-INCLUDED.md` is the refusals. Both READMEs now link `CANDIDATES.md` directly, so a reader is no longer dropped on the directory to guess — that half is done. What is left is that a reader landing on `sites/` still sees the contributor guide first and has to work out which of its neighbours is the list of what the app actually offers |

**What would simplify S4 without another file.** The Site Gallery already shows exactly the 38, with
their settings, filterable by tag — the readable list, in the one place where picking something has an
effect. The repository does not need a fourth rendering of the same data; it needs the two markdown
files to say plainly what they are for and to stop reading like alternatives to the app.

---

## 5.8 Media controls for the panel (the V series)

The panel already knows where a video is — it reads `currentTime` and `duration` out of the page and
writes them back, to keep synced displays in step. Everything a transport needs is in hand; what is
missing is the controls and the decision about which pages get them.

| | The item | What is known |
|---|---|---|
| **V1** | Pause, play, and step back or forward on the column | The clock already reports `duration`, so a page either has a video or it does not, and the controls can simply not appear when it does not. `MediaSync` already writes `currentTime`, so stepping is the same call it makes to correct drift |
| **V2** | A progress bar under the picture | The same reading drives it. It has to update while the panel is open and stop when it closes — the panel is transient and a timer that outlives it is a timer nobody switched off |
| **V3** | What a control means in a sync group | Pausing one display of a synced pair is a contradiction: the follower is corrected towards the leader every five seconds and would be dragged back into playing. A control pressed on any member has to act on the group, which makes the group the unit a transport acts on rather than the display |
| **V4** | Live streams have no transport | `currentTime` on a live stream is relative to a sliding window, seeking is often refused, and "back thirty seconds" may not exist. The controls have to be absent rather than present and broken, and the test for it is not the same as "has a video" |
| **V5** | Save the picture a column is showing | A button on the column writes the current frame to the Desktop, and a press held past a second writes a short GIF instead. **At the display's own resolution, not the panel's.** The panel takes its snapshots at 260 points because that is all it draws — a saved frame taken the same way would be a thumbnail, so this needs a second snapshot at full size, taken only when asked. Do not confuse the two paths: the cheap one runs several times a second while the panel is open, the expensive one runs once and cost about 600ms a frame when it was the default |

Two things these need that do not exist yet. The clock reports the leader's position on a five second
tick, right for correcting drift and far too slow for a progress bar; a transport wants its own faster
read while the panel is open, and only then.

And a GIF needs frames held rather than shown. The panel's snapshots are deliberately transient — each
refresh replaces the last and the previous images are released, which is why forty-five seconds of
continuous refreshing moves the app's memory by less than it fluctuates on its own. Recording has to
keep them, at full resolution, for as long as the press lasts: a second of a 4K display is tens of
megabytes, so it wants a frame budget and a hard stop rather than "until the user lets go".

---

## 6. Known and not yet fixed (the K series)

Reported while using the app, reproduced, and left alone for now. Each is written down rather than
fixed so that the first release is a thing that exists.

| | What happens | What is known about it |
|---|---|---|
| **K1** | A YouTube video cannot be shrunk back into the YouTube page, so there is no way to sign in | The address is rewritten to the player-only page and framed by a host page, because YouTube's player answers "error 153" when it is the document rather than a frame in one. That gets the video up and takes the site with it: no page around the player to navigate, nothing for Browsing Mode to click into. Bilibili's player is a normal page, which is why the two differ. Any fix has to keep 153 away. **"No way to sign in" is too strong.** The address is an ordinary field on the website, and cookies now live in a store keyed on `website.id` rather than on the URL — so changing the address back to `youtube.com/watch`, signing in through Browsing Mode, and changing it back to the embed keeps the session, because the store does not move when the address does. Nobody is told this; the cheapest fix is a sentence of help text, not new UI |
| ~~K2~~ | ~~A framed region does not land exactly where it was framed~~ | **Fixed by L0.** The gap was the conversion described in L0's third bullet. Moving the page changes the stored value directly, so there is no conversion left to be out by a point. The region also survives however the mode is left now, and no longer reloads the page it is framing |
| **K3** | Switching website can take several seconds | It is a page load, and swap loading keeps the previous page up for all of it, so nothing is broken — but nothing tells the user it is working, and a few seconds of unchanged wallpaper after choosing a website reads as the choice not registering |
| **K4** | Nothing is done to reduce what the app costs when nobody is looking at it | Deliberate, for now. See section 4 |
| **K5** | No way to choose the app's language from inside the app | It follows the system. macOS has a per-app setting — System Settings → General → Language & Region → Applications — and it works today, but nobody finds it: a person running their Mac in English who wants Nifro in Chinese has no reason to think the answer is three levels into System Settings. A picker in Settings that writes `AppleLanguages` and offers to relaunch would cost little |
| **K6** | The wording is right in places and thin in others | ~~Every setting now says what it does~~ — counted, and that is optimistic: seven `SettingHelp` / `.help(` sites across `Screens/`, against two settings screens of 25 KB. Those that exist were written one at a time and it shows: some explain the mechanism, some the consequence, a few both at different lengths. Worth one pass reading them as a set rather than as twenty separate answers |
| **K7** | Nothing anywhere handles HDR | Not one line of the app touches it: a page's HDR content is whatever WebKit decides to do with it, and nobody has measured what that is. A wallpaper is on screen all day, so getting this wrong is visible all day. Needs a real HDR source and a look at what actually reaches the display before anything is worth designing |
| **K8** | A Bilibili entry has a generic icon where a YouTube entry has the video's own cover, **in the Websites list only** — `previewImageURL` has one caller, the row icon in `WebsitesScreen`, so the Site Gallery is not affected | YouTube publishes a cover at a fixed address derived from the video id, so it costs nothing. Bilibili's is behind `api.bilibili.com`, a network request and a JSON field (`data.pic`) rather than a URL you can build. Worth doing, but it is the first place the app would call a site's API rather than just load a page |
| **K9** | One catalogue entry with a `zoom` silently kills the live Site Gallery on every installed copy | **Found by reading, never triggered, and all four CI gates pass it.** The two sides of `sites/index.json` disagree about how a `Zoom` is spelled: Swift's synthesised `Codable` encodes `CGPoint` as an unkeyed array, so it wants `{"scale":2,"center":[0.5,0.4]}`, while the generator and `schema.json` produce `{"centerX":0.5,"centerY":0.4,"scale":2}`. Verified by round-trip: decoding the generator's shape throws. The generated Swift path is fine — it constructs `Zoom(center:scale:)` directly — which is why a local build never sees it. `SiteCatalog` then decodes `[Entry].self` in one go under `try?`, so **one bad entry loses the whole fetch**, falls back to the bundled snapshot and reports `isLive: false` with nothing said. No entry uses `zoom` today, so the first contributor to add one breaks it for everybody. Two fixes, the second mattering more: map the keys, and stop making this path all-or-nothing |
| **K10** | Toggling Browsing Mode while the app is disabled desynchronises it for good | `isBrowsingMode.didSet` returns early when `isEnabled` is false, and the write is never replayed: `isEnabled.didSet` calls `resume`, `loadWebsite` and both timers on the way back up, never `window.isInteractive = isBrowsingMode`, and `resume()` does not read it either. So `Defaults` says true, the menu draws a checkmark, and the windows sit at `.desktop` until something unrelated triggers `rebuildScenes`. Reachable three ways: the menu item gates on `currentWebsite != nil`, not `isEnabled`; the global shortcut and the Shortcuts intent gate on nothing. **The failure shape section 4 is a monument to**: two owners for what is on screen, one dropping writes. One line in `isEnabled.didSet` |
| **K11** | The per-page zoom level is lost on every website switch and every reload | `zoomLevelWrapper` restores on `didLoadPublisher` and reads `webViewController.webView`, but swap loading's replacement web view shares the navigation delegate — so when `didFinish` arrives the live web view is still the old one, and the old page's zoom is written back to the old page. `adopt(_:)` then restores the scroll position on the new web view and never applies `pageZoom`. `PerPageDefaults.zoomLevel` is written correctly; only the restore path misses |
| **K12** | Unplugging a display mid-crop pins a wallpaper window above everything, permanently | See D3, which has the mechanism |
| **K13** | An unplugged display's wallpaper does not go away, it stacks onto the built-in one | See D5. Two full-screen windows on one screen, two sets of timers, two menu-bar bands competing for one menu bar |
| **K14** | A display plugged in while running gets a scene that never loads a page | See D5. `rebuildScenes` assigns the website, installs the content view and resets the playlist timer, but calls neither `loadWebsite()` nor `reload()`; the web view is born hidden and only a load reveals it. It also skips `resetTimer()`, so the new scene has no reload timer. Only fires when some website names that display explicitly |
| ~~K15~~ | ~~"Show on every Space" never reaches a scene built after launch~~ | **Gone with the setting.** It was off by default, which made it a wallpaper that disappeared when you switched Mission Control desktop — not a preference. `.canJoinAllSpaces` is set in `DesktopWindow.init` now, so a scene built later gets it like every other one. **Not yet checked on a real machine:** switching desktop with the app running is the one-line verification nobody has done |
| **K16** | Syncing a display eats the website that was on it, and leaves a duplicate behind every time | `mirrorAcrossSyncGroup` overwrites the follower's existing entry in place — `update(existing.id) { $0 = copy }` — so the page that display was showing is gone, not set aside, with no way back. With no entry on the follower it appends a new one instead, and nothing ever removes those, so a list picks up a copy of the leader's website per display per group. Measured on the maintainer's own list: eight entries, six of them copies of two websites, two originals (Calculating Empires, WindowSwap) overwritten and unrecoverable. Both halves are one decision — a mirrored entry is a *view* of the leader's, not a website in its own right, and it should not be in the list at all |
| **K17** | The website chooser on a display lists only that display's own websites, which is usually one | `DisplayPanelModel.refresh` builds `choices` as `all.filter { $0.effectiveDisplay == scene.display }`, so a website reaches the menu only once it belongs to that display — and the way a website gets a display is by being chosen there. A display with one website has a one-item menu, which reads as "the chooser does not work". The control is for picking any website *and* moving it here, so the list wants to be every website, with the ones already here marked |
| **K18** | The correction can make the picture stutter | Every change of `playbackRate` costs a visible hitch on WebKit (bug 208142; dash.js refuses rate changes under 0.25 on Safari for this reason). The hysteresis around `engage`/`release` makes one correction cost two changes rather than one per pass, but nothing has measured how often a correction episode starts on a real stream over an hour — a page that stalls every few seconds would be changing rate every few seconds. Needs a count of rate changes per minute before any tuning, and if it is high the answer is a wider `engage`, not a smaller `nudge` |
| **K19** | A new install opens with nothing on screen | No initial configuration, so the first thing a new user sees is a wallpaper that is not there. It should ship with websites already in the list, muted, in this order: **floor796**, **Svalbard**, **Calculating Empires** — floor796 up on a single display, Svalbard added on the second when there are two. Muted because a wallpaper that makes a sound the moment it is installed is a wallpaper that gets uninstalled. All three are already in `sites/index.json` and all three already carry `audio: muted`, so this is a first-run step that reads the catalogue, not new entries |

---

## 7. Engineering (the E series)

| | Item | Status |
|---|---|---|
| ~~E16~~ | ~~Universal binary~~ | **Not doing** (your call). One thin build per architecture instead |
| ~~E17~~ | ~~Three families of per-page `UserDefaults` keys grow without bound~~ | **Measured, and they do not.** On a real install after real use: `com.pathgao.nifro.plist` is 4378 bytes, 21 keys, and **zero** of all three families. The reasoning that said "one key per page ever visited" was wrong about every one — `scrollPosition_` is written only from `reload()` and only when the position is not `[0, 0]`, `lastAddress_` needs the page to carry a fragment, `zoomLevel_` needs somebody to pick Zoom In from the context menu. Growth follows what the user does to a page, and a wallpaper is a thing nobody touches. No pruning, and the reason is a number instead of a guess |
| ~~E18~~ | ~~`forgetWherePagesWere` cannot be tested~~ | **Replaced with something that cannot be forgotten instead.** A test was the wrong tool: the failure to guard against is "a fourth kind of per-page record is added and the sweep is not told", and a test of the sweep's filter cannot see a prefix never handed to it. The three prefixes are cases of `PerPageDefaults` now, which builds the keys too, so a fourth kind has to be a case to get a key at all — and the sweep is `allCases`. `UserDefaults.standard` is still named directly and the sweep still has no test; it no longer needs one |
| ~~E20~~ | ~~`nifro://reload` did nothing but put up an alert~~ | **Fixed.** `URLCommands` read `urlComponents.path`, and only `nifro:reload` puts the word there — `nifro://reload` puts it in the *host* with an empty path, so the command fell through to "The command “” is not supported". That message names nothing and is what a real typo gets, so there was no telling "wrong number of slashes" from "no such command". Both spellings are accepted now, plus `nifro:///reload`, and the extraction is a pure function in `Support/URLCommand.swift` with the three spellings pinned. Found by using it: the alert in the screenshot was four of these stacked up |
| **E21** | `nifro://` is registered to stale copies of the app | **Test URL commands with `open -a <path> "nifro:reload"`, never plain `open "nifro:reload"`.** LaunchServices holds this scheme against every build ever made on the machine, `~/.Trash` and derived-data copies included, and picks one of them rather than the installed app. Nothing in the repo causes it and nothing in the repo can fix it. Written down because the plain form cost real time once, driving a three-week-old build |
| **E19** | The first page of the session is loaded by the content-rules subscription | Nothing in `didLaunch` loads anything. `Defaults.publisher(.contentRulesURL)` sends its current value on subscribe, and the handler puts the first wallpaper up. It happens to be the right order — pages come up with the blocklist already compiled — but nothing says so, and anyone changing that subscription takes the wallpaper away at launch with no clue pointing back here. Left alone rather than restructured: the ordering is load-bearing and cannot be checked without running the app. There is a comment on the subscription saying so now |

---

## 8. Signing and distribution

From looking into what [AeroSpace](https://github.com/nikitabobko/AeroSpace) actually does:

| | AeroSpace | Nifro | Reason |
|---|---|---|---|
| Signing | A self-signed certificate on the machine | The same, `Nifro Signing` | To Gatekeeper the two are the same, but the identity is not: a stable certificate keeps the app's designated requirement stable, and the security-scoped bookmarks holding local-file wallpapers are tied to it. Ad-hoc changes identity every build and breaks them |
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
PathGao/tap/nifro` resolves to a repository literally named `homebrew-tap` — a second repository to
own, plus a token here with write access to it. Worth doing for one reason rather than for the
shorthand: tapping clones this repository, all 6 MB of source and images, onto every user's machine
and refetches it on every `brew update`, where a dedicated tap repository is a few kilobytes. Do it
when there are enough users for that to be somebody else's bandwidth rather than a tidiness argument.

Plain `brew install --cask nifro`, with no tap at all, means being in Homebrew's own cask repository.
That has a notability threshold — 75 stars, or 30 forks, or 30 watchers. Two stars today. A milestone
to notice rather than a task to schedule.

**Release immutability is off, on purpose for now.** The switch is in Settings → General, under a
Releases heading that is not in the sidebar, and it forbids changing a published release's assets and
tags. Right end state, wrong one today: the two download links in the README only work because the
v0.1.0 assets were *renamed* after publishing, to drop the version from the file name. Turn it on once
a few releases have gone out without needing to be touched afterwards.

### Knowing there is a new version (the U series)

Nothing in the app knows a release exists. No Sparkle, no check, no menu item — the only upgrade path
is `brew upgrade`, and only for people who installed that way. Somebody who took a disk image from the
README stays on the version they took until they happen to visit the repository again, and for a menu
bar app that runs from login and is rarely opened on purpose, that is close to never.

| | Item | Status | Notes |
|---|---|---|---|
| **U1** | Check for a new version and say so | To do. **Do this one first** | One request to `/repos/PathGao/Nifro/releases/latest`, compare `tag_name` against `SSApp.version`, put "Version 0.2.0 is available" in the menu linking to the release. No dependency, no entitlement, no keys, no infrastructure — the release API is public and already there. It tells a brew user to run `brew upgrade` and a direct-download user that there is anything to download. Needs a cadence that is not a poll on every menu open, and a way to turn it off |
| **U2** | Download and install it too (Sparkle) | Not now | Much more than U1 looks. Sparkle needs an appcast feed to publish and an EdDSA key pair to sign updates with — a second signing identity to keep for the life of the app, on top of the certificate. A sandboxed app cannot replace itself either; that goes through Sparkle's installer XPC service, more entitlements on an app whose short entitlement list is a feature. **And the feed URL is permanent from the first version that ships with it**: Markpad is on its second repository owner and its release workflow still asserts that the *old* URL serves this project's feed, because every install up to v2.7.0 asks that address and nothing else. Renaming this repository once was free; it stops being free the day an update feed points into it |
| **U3** | Tell Homebrew the app updates itself | Only with U2 | The moment the app can replace its own bundle, the cask has to say `auto_updates true`. Without it `brew upgrade` and the app fight over the same bundle, and brew's idea of the installed version goes stale. U1 alone does not need this, another reason to start there |

The first version to benefit from U1 is the one after it ships — 0.1.0 users will not be told about
0.2.0 by an app that could not check. An argument for doing it early rather than for doing it well.

---

## 9. Explicitly not doing (do not raise again)

| | Proposal | Why it was turned down |
|---|---|---|
| **X1** | Change web engine (Electron / Tauri / CEF) | WKWebView is a system process shared with Safari; anything else costs more. The problem is scheduling, not the engine |
| **X2** | Rewrite in pure SwiftUI | The `NSMenu` + `NSWindow` we have is fast and correct; moving to `MenuBarExtra` would be a step back |
| **X3** | Tuist / XcodeGen | `project.pbxproj` is 873 lines, nowhere near the size where conflicts become a disaster, and adding a file to it by hand is four lines |
| **X4** | A dependency injection framework, a plugin system | There is no second implementation, so there is nothing to base the abstraction on |
| **X5** | Use only the CLT as a type-checking gate | **Tried, failed**: KeyboardShortcuts uses `#Preview`, that macro plugin ships only with Xcode, and the Command Line Tools cannot build the dependency module. Xcode has to be installed |
| **X7** | Camera / screen capture input (`getUserMedia`, `getDisplayMedia`) | The entitlement is per process, which means permanently giving a process that renders arbitrary user URLs around the clock the ability to reach the camera; the shorter a wallpaper app's permission list, the easier it is to check. Capture-card compositing belongs in OBS, surveillance in an NVR client. Upstream [#125](https://github.com/sindresorhus/Plash/issues/125); the full argument is in UPSTREAM-ISSUES.md §4. It **is technically doable**; the reason for refusing is not difficulty |
| **X8** | The real-wallpaper route: render the page to an image and hand it to `NSWorkspace.setDesktopImageURL` (was P6, and A2 in section 2) | Never built, and now refused rather than blocked. It ends the app. A wallpaper set this way is a picture: no clicks, no Browsing Mode, no scrolling, no hold-to-interact, no logging into anything — and interaction is what this app is. Refreshing it means re-rendering and setting it again, which macOS cross-fades, so a clock would cross-fade the whole desktop once a minute. The renderer it needs is the offscreen one that photographs blank for exactly the pages worth putting up (section 2). Against that: the menu bar colour, already solved; Mission Control and Stage Manager behaviour; the picture surviving after the app quits; and idle power, which nobody has measured. A tool that turns a web page into a wallpaper image is a real idea — it is just a different program, and it does not need a menu bar app at all |
| **X9** | Put the user's own Chrome window on the desktop layer instead of rendering the page ourselves — a hotkey brings it forward to use, a hotkey sends it back, crop and full-screen video kept | **The interaction model this asks for already ships.** `DesktopWindow.isInteractive` moves the window between `.desktop` and `.desktopIcon + 1`, and `HoldToInteract` is the hold-a-key version of the same switch. The only new thing is the engine, and the engine is where it fails. **No public API sets another process's window level**: `NSWindow.level` applies to windows this process owns; the Accessibility API has position, size and `AXRaise`, but no level and no lower; what is left is SkyLight calls against a connection we do not own, which is yabai's route — a scripting addition injected into Dock — and it needs part of SIP turned off. A wallpaper app cannot ask that of anyone. **Giving up the icon layer makes it buildable and still not worth it.** Chrome's `--app=` mode gives a window with no tab bar and no address bar, a transparent click-absorbing pane above it keeps the window from ever being raised so it sinks under every other app, and crop falls out of a negative `--window-position` with an oversized `--window-size` — the page lays out full size and one region shows, our own crop semantics for free. What kills it: **the wallpaper's lifetime moves into an app we do not control.** Cmd-Q on Chrome ends the wallpaper, a Chrome auto-update restarts it, a crash-recovery bubble lands on it. And the entitlement list goes from four lines to full Accessibility access with the sandbox off. **Screencasting it instead is worse.** CDP `Page.startScreencast` into our own `.desktop` window keeps the icon layer, but DRM video arrives black through output protection — the one thing Chrome was wanted for is the one thing that does not survive — the frames are JPEG, so animation degrades in exactly the case this app exists for, and it needs `--remote-debugging-port` open, which hands the user's entire browser identity to any process on localhost. **The motive has a cheaper answer anyway.** WKWebView shares Safari's engine but not its identity: every app gets its own `WKWebsiteDataStore` inside its own container, so nothing is inherited from Safari or Chrome — but it is persistent, so logging in once through Browsing Mode holds for good, and `ContentRules` already covers the one extension anybody was going to install for this. See also X1, which this is a weaker form of, and section 2's second complaint, which this reverses |

---

## 10. Reviewed and deliberately left alone (with the data)

The conclusions left behind by two rounds of machine review (the tidy gate, the duplication scan).
**What was ruled out is easier to lose than what was built**, so this section stops someone raising the
same thing next round. The original reports were `docs/TIDY-REPORT.md` and `docs/DUPLICATION-REPORT.md`,
deleted when this section was written; they exist only in git history, and their line numbers have gone
stale from later refactoring, so do not change code against them.

| | Candidate | Data | Why it stays |
|---|---|---|---|
| R1 | `SecurityScopedBookmarkManager`, 176 lines | Serves 1 to 3 call sites | It sits on the sandbox trust boundary. Replacing it is an equivalent rewrite, and no check would catch getting it wrong |
| R2 | `Cache` + `SimpleImageCache`, 270 lines | Same | Same |
| R3 | `WebsiteIconFetcher`, 200 lines | Same | Same |
| N1 | A batch of hand-written loops replaced by regexes or the standard library | — | An equivalent rewrite. The code being replaced carries domain rules, and we have no assertion that could go red |
| N2 | A batch of changes whose only verification was "it type-checks" | — | There is no answer to "which check would go red" |
| N3 | Two animation durations, 0.25 / 0.35, that look like duplication | 2 places | One is an opacity transition, the other a content fade-in: **they change for different reasons**. Merging them manufactures coupling |
| R4 | `sites/index.json`, fetched from `main` when the gallery opens | 1 place | A code path into the user's web view that does not go through a release. An entry carries `css` and `javaScript`, and adding one is a merge on `main` rather than a build, a notarisation or a version bump — so a bad entry reaches every installed copy the next time somebody opens the gallery. **The automatic half is narrower than it reads**: `featured` comes from the compiled-in snapshot rather than from the fetch, and first-launch installation only walks featured — a fetched entry's `css` and `javaScript` reach a web view only when somebody presses Add on it in the gallery. The conclusion stands; the blast radius is one deliberate click wide rather than zero. K9 is the other half of this surface: the fetch has no per-entry failure mode, so one bad entry costs the whole list. CONTRIBUTING asks contributors not to submit JavaScript that sends anything anywhere, a policy and not a control. Kept because the alternative loses the thing it is for: entries contributed between releases showing up without an app update. Worth knowing the site list is release-grade surface and reviewing it as such |
| ~~R5~~ | ~~`Nifro/Support/Extensions.swift`, 3600 lines, a third of the app~~ | — | **Split, after the argument for keeping it whole turned out to be invented.** The four things in it that are not extensions — `SimpleImageCache`, `WebsiteIconFetcher`, `SecurityScopedBookmarkManager`, `ScrollableTextView`, 776 lines — are their own files now, and the rest is 2810 lines of actual extensions. The reason first given for not doing it was that the file is cheap to diff against upstream: **there is no upstream remote**, no commit has merged from Plash, and the file has been edited 17 times here. Registering a file in `project.pbxproj` by hand is four lines, just done for `Rotation.swift`. What is still true: **nothing in the file is dead.** A reading-based claim that 200 lines were unreachable was checked with `periphery` and was wrong — each of those types is reached from a live extension a few hundred lines away, itself an argument for the file being too big to reason about by eye |
| R6 | `DesktopWindow.reducedRegion` and `CGRect.screenFrame(inScreen:)` | 1 read, 0 writes | Nothing assigns `reducedRegion`; the visibility policy that used to came out with the power machinery. Kept because shrinking the window to part of the desktop is the L series and this is the shape it needs. `periphery` cannot see it, because the property is read. The doc comment says it is never written now, which matters to anything reasoning about where the wallpaper window is |
| N4 | Narrowing the visibility of `Website.InvertColors` | Tried twice, red twice | The conformance is declared at the top level rather than inside the type's scope, and the stored property that uses it is read from other files |
| ~~N5~~ | ~~Narrowing `WallpaperContent` / `RenderingMode`~~ | — | Still true of `WallpaperContent`. `RenderingMode` is **gone**: narrowing it was the wrong question. It was two cases computed from `website?.allowsInteraction` and read at exactly one comparison, so it was a `Bool` with an enum around it, and the compiler is the check that the collapse is faithful |
| N6 | A cross-fade when switching website, instead of the straight swap | 1 place | Both pages would have to be in the window at once, which means a container view and a second answer to what `window.contentView` holds — the exact ambiguity that cost a blank wallpaper before. Two loaded pages can just change places. Revisit only if the straight swap reads as abrupt |
