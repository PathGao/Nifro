# Nifro Roadmap and Working Ledger

[简体中文](ROADMAP.zh-Hans.md)

> Source of truth for scope. The README is the community-facing write-up; this is the working document.
> Rewritten 2026-08-27 against `54cac6a` (v0.1.3). Everything below was checked against the code it
> describes. Items that shipped are gone, not struck through — the one-line residue that stops a
> question being re-litigated lives in section 14.
>
> Sections 8 to 11 re-checked 2026-08-27 against the tree at `53f110b`, which is `54cac6a` plus #24
> to #30 and two commits on `fix/docs`. Three entries closed, four opened, and several corrected in
> place. Everything closed was read in the code as it stands; nothing was closed off a commit
> message, and K12 and K28 both survived commits that read as though they had fixed them.

**The rule this document keeps failing.** Before writing "nobody has looked", read the callers. Every
claim here that has ever turned out false failed that way, and reading cost less than the hardware it
was waiting for.

---

## 1. What this is

Nifro puts a website on the desktop wallpaper, one page per display. Distribution is a Homebrew cask
plus a GitHub Release, not the Mac App Store.

**Where this stands after v0.1.3.** The menu-bar menu was replaced by a per-display panel (#21). That
was the right move and it is half-landed: the panel is the surface a website is chosen on now, and
eleven things the menu could do have no entry point at all (section 8). Most of what is open in this
document is either that wiring or something the panel made visible.

```
Open      W1-W9 wiring   K1 K6 K8 K12 K16-K18 K20-K24 K26-K31 K33-K38 bugs   L1-L4  V1-V5  S1 S2 S4  D4 D6  E21-E23  U2 U3
Parked    K7 HDR (your call), the P series (needs a measurement first)
Blocked   nothing
```

---

## 2. Power (the P series)

All of it is out of the code — 811 lines removed, back to what upstream does: the page renders and
stops only when disabled, when the screen is locked, or on battery. Every piece of it owned the answer
to "what is being rendered right now", which is the answer Browsing Mode also changes, and each fix
exposed the next one.

Before any of it returns:

1. A measurement of the cost it claims to remove, taken while the machine is idle, on the state it
   targets — a covered wallpaper, not a browsing session.
2. Exactly one owner for "what is being rendered". This is what broke every previous version.
3. An off switch that needs no explanation.

Upstream stops for three reasons only and does nothing about occlusion at all. That is the baseline
any of this has to beat. Two ideas from the original design are refused rather than deferred and now
live in section 12 as X10 and X11.

---

## 3. Blocks: a page as a piece of the desktop (the L series)

Zoom answers *which part of a page*. Blocks answer *where on the desktop it goes*, because a zoomed
fragment usually belongs in a corner rather than at full-screen size. The case is a number that exists
only on a web page — a usage counter, a build dashboard, a deploy status — that nobody will ship a
widget for.

Most of the machinery exists: a scene owns a window, `Zoom` picks the region, `DesktopWindow` sets an
arbitrary frame, several scenes already run at once.

| | Item | Notes |
|---|---|---|
| **L1** | A website has a place and a size on its display, not just a display | Stored as fractions, like `Zoom`, so a block survives a change of display. `Website` has no place/size field today; `DesktopWindow.reducedRegion` still exists and is still written by nothing |
| **L2** | A four-way grid to snap to, and free placement for anything else | The grid is the affordance, not the model. Free placement is the model |
| **L3** | Whether the grid uses the whole screen or keeps clear of the Dock | A setting. **Not as cheap as this row used to claim:** `pageFrame` is `frameWithoutStatusBar`, and `visibleFrame` appears in the app in exactly one place, inside `menuBarStripHeight`. Nothing computes a Dock-clear rectangle yet |
| **L4** | Which block takes a click | Browsing Mode and hold-to-interact now mean *one display's* wallpaper. With blocks they have to mean one block |

**Three constraints, named so they are not discovered later.**

- **Two things sizing one window.** A block has to be the window's *base* frame with occlusion
  shrinking inside it, never the reverse. That collision is what made cropping and the visibility
  policy fight until cropping stopped moving the window at all.
- **One web process per block**, and since per-website data stores landed, one data store as well.
- **A block is not a window the user can grab.** No title bars down there. Placement happens over the
  wallpaper or from a menu of grid positions.

**Two traps L1–L4 inherit from the shipped region picker.**

- **The model is *the frame moves, the page stays still*** — not Photos' *content moves*. A web page
  can pan and zoom itself, so a moving picture has two readings and the page's own magnification
  multiplies with the frame's. Reasoning is in `Zoom/CropSelectionView.swift`.
- **`Geometry.resizedFrame(byGrowing:)` grows around the frame's own middle on purpose.**
  Pointer-anchored zoom slides the frame out from under the pointer when the page is still. Do not
  re-add it.

The overlay's job is to swallow scroll and `magnify(with:)` so gestures move the frame and not the
page — `webView.allowsMagnification` is on. `hasPreciseScrollingDeltas` separates trackpad (scroll
pans, pinch zooms) from wheel mouse (wheel zooms). Drag always moves, on every device.

---

## 4. What a page remembers (the M series)

Sound and the framed region belong to the website. Where the *page* is inside itself belongs to the
page, and there are four ways it can hold that.

- **M1** `localStorage` / IndexedDB — **survives.** Stores are per website entry (`website.id`), not
  per origin, so two entries on one site share nothing and deleting an entry drops its store.
  Orphans are reaped at launch. *Consequence nobody has written down:* syncing a display that had no
  entry mints a new id and therefore an empty store, so the follower is signed out of a site the
  leader is signed into.
- **M2** URL fragment — **survives.** *Trap:* the last-loaded address is stored *beside* the
  website's own, never over it, and is used only when the two differ in nothing but the fragment.
  Overwriting turned a website into a GitHub 404 once. See K28 — it stops recording after a suspend.
- **M3** Document scroll — survives a reload, not a quit. Captured only from `reload()`.
- **M4** Memory only — nothing to be done.
- **M5** Half in the address, half in memory (floor796) — *where* comes back, *how close* does not.
- **M6** Keep the page instead of remembering it — **proposed, nothing implements it.** Complete
  within one run of the app and nothing beyond it. Per-website switch. `releaseWebView` currently does
  the opposite and drops the process on suspend.

**Two ways past M5, neither urgent, and they do not conflict.** **B** is M6 as a per-website switch:
it helps every site, depends on no site's internals, and makes switching back stop being a page load.
**C** is `pageWorld: true` on one catalogue entry: the site's own magnification then survives a
restart, at the cost of that entry losing its isolation and depending on floor796's private fields.
C must stay a per-entry opt-in, isolated by default — never a global world change. The app's own
scripts (the audio control and the media clock) sit in `.defaultClient` either way.

**Worth saying out loud in the app:** a website's settings are per website, and where the page is
inside itself is up to the page. Nothing tells anyone this.

---

## 5. Multiple displays (the D series)

Written on a one-display machine. Everything that could be answered by reading has now been read, and
most of it was wrong or already broken — those fixes are in section 14. Two claims are left that only
hardware can settle.

| | The claim | What would show it is wrong |
|---|---|---|
| **D4** | The menu bar band, on a display with no menu bar | The gate is `screen.statusBarThickness > 0`, already tested for the secondary-screen case. The unknown is what "Displays have separate Spaces" does to `visibleFrame`, which is an OS behaviour and unreadable from here |
| **D6** | Different scale factors and different sizes side by side | Nothing in the app branches on backing scale; per-screen layout is `pageFrame` → `DesktopWindow.setFrame`. There is no code to read that could be wrong, only pixels |

D7 was in this section and does not belong here: it is a defect with a known fix, not an unchecked
claim. It is K31.

---

## 6. The site catalogue (the S series)

`CANDIDATES.md` (pool) → `sites/*.yml` (schema-checked catalogue) → `featured: true` (installed on
first launch). Every entry was written by an agent from a link and a guess, and the featured ones
install themselves on a stranger's first launch.

| | Item | Notes |
|---|---|---|
| **S1** | The maintainer reviews the featured entries | **This one first.** They are what a new user sees before deciding whether the app is any good. An evening's work, and the highest-value hour in this document |
| **S2** | The maintainer reviews the rest of the catalogue | Lower stakes, same claim: that the settings on them are right |
| **S4** | A reader landing on `sites/` meets the contributor guide first | Half done — both READMEs now link `CANDIDATES.md` directly. Do not add a fourth rendering of the same data: the in-app Site Gallery is the readable list. Make the two markdown files say what they are for, near the top |

**A rule, not an item:** the candidate pool stays larger than the catalogue. That is the normal state,
not a backlog. Never write a count of it in prose — and note that section 6 as it stood broke its own
rule twice, three paragraphs after stating it.

---

## 7. Media controls for the panel (the V series)

**Read this before the table.** Every row here used to describe `MediaSync`, the multi-display sync
feature, as though it were running. None of it is in the tree: no clock, no epoch, no reading, no
per-page script. `mediaClock()` and `mediaClockCode`, which these rows named as though they were code
somebody could go and read, appear nowhere in `Nifro/`. What survives of the feature is `docs/shelved/MULTI-DISPLAY-SYNC.md`,
whose first line says it is removed and built by nothing. So no row here is "half built" — every one
of them is downstream of rebuilding that, and the rows say which part each needs.

| | The item | What is known |
|---|---|---|
| **V1** | Pause, play, and step back or forward on a column | Nothing exists, detection included: nothing in `Nifro/` reads a `<video>` at all, so "does this column have a video" cannot be answered today. Both halves have to be built. The detection is one line of the shelved script — largest video with a finite duration. The transport was never built even there: that design only ever wrote an epoch and let each page compute its own seek, so pause, play and step are a new message type rather than a reuse of anything |
| **V2** | A progress bar under the picture | Half the prerequisite exists and it is the cheap half: `DisplayPanelModel.startLiveRefresh` already runs while the panel is up and cancels the moment it closes, so a reading would have a loop to ride. The reading itself does not exist |
| **V3** | What a control means in a sync group | There are no sync groups. `WallpaperScene.shouldPlaySound` is where the last rule that mentioned one was removed, and it names where the design went. Read § 4 of `docs/shelved/MULTI-DISPLAY-SYNC.md` first — it is the list of defects the feature was pulled for, and this item cannot be specified ahead of deciding what replaces them |
| **V4** | Live streams have no transport | Nothing reports it, because nothing reads a `<video>` duration. The finiteness test is one line and comes back with V1's detection; there is no separate work here |
| **V5** | Save the picture a column is showing | Not built at all. A button writes the current frame to the Desktop; held past a second, a short GIF. **At the display's own resolution** — the panel snapshots at 260 points, so this needs a second full-size path, taken only when asked, at roughly 600 ms a frame on 4K |

**The prerequisite V1 and V2 share** is a per-page reporter, and there is not one to tune. The panel's
own loop is 80 ms and is not the constraint; freshness is capped by how often a page can be asked,
which is a script somebody has to write. The shelved design reported upward every 1000 ms and
corrected every 250 ms — starting points, not measurements of anything running. **V5's GIF** needs
frames held at full resolution — a second of a 4K display is tens of megabytes, so it wants a frame
budget and a hard stop, not "until the user lets go".

---

## 8. What the panel refactor has not wired up yet (the W series)

Capabilities the menu had that the panel does not. None of these are broken code; they are things with
no entry point. Baseline for every row: `git show 54cac6a~1:Nifro/App/Menus.swift`.

| | Gone | Reachable today |
|---|---|---|
| **W1** | App-wide Enable / Disable | Global hotkey and the Shortcuts intent only. No control anywhere in the UI, which is what makes K22 as bad as it is |
| **W2** | "Deactivated while on battery", said out loud | Nothing in `Screens/` reads `isEnabled` or `isManuallyDisabled`. The wallpaper vanishes and the panel says nothing. **Worse since #53:** the string that used to explain it was an orphan of the deleted menu and went with the rest, so no text anywhere names this behaviour now — on the one row in its settings section without an ⓘ |
| **W3** | Reload | Hotkey and `nifro://reload` only |
| **W4** | Random — jump to one now | The panel's `.random` rotation mode only affects the timer tick |
| **W5** | "Update Website to Current" | **Does not exist anywhere.** `AppState.swift:32-33` asserts it "moved into the website's own settings"; it did not. That comment is false, and this was the manual half of M2 |
| **W6** | Edit this website, from its name | The panel's name row is not a button. **The half-dead route is gone rather than left lying there:** `.showEditWebsiteDialog` and its observer were deleted, because the observer opened `AppState.currentWebsite` — the main display's website whatever screen the request came from — so re-pointing it at the panel would have opened the laptop's website in front of somebody looking at the monitor. Wiring this up is a per-display route, not a notification to re-declare |
| ~~**W7**~~ | ~~Move a website to another display~~ **Done**, by removing the question: a website is a member of a playlist and a display picks a playlist. | Only inside the website editor sheet. With K17, there is no path from the panel to put a website on a display |
| **W8** | Keyboard shortcuts, discoverable | `setShortcut(for:)` is gone; panel buttons carry `.help()` text only. `Shortcuts.swift:8,15-16` still argues defaults were shipped so the menu could display them |
| **W9** | The scaffolding the menu left behind | `SSMenu` and `WebsitesScreen`'s empty `.onChange` and `.onAppear` are deleted. What is left is `CallbackMenuItem.validateCallback`, never assigned, so `validateMenuItem` is a constant `true` |

W1 and W3 are the two that make the app feel unfinished from the panel; W5 is the one that lost a
feature rather than an entry point.

---

## 9. Known and not yet fixed (the K series)

| | What happens | What is known about it |
|---|---|---|
| **K1** | A YouTube video cannot be shrunk back into the YouTube page | The address is rewritten to the player-only page (its player answers error 153 when it is the document rather than a frame), so there is no page to navigate and Browsing Mode has nothing to click. **Signing in *is* possible:** change the address to `youtube.com/watch`, sign in, change it back — the cookie store is keyed on `website.id` and does not move with the address. Nobody is told this. The fix is a sentence of help text, not UI. Anything done here has to keep 153 away |
| **K6** | The help text is right in places and thin in others | Counted this time: **30 sites** — 23 `.explained(…)` and 7 `.help(…)` — across three surfaces totalling 2838 lines. The earlier "seven" was wrong by four times. Worth one pass that reads them as a set, but it is a 30-string job, not a small one |
| **K7** | Nothing anywhere handles HDR | **Parked, your call.** Confirmed by sweep: no API, entitlement or plist key touches it; the only matches are a colour-space option in the menu-bar sampler and the letters "HDR" inside one site's name. Needs a real HDR source and a measurement of what reaches the display before anything is worth designing |
| **K8** | A Bilibili entry has a generic icon where a YouTube entry has the video's own cover | YouTube's cover is derivable from the video id; Bilibili's is behind `api.bilibili.com` (`data.pic`). Affects the Websites list row icon only — `previewImageURL` has one caller. It would be the first time the app calls a site's API rather than loading a page |
| **K12** | Rebuilding a scene's content view during a crop pins that window above everything, for good | **Re-pointed: the second display is not needed and never was.** The overlay is a subview of `window.contentView`, and nothing guards `applyContent` against an active crop — so any rebuild detaches the overlay, which is the only thing that can call `onFinish`. The window keeps `.floating` and full opacity, and `beginCropSelection` refuses forever. **Re-checked after the framing work in `a332dae` and `53f110b`, which did not reach it:** `installContentView` now passes `nil` while `isFramingRegion`, and `applyOpacity` now leaves a framing window alone, but `content`'s `didSet` fires on assignment rather than on change — so the re-assignment still reaches `applyContent`, which still writes `window.contentView`, which still takes the overlay with it. "Interactive" has dropped off the symptom list: `rebuildScenes` reassigns `isInteractive` from Browsing Mode on the way past. `DisplayPanelModel.chooseRegion` calls `makeCurrent` immediately before `beginCropSelection`, and that write arrives on the *next* runloop turn — after the overlay is installed. For a website that already has a region, the case this feature exists for, the detach is certain |
| **K16** | Syncing a display eats the website that was on it, and leaves a copy behind | `mirrorAcrossSyncGroup` overwrites the follower's entry in place, so the page that display was showing is gone rather than set aside, with no way back. Measured on the maintainer's own list: six of eight entries were copies, two originals unrecoverable. The appended copies are bounded at one per follower display that started empty, and nothing ever removes them. Both halves are one decision: a mirrored entry is a *view* of the leader's, not a website in its own right, and should not be in the list |
| ~~**K17**~~ | ~~The website chooser on a display lists only that display's own websites, usually one~~ **Done.** A display picks a playlist and the chooser lists that playlist's members, so `effectiveDisplay == scene.display` is deleted along with the field it read. What the entry said the control was for — picking any website *and* moving it here — is answered differently: nothing is moved, because nothing belongs to a screen any more. | The filter is `effectiveDisplay == scene.display`, and a website gets a display by being chosen there — so the menu has one item and reads as broken. The deleted menu iterated the whole list and its comment called that deliberate, which makes this a regression rather than a design change. What the control is for is picking any website *and* moving it here See `docs/PLAYLIST-REFACTOR.md`, which argued it before the code. |
| **K18** | Sync correction can make the picture stutter | Every `playbackRate` change costs a visible hitch on WebKit (bug 208142). Needs a count of rate changes per minute on a real stream before any tuning; if it is high the answer is a wider `engage`, not a smaller `nudge` |
| **K20** | The panel takes snapshots twelve times a second, and keeps going when nobody can see it | **Your item.** Closing the panel does stop it — every dismissal route reaches `popoverDidClose`. Two things are wrong anyway. The loop sleeps **80 ms**, so it is 12.5 passes a second and one snapshot per display per pass, while the comment beside it says "a few a second" and the snapshot's own comment says "roughly once a second". And the stop condition is *closed*, not *visible*: a transient popover only self-closes on outside interaction, so it survives screen lock, display sleep, a Space switch and Mission Control, spinning the SwiftUI tree at 12.5 Hz the whole time. The comment on `startLiveRefresh` still claims nothing runs while nobody is looking. Fix is a slower cadence plus an occlusion or lock check, and while there, a `Task.isCancelled` between scenes so a close mid-pass does not publish one more frame |
| **K21** | The panel preview shows the whole magnified page, not the framed region | `snapshot()` passes no `rect`, so it captures the web view's full bounds — and under a region `PageView` sets that frame to the magnified whole page and clips it. So the column shows the entire page shrunk to 260 points while the display shows one slice of it. `refreshMenuBarBandColor` already demonstrates the fix: set `configuration.rect` to the region intersected with `webView.bounds` |
| ~~**K22**~~ | ~~With the app disabled, the panel's power buttons read "on" and turn displays off~~ **Done.** The column and its power button ask `isSwitchedOff`, so a column cannot read "on" while the app is disabled and pressing it cannot write "off" onto a display the user was switching on. Switching one on while the app is off records the setting and leaves the screen dark, which is what `setDisplayEnabled` already promised. | The column reads `!scene.isDisabledForDisplay` and never consults `AppState.isEnabled`. Unplug with "deactivate while on battery" on: every wallpaper goes, each column still draws as showing, and pressing the power button passes `false` and switches that display **off**. With W1 missing there is then no way to turn the app back on from the panel |
| **K23** | The website chooser does not wake a switched-off display; the arrows two rows above it do | `step()` re-enables first and has a comment explaining why. `show()` is a bare `makeCurrent` with no such guard, so picking a website on a switched-off display changes the title and leaves the screen blank. Two sibling controls in one column disagree about what picking a website means |
| ~~**K24**~~ | ~~Rotation arrows can be lit and inert~~ **Done.** `canRotate` is `eligible(in:).count > 1` — the same expression the arrows step through, off the same resolved playlist, rather than a second count that ignored the schedule. | `canRotate` counts websites by display; rotation walks `eligible(for:)`, which is that set intersected with the schedule. A display with two websites, one scheduled 08:00–18:00, lights both chevrons at 22:00 and does nothing when they are pressed. `RotationMode`'s own doc promises the arrows keep working while pinned |
| ~~**K25**~~ | ~~The daily update check writes a key nothing reads~~ **Done in #53.** The panel footer grows a download button only when there is something newer, and the settings sentence points at it. | U1 shipped in #18 with its passive surface in `Menus.swift`; #21 deleted that file and did not re-home the item. `latestKnownVersion` is now write-only — one network request every 24 h whose result is never shown — and `SettingsScreen.swift:78` still promises "Nifro mentions a newer version in the menu and nowhere else". Either a badge in the panel footer or delete the daily task; shipping neither is the worst of the three |
| **K26** | A page that fails to load reports nowhere anyone will look | The error sets the status item's tooltip and otherwise returns unless Browsing Mode is on. The panel never reads it, so a wallpaper URL that starts returning 500 shows as "No Website" with no reason given. The deleted menu put the error at the very top. **Re-pointed:** the store it would read is now per display and pruned with the scenes, so what is left is a column that can say so rather than a fact nobody kept |
| ~~**K27**~~ | ~~Browsing Mode orders a switched-off display's window back on screen~~ **Done, and the cause was not the loop.** `applyBrowsingMode` already read `isBrowsingMode(on:)` per scene; what put the window back was `orderBack`, which means "behind the others" for a window on screen and "show it" for one that is not, run from the unraised branch on a window `suspend()` had taken off screen. Guarded on `isVisible` there rather than on the assignment having moved — `rebuildScenes` writes the same property on every window, and the `bringBrowsingModeToFront` subscriber assigns it to itself on purpose so that branch runs again, so a guard on the value would have silently stopped that setting working. **Measured on two displays**, external switched off: off screen → on screen on the toggle before, off screen throughout after; browsing still raises its own display, `bringBrowsingModeToFront` still reaches `.floating`, switching browsing off still returns to desktop level. | `applyBrowsingMode` iterates *all* scenes including suspended ones, and `isInteractive.didSet` calls `makeKeyAndOrderFront` on every assignment, equal value or not. The window is transparent so the symptom is mild — except for a website with `allowsInteraction`, where it stops passing clicks through, and via the global shortcut it comes forward at `.floating` over a display the user switched off |
| **K28** | M2 stops recording after any suspend | `releaseWebView` builds a fresh web view and neither side re-subscribes `addressObserver`, so it stays bound to the web view that went away. After a disable/enable, a screen lock, a battery transition or a per-display off/on, that scene never records where its page moved itself to. `reload()` captures directly, which masks it for pages on a reload timer. One line |
| ~~**K29**~~ | ~~Four `WKUIDelegate` paths still use app-wide Browsing Mode~~ **Was already done**, and this entry had outlived it: all four paths take `isBrowsingMode(on: scene?.display)`. | `createWebViewWith` and the confirm, prompt and open panels read `isBrowsingMode`, which means "any display at all"; the two navigation paths in the same file were converted to the per-display form and these were left. With Browsing Mode on the laptop, a `window.open()` on the monitor's wallpaper is honoured and replaces a page nobody was interacting with |
| **K30** | The thumbnail cache is unswept and unbudgeted | `DiskBudget` sweeps the two WebKit roots on a 100 MB budget every six hours. `websiteThumbnailCache` is in neither root: one file per key under `~/Library/Caches/Nifro/`, no count cap, no size cap, no age sweep, and the only removal is the "Clear all website data" button. The key is the URL, so editing an address or deleting a website orphans its file permanently — `removeOrphanedStores` keeps by website *ID* and reaches only the WebKit stores, so nothing collects a thumbnail, ever. Bounded by distinct URLs ever in the list, so not runaway — but invisible to the budget that exists. Two lines: add the directory to `sweptRoots`, or reuse the orphan sweep against the thumbnail keys. **The on-disk format is a separate question and closes none of this.** A cheaper encoding makes each file smaller and a directory with no cap is still uncapped; it does not shrink what is already there either, because `IconView.fetchIcons` returns on a cache hit and a hit is served from disk, so a file written once is never rewritten and a change of format leaves the old files beside the new ones indefinitely |
| ~~**K31**~~ | ~~Two entries with the same URL on two displays overwrite each other's page position~~ **Done.** Keyed by `Website.ID` now, and the URL→key route is deleted rather than left unused, so no path can produce an address-shaped key again. The saved positions dropped once, as this entry accepted. **What it also cost, which this entry did not foresee:** the old key asked each kind whether `?panel=2` is a different page, and an `id` cannot be asked that — so a page reached by clicking a link in Browsing Mode now shares the entry's record instead of getting its own, and the last page scrolled is the one restored. Bounded and self-correcting, but it is a behaviour change and not only a re-key. The records of a deleted website are swept now too, beside the data stores and off the same list; nothing but the clear-everything button removed them before. | Was D7. Per-page records (`scrollPosition_`, `lastAddress_`, `zoomLevel_`) are keyed by URL while data stores are keyed by `website.id`. **Sync groups make this the normal configuration, not a corner:** every group mints one entry per follower display carrying the leader's URL, so ≥2 entries with different ids and the same URL share one set of records. Fix is to re-key to `website.id`, at the cost of dropping saved positions once |
| ~~**K32**~~ | ~~The UI still tells people to use a menu that no longer exists~~ **Done**, across #40 and #53. Counted again on `112e9a2`: the four catalogue strings still containing "menu" all name the menu bar *icon*, which exists. | **Six, counted rather than estimated:** the welcome screen's "click its icon and choose Add Website…" and "in the same menu", the region setting's "Choose Region… in the Nifro menu" (the panel calls it Crop), the sound setting's "the same setting as Sound in the Nifro menu", the update setting's "in the menu", and the hidden-icon setting's "if you need to access the Nifro menu…". The seventh this row used to claim, in the catalogue, is not there. **The rectangle is gone too:** the region help describes moving and zooming the wallpaper, which is L0's model and the right one |
| **K33** | The menu-bar band samples a strip up to a scale factor away from where the page was laid out | The window is deliberately `pageFrame.height + 1` while `pageLayoutSize` is `pageFrame.height`. `PageView` derives from live `bounds`; `topStripOfWallpaper` derives from `pageLayoutSize`. Same class of off-by-a-point disagreement K2 was, on the one surface with no test |
| ~~**K34**~~ | ~~Moving the pointer while holding the interact key strands the display you started on~~ **Was already done**, and this entry had outlived it — including the line below saying it still reproduces. `HoldToInteract` stores the scene at `begin` and `end` uses that one. | `HoldToInteract.begin` switches Browsing Mode on for `actingScene.display` and `end` switches it off for `actingScene.display`, each asked at the moment it runs. Let go over the other screen and the second display is switched off — it was never on — while the first stays interactive with nothing holding it, and only the toggle shortcut gets it back. The display has to be remembered at `begin`, not asked for again at `end`. **A branch of its own is on this; it still reproduces in this tree, so it is written here rather than assumed gone** |
| **K35** | Two full-screen wallpapers can stack on one screen while the displays are being reconfigured | `Display.main` is a failable init over `CGDisplayCreateUUIDFromDisplayID`, which comes back `nil` for the same tens of milliseconds `Display.underMouse` already documents. Inside that window an unpinned website has `effectiveDisplay == nil` while `isShowable` still says yes — `(display ?? .main)?.isConnected != false` is true when the whole chain is `nil` — so `displaysInUse` can hold `nil` *and* a real display at once. `rebuildScenes` builds a scene for each, and both resolve their screen through `Display.mainScreen`, so one screen carries two wallpaper windows, two menu bar bands and two sets of timers. It heals itself at the next `NSScreen.publisher` event. **Reasoned, never forced:** the window is too short to hit by hand, which is also why the cost of being wrong about it is low |
| ~~**K36**~~ | ~~One display's failed load is erased by another display's routine reload~~ **Done.** The store is keyed by display and pruned with the scenes, and the status item tooltip has one writer instead of three, so a load finishing on one display can neither erase nor overwrite another display's failure. What the icon says is still "any, not which" — that is K26. | `AppState.webViewError` is a single app-wide slot written per display. `load()` sets it to `nil` for whichever scene is loading, so a reload timer on the monitor throws away the record of the laptop's page having started returning 500. The status item's tooltip is the same slot from the other end: `report` writes the error onto it, and the next scene to finish a load writes its own website's tooltip over the top. Neither says which display it means. K26 is that nobody sees the error at all; this is that there is only one of it to see |
| **K37** | Per-display settings are never forgotten for a display that is gone for good | `rotationModes`, `rotationIntervals`, `disabledDisplays` and `currentWebsites` are keyed by `Display.settingsKey`, a per-display UUID, and nothing removes an entry. Correct for a monitor that is unplugged and comes back, which is the case the dictionaries were chosen for; there is no way at all to forget one that was sold. One small entry per display ever attached, invisible everywhere, so this is tidiness rather than a defect — worth a line so it is not rediscovered as a leak. `browsingDisplays` is the exception: `Events.swift` empties it wholesale |
| **K38** | Every timed reload starts a new WebContent process | A timed reload goes `reload()` → `loadBySwapping` → `createWebView()`, which builds a fresh `WKWebViewConfiguration`, every user script, **and a new `WKWebsiteDataStore(forIdentifier:)`** — a new renderer and a new network session each time, with the previous one thrown away. The request also carries `.reloadIgnoringLocalCacheData`, so every subresource is fetched cold. A 15-minute entry on two displays is roughly **192 process launches a day**. The fix is to call `reloadFromOrigin()` in place when the replacement URL equals the loaded one, which is the timed-reload path and not the switch-website path. **What it gives up, on that path only:** swap loading's failure isolation — a reload that fails because the Mac woke before the network did would show an error page instead of silently keeping the last good one. Measure before doing it: `powermetrics --samplers tasks` filtered to `com.apple.WebKit.WebContent`, two displays at a 15-minute interval for an hour, against a build using `reloadFromOrigin()`, plus `pgrep -c WebContent` either side of a reload |
| **K39** | The Settings-wide reload interval does nothing for almost every website | `Website.effectiveReloadInterval` is `reloadInterval ?? Defaults[.reloadInterval]`, and the compiler says the right side is never used. Both operands are `Double?`, so the optional overload should apply — but `Defaults[.reloadInterval]` goes through the package's generic subscript, and that drives resolution to `T ?? T` with `T == Double?`, where the left side is non-optional and the default is dead. **Measured, not read:** with the right side replaced by a plain `Double?` literal the warning goes away; against the subscript it does not. So a website with no interval of its own answers `nil`, `resetTimer()` returns at its `let reloadInterval =` guard, and no timer is armed. The setting is drawn, saved, and reaches nothing. Fix is an `if let` rather than a `??`, which is also what stops the next `Defaults` default being swallowed the same way |


**One shape behind six of these.** K22, K26, K27, K29, K34 and K36 were written as six unrelated
reports and were one: a fact that is true of *one display* kept in a slot with room for one answer,
or asked of the app where the per-display question already existed. That is why fixing them one at a
time kept working and kept leaving siblings behind — the per-display readers for Browsing Mode landed
in `WebViewController` and `HoldToInteract` while the panel's power button and the load error were
still app-wide, and two of the entries above had outlived their own fix without anybody noticing.
Five are closed; K26 is the one left, and it is a surface rather than a store. When the next one of
this shape arrives, look for the slot rather than the symptom — the guardrails are in `ScopeTests`
and `SwitchedOffTests`.

---

## 10. Engineering (the E series)

| | Item | Status |
|---|---|---|
| **E21** | `nifro://` is registered to stale copies of the app | **Test URL commands with `open -a <path> "nifro:reload"`, never plain `open "nifro:reload"`.** LaunchServices holds the scheme against every build ever made on this machine, `~/.Trash` and derived data included. Nothing in the repo causes it and nothing in the repo can fix it. The plain form once drove a three-week-old build for an afternoon |
| **E22** | Move localization onto Vorssaint's mechanism | **New, and a rework rather than a bug.** Nifro today: `Localizable.xcstrings`, 244 keys, 2 languages (English is the untranslated source), an `AppleLanguages` write and a **mandatory relaunch**, with a CI script gating completeness. Vorssaint: strings are Swift — a `struct Strings` of 892 fields with one `static let` per language across 13 languages, so a missing field is a compile error and there is no CI gate; `L10n: ObservableObject` publishes the choice and views re-render **with no relaunch**. The delta for Nifro is five steps, and step 3 is the whole cost: (1) replace the catalogue with `struct Strings` + one value per language; (2) add `L10n` with a `systemDefault` mapping and literal `displayName`s; (3) **rewrite 244 literals across ~30 files as `l10n.s.field`**, and make the AppKit surfaces — `DisplayPanel`, `PanelControls`, `Actions` — rebuild on change instead of relying on `AppleLanguages`; (4) delete the relaunch dialog; (5) delete the CI gate, the compiler replaces it. **What it gives up:** `AppleLanguages` localizes third-party package strings for free (`LaunchAtLogin.Toggle`); the Swift-struct scheme does not reach them. Keep a small gate for those |
| **E23** | Carrying a user's settings across an upgrade | **New.** There is no mechanism for it. What exists is three unrelated things that each cover one case: `rotationInterval(stored:legacySeconds:)` reads an old key when the new one is absent, `@DecodableDefault` fills in a field added to `Website`, and `SS_hasLaunched` is a one-shot flag for the welcome screen. Nothing records which version last ran, and there is no place a one-time upgrade step could be hung. It has not bitten anybody yet because nobody is upgrading from anything — which is also why the shape of it is still free to choose. Changing a shipped default is the case that shows the gap most clearly, and section 12 is not where this belongs: it is worth doing, before the first release makes every choice permanent. |
| **E24** | Websites become playlists | **New, and the largest change planned.** A website stops belonging to a display; a display picks a playlist. The design is written before the code in `docs/PLAYLIST-REFACTOR.md`, with what it dissolves (K17, K24, W7) counted against what it leaves alone (fourteen entries, all of them web view, window or cache problems). It also promotes K31 from a corner back to the normal case, because duplicating a playlist deep-copies its websites and two copies share a URL — so re-keying `PerPageDefaults` is a prerequisite rather than a cleanup |
| **E24** | Five lint rules that have never run | **The same shape as the periphery configuration #58 fixed.** `.swiftlint.yml` declares five `analyzer_rules` — `capture_variable`, `typesafe_array_init`, `unneeded_synthesized_initializer`, `unused_declaration`, `unused_import`. Analyzer rules only execute under `swiftlint analyze`, which needs a compiler log; the Xcode build phase and `ci.yml` both run `swiftlint lint`. **So all five have been inert since they were written.** `unused_import` would have named both imports deleted by hand in #58. Wiring it up costs an `xcodebuild ... | tee`, a `--compiler-log-path` run and a second lint job's worth of CI minutes, against five rules of unmeasured value — but a rule that cannot fire reads as though it has already checked. Either run them or delete the block; declaring them and not running them is the worst of the three |

**A trap, not an item:** adding a field to `Website` is a data-loss change unless the field can decode
from a payload that predates it. The list is one `Defaults` value, so one record that will not decode
takes every website with it, and `Defaults` answers a failed decode with the key's default — an empty
array. The user sees a fresh install with the file on disk still holding everything.

`@DecodableDefault` reads as if it covers this and does not on its own. What covers it is one overload
of `KeyedDecodingContainer.decode(_:forKey:)` in `Extensions.swift` routing the wrapper to
`decodeIfPresent`; without it the synthesised `init(from:)` throws `keyNotFound` before the wrapper
runs at all. That extension was deleted once, while it happened to have no members, and the gap sat
unnoticed until the next field was added — because a field only meets an absent key in records written
*before* it existed, so the four already using the wrapper never proved anything about it.
`WebsiteMigrationTests` now asserts the overload as well as the wrapper: being wrapped and surviving an
absent key are two facts that must agree, and nothing else requires them to.

**A trap, not an item:** a fourth kind of per-page record must be a case of `PerPageDefaults` — that
is what builds the key, and the sweep is `allCases`.

---

## 11. Signing and distribution

- **Signing** is a stable self-signed certificate, `Nifro Signing`. The stability is the point: it
  keeps the designated requirement fixed, and the security-scoped bookmarks holding local-file
  wallpapers are tied to it. Ad-hoc changes identity every build and breaks them.
- **Notarization** once there is a paid account. Nifro is a sandboxed GUI app and its users are not in
  the habit of typing `xattr`.
- **Releasing** is a tag triggering Actions, one thin dmg per architecture. The cask lives in
  `Casks/` and CI writes it back. Livecheck is on.
- **One workflow, two paths**, chosen by whether `secrets.MACOS_CERTIFICATE_P12` exists. Buying an
  account later costs six secrets plus deleting the cask's `postflight` block, and not one line of
  YAML changes. Full manual in `docs/RELEASE.md`.

Without an account, a double-clicked dmg is **blocked outright** — "Move to Trash / Cancel" — while
brew is clean, which is why the README's install section leads with brew.

**Two things about the tap, both deliberate.** Installing means naming the tap URL, and the shorthand
would need a repository literally called `homebrew-tap`. Worth doing for bandwidth rather than for the
shorthand: tapping clones this repository, all 6 MB, onto every user's machine and refetches it on
every `brew update`. Do it when that is somebody else's bandwidth. Plain `brew install --cask nifro`
means Homebrew's own cask repository, which has a notability threshold — a milestone to notice rather
than a task to schedule. **This section has drifted from the README twice** — it used to say "section 8", from a numbering two rewrites ago: the install now also needs
`brew trust`, and `Casks/nifro.rb:1` says the cask is "for use from PathGao/homebrew-tap" while this
section says it lives here. Fix both when the tap question is next opened.

**Release immutability is off**, and the reason it was off has expired: release assets are now named
without a version at publish time, precisely so `/releases/latest/download/…` is stable, and nothing
is renamed after publishing any more. Turn it on.

| | Item | Notes |
|---|---|---|
| **U2** | Sparkle | Not now. It needs an appcast feed and an EdDSA key pair — a second signing identity for the life of the app — and a sandboxed app cannot replace itself without the installer XPC service. **The feed URL is permanent from the first version that ships with it.** Renaming this repository is free today and stops being free that day |
| **U3** | `auto_updates true` in the cask | Mandatory the moment U2 lands, and meaningless before it: without it `brew upgrade` and the app fight over one bundle |

U1 shipped and then lost its surface in the panel refactor — that is K25, not a U item.

---

## 12. Explicitly not doing (do not raise again)

| | Proposal | Why it was turned down |
|---|---|---|
| **X1** | Change web engine (Electron / Tauri / CEF) | WKWebView is a system process shared with Safari; anything else costs more. The problem is scheduling, not the engine |
| **X2** | Rewrite in pure SwiftUI | `NSWindow` plus AppKit where it matters is fast and correct |
| **X3** | Tuist / XcodeGen | `project.pbxproj` is nowhere near the size where conflicts hurt, and adding a file by hand is four lines |
| **X4** | A dependency injection framework, a plugin system | No second implementation, so nothing to base the abstraction on |
| **X5** | Use only the CLT as a type-checking gate | **Tried, failed**: KeyboardShortcuts uses `#Preview`, that macro plugin ships only with Xcode |
| **X7** | Camera / screen capture input | The entitlement is per process, so it permanently gives a process that renders arbitrary URLs around the clock access to the camera. The shorter this app's permission list, the easier it is to check. It **is** technically doable; difficulty is not the reason |
| **X8** | Render the page and hand it to `NSWorkspace.setDesktopImageURL` (was P6, and A2 in the old section 2) | Refused, not blocked: it ends the app. A wallpaper set this way is a picture — no clicks, no Browsing Mode, no logins — and refreshing it cross-fades the whole desktop. **And it needs the offscreen renderer, which cannot exist:** an offscreen window makes WebKit report `visibilityState: hidden`, so `requestAnimationFrame` never runs and canvas pages photograph blank. Overriding `document.hidden` in JS does not help. Every snapshot-as-wallpaper idea dies on that sentence |
| **X9** | Put the user's own Chrome window on the desktop layer | Refused. **No public API sets another process's window level** — SkyLight against a connection we do not own is yabai's route and needs part of SIP off. The buildable variant gives up the icon layer and moves the wallpaper's lifetime into an app we do not control: Cmd-Q ends it, an auto-update restarts it, and the entitlement list goes to full Accessibility with the sandbox off. Screencasting instead is worse — DRM video arrives black, frames are JPEG, and `--remote-debugging-port` hands the whole browser identity to any process on localhost. The motive, inherited logins, is already answered: WKWebView's store is persistent, so one sign-in through Browsing Mode holds |
| **X10** | Go opaque when the content fills the screen | The saving cannot be measured, and it needs a switch that turns the screen black on a page with a transparent background |
| **X11** | A configurable reload strategy | Nobody asked for it. A setting in search of a complaint |

---

## 13. Reviewed and deliberately left alone

What was ruled out is easier to lose than what was built, so these stay to stop the next round raising
them again.

| | Candidate | Why it stays |
|---|---|---|
| **R1–R3** | `SecurityScopedBookmarkManager`, `Cache` + `SimpleImageCache`, `WebsiteIconFetcher` | Few call sites each. Replacing any of them is an equivalent rewrite on a trust boundary, and no check would go red if it were done wrong. K30 is about a missing sweep, not about these classes |
| **R4** | `sites/index.json`, fetched from `main` when the gallery opens | An entry carries `css` and `javaScript`, and adding one is a merge rather than a release — so a bad entry reaches installed copies without a build. **The blast radius is one deliberate click wide:** `featured` comes from the compiled-in snapshot, and a fetched entry's code reaches a web view only when somebody presses Add. Kept, because entries arriving between releases is the point. **Review the site list as release-grade surface** |
| **R6** | `DesktopWindow.reducedRegion` | Read once, written by nothing. `periphery` cannot see that because the property is read. Kept because shrinking the window to part of the desktop is L1, and this is the shape it needs |
| **N1–N2** | Loop-to-regex rewrites, and changes whose only verification was "it type-checks" | No assertion could go red |
| **N3** | Two animation durations, 0.25 and 0.35 | One is an opacity transition, the other a content fade-in. They change for different reasons; merging them manufactures coupling |
| **N4** | Narrowing the visibility of `Website.InvertColors` | Tried twice, red twice |
| **N6** | A cross-fade when switching website | Both pages would have to be in the window at once, which is a second answer to what `contentView` holds — the ambiguity that cost a blank wallpaper before. Revisit only if the straight swap reads as abrupt |


### Private API: checked, no public replacement, kept

| Site | Why it stays |
|---|---|
| `WKWebView.drawsBackground` KVC | It is what makes a wallpaper transparent. **`underPageBackgroundColor` is not a replacement** — it paints the over-scroll area, not the view's backing, so do not swap it on the strength of the name. #45's guardrail allows this one key by name, with the condition for deleting the entry written beside it |
| 24 `WKMenuItemIdentifier*` strings | The symbols are in `WebKit.tbd` but no public header declares them, and `WKUIDelegate` has no supported way to identify a context menu item on macOS. Nothing links a private symbol, so there is no review risk; a rename only turns the filter into a no-op |
| `com.apple.screenIsLocked` / `Unlocked` | A sandboxed app cannot get the public lock notification. `NSWorkspace.screensDidSleepNotification` is **a different event**, not a quieter one. A rename stops the suspend; it does not crash |
| `com.apple.DownloadFileFinished` | The Dock bounce. Decoration |
| `EnvironmentValues().openWindow` / `openSettings` | macOS 15 has no supported way to open a SwiftUI `Window` scene from AppKit. **But this fails silently**: one SwiftUI update and the panel's Settings and Websites buttons do nothing, with no error. Capturing `@Environment(\.openWindow)` from a long-lived view would outlast it |

### Looks hand-rolled, is the correct answer

- **`NSWindow.Level.desktop` / `.desktopIcon`** — built from `CGWindowLevelForKey`, which is **public** CoreGraphics. Not a private window level.
- **`UpdateCheck.isNewer`** — `String.compare(options: .numeric)` calls `0.2` older than `0.2.0`. The hand-written comparison calls them equal, which is right.
- **`ScrollRestoration` not using `WKWebView.interactionState`** — that API **drives a navigation**, so a stale blob leaves a blank wallpaper with no way back. A scroll position that fails is safe.
- **`ScrollableTextView`** — SwiftUI on macOS **does not expose smart quote and dash substitution**, and a smart quote in the user's CSS or JavaScript breaks their code outright. That is the whole reason the wrapper exists.
- **`NSStatusItem` + `NSPopover` rather than `MenuBarExtra`** — `MenuBarExtra` exposes none of `isVisible`, `appearsDisabled`, `behavior`, `contentTintColor`, and has no layer to run the loading pulse on. Five capabilities for none.
- **`DisplayPanelModel.startLiveRefresh`'s 80 ms poll** — a live preview of a moving page, with no notification to subscribe to, cancelled when the popover closes. What was wrong there was decoding the list twice per frame, fixed in #57.

### Looks dead, is not

`NSItemProvider: @unchecked Sendable` (**deleting it fails the build** with a data-race error; a conformance-only extension has no member for an indexer to see referenced) · every `AppIntent` in `Intents.swift` and `WebsiteAppEntity`'s `@Property`s (discovered from bundle metadata — 14 of periphery's 15 raw findings) · `Shortcut.allNames` (three live call sites and a test; its doc comment is stale, the code is not) · `NSStatusBarButton.setShowingActivity` (a test asserts on it) · the downloads entitlement · `SecurityScopedBookmarks.swift` · `Display.serialize`/`deserialize` (`Defaults.Bridge` requirements, called by the package) · `Constants.playlistInterval` (a deliberate, dated migration shim) · `ActionTrampoline`, `CallbackMenuItem`, `addCallbackItem` (`SSWebView` builds the context menu from them).

### Two negative results

- **The site catalogue expresses less than the Add Website sheet, not more.** `SiteCatalog.Entry` decodes seven fields and `Entry.add()` applies five, all of which have controls; an entry cannot reach `allowsInteraction`, `display` or `startHour`/`endHour`. There is nothing hidden down that path.
- **All nine keyboard shortcuts ship with a default binding** and a recorder row in Settings. Looked for one that shipped unbound; there is none.


---

## 14. Decided and done

One line each, kept only where the line stops a question being asked again.

- **L0** Region picking is direct manipulation. See the two traps in section 3.
- **K2** Region drift — gone with L0; there is no conversion left to be a point out.
- **K3** A page on its way says so on both surfaces: the panel's chooser pulses and its column goes inert for that display, the menu bar icon pulses for any. Read off `WallpaperScene.isLoading` rather than counted, so the first load of a session, the one after a suspend and the one after a display is switched back on all report like every other — which is what the old entry said only the swap path did.
- **K5** Language picker shipped: `AppleLanguages` plus a relaunch prompt. Superseded by E22, which changes the mechanism rather than the feature.
- **K9** A catalogue entry with a `zoom` no longer costs the whole gallery: both spellings decode, and the fetch skips a bad entry instead of dropping the list. The skip half has no test — it is `private`.
- **K10** Browsing Mode is replayed by `isEnabled.didSet`. **K11** Page zoom is restored on the web view being handed the page, on both arrival paths.
- **K13 / K14 / D5** A display that goes away loses its wallpaper; a display plugged in gets a page, because `NSScreen.publisher` now calls `applyWebsiteChanges()` rather than `rebuildScenes()`.
- **K15** `.canJoinAllSpaces` is set in `DesktopWindow.init`. **Unverified on hardware:** switch Mission Control desktop with the app running.
- **K19** First run is curated in the entries' own YAML: `featured` is a rank rather than a flag, floor796 is 1 and Svalbard 2, and the Nth display gets the Nth site. It still installs all eight featured entries; that half was never the complaint, and the list is what a new user edits.
- **D3** `croppingSceneDisplay` and its `?? primaryScene` fallback are gone; the crop holds a weak scene.
- **D9 / D10** Rotation is per display and scenes are handed their website in `init`. Both are covered by `swift test`, which is why neither needs two displays any more.
- **D11** `layOutContent` derives from `bounds`. The original claim was reasoned from one file and did not survive reading the callers.
- **E16** Universal binary: not doing. One thin build per architecture, and the workflow says so.
- **E17** Per-page defaults do not grow without bound; measured, not reasoned.
- **E18** The sweep cannot be forgotten any more — see the trap under section 10.
- **E19** The first page of the session is loaded by an explicit `reloadEverything()` in `setUpEvents`, in front of the content-rules subscription rather than behind it. The entry that stood here argued the old ordering was deliberate and that the comment on the subscription was the only guard. Both were false: with a rule list set, the launch load waited out a `URLSession` fetch and a rule-list compile, and a duplicate load from `isEnabled.didSet` was hiding it.
- **E20** `nifro://reload`, `nifro:reload` and `nifro:///reload` are all accepted; the extraction is a pure function with the three spellings pinned.
- **U1** The check ships, daily and switchable. Its surface does not — K25.
- **R5** `Extensions.swift` was split; four non-extension types moved out. Nothing in it was dead, and `periphery` disproved the reading-based claim that said otherwise.
- **N5** `RenderingMode` is gone: two cases computed from one `Bool`.
