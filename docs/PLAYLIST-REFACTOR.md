# Planned: websites become playlists

**Status: not built. This is the design, argued before the code, so the decisions in it can be
disagreed with while that is still cheap.**

## 1. The one change

A website stops belonging to a display. A display picks what to show.

```
today                                    after
┌─────────────────────────┐              ┌──────────────────────────────┐
│ Website                 │              │ Playlist                     │
│   display: Display?  ───┼── ownership   │   websites: [Website]        │
│   isCurrent: Bool       │   lives on    │   boundDisplay: Binding?     │
└─────────────────────────┘   the site    └──────────────────────────────┘
                                                    ▲
content claims the screen                 Display ──┘ picks a playlist
                                          the screen claims the content
```

Everything below follows from that one inversion, and every risk in it is a place where the old
direction is still assumed.

The inversion is not cosmetic. `WebsitesController.displaysInUse` — the list `rebuildScenes` reads to
decide which displays get a scene at all — is derived from the websites' `display` fields. Its own
comment says so:

> `displaysInUse` is read off the websites, so a display nothing names has no wallpaper.

That is also why `firstLaunchPlacements` pins the Nth featured site to the Nth display: not as
curation, but because otherwise the second screen is named by nothing and gets no wallpaper. The
symptom users see — a second display whose website chooser has exactly one item — is a consequence of
that mechanism, not of a filter written wrong.

## 2. What it dissolves, and what it does not

Counted against the K series rather than asserted.

| | Entry | After |
|---|---|---|
| **K17** | The chooser on a display lists only that display's own websites | Gone. The chooser lists the selected playlist's members; `effectiveDisplay == scene.display` is deleted |
| **K24** | Rotation arrows can be lit and inert | Gone **only if** `canRotate` and `eligible(for:)` are made one expression. They are two derivations of one question today, which is the defect; the refactor is the chance to collapse them, not a cure on its own |
| **W7** | Move a website to another display | Gone. A website moves between playlists |
| **K23** | The chooser does not wake a switched-off display; the arrows do | Not dissolved by the model. `show()` and `step()` disagree today and both are rewritten here, so it is cheap to fix in passing — but it is adjacent work, not a consequence |

Fourteen entries are untouched, and it is worth writing down that they are: K1, K6, K7, K8, K12,
K18, K20, K21, K26, K28, K30, K33, K35, K38. All of them are web view, window ordering, rendering or
cache problems. None of them has anything to do with which website is on which screen. A refactor
that dissolves three structural defects and leaves fourteen local ones is a good trade, but not
because of the count.

**K16 and K31 are stale, in different ways.** Both are written against `mirrorAcrossSyncGroup`, and
sync groups were pulled — see `docs/shelved/MULTI-DISPLAY-SYNC.md` and V3. K16 cannot happen at all
today. K31's premise ("sync groups make this the normal configuration") is gone with them, which
demoted it to a corner case — and then § 6 below promotes it back, for a new reason.

## 3. The model

```swift
struct Playlist: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var websites: [Website]            // bodies, not references — see D1
    var boundDisplay: DisplayBinding?  // nil is "none", the default — see D3
}

/// A binding has to be readable while the display is not attached, so the name is a snapshot.
struct DisplayBinding: Codable, Hashable {
    let id: UUID
    let nameWhenBound: String
}
```

Three pieces of per-display state, each answering one question:

```
[displayKey: Playlist.ID]   which playlist this display is showing     (chosen in the panel)
[displayKey: Website.ID]    where in that playlist it is               (replaces Website.isCurrent)
Playlist.boundDisplay       which displays may offer this playlist     (filters the panel's picker)
```

`Website` loses two fields: `display` and `isCurrent`.

### D1 — a playlist holds websites, not references to them

The use case that decides this: duplicate the default playlist twice, bind one copy to each display,
and give the same site a different crop on each screen. A crop is `Website.zoom`, stored on the
website itself, along with `css`, `javaScript`, `invertColors2`, `usePrintStyles`, `audio` and
`reloadInterval`. Under a reference model every copy shares all of them, which is the opposite of
what the feature is for.

So duplication is a deep copy: new `Website` values with new ids. That also settles what "handle the
rename properly" means — nothing special is needed, because the copy's members are independent
objects from the moment they exist.

### D2 — the cursor is keyed by display

`Website.isCurrent` is a `Bool` on the website, and `currentFlags(displays:wasCurrent:makingCurrent:)`
keeps exactly one of them true per display. Its first argument is `all.map(\.effectiveDisplay)` — the
field being deleted. The mechanism does not survive the change and is not worth patching: "which
website is up on which display" becomes a dictionary keyed by `Display.settingsKey`, where uniqueness
is a property of the dictionary rather than of a sweep over a list.

This is the one change in the set that can compile, pass every test, and still be wrong. A
per-display fact kept in a slot with room for one answer is the shape behind six K entries already;
see `ScopeTests` for the two guardrails that exist because of it.

### D3 — a binding filters the picker and does nothing else

A playlist bound to a display appears only in that display's picker. It is not applied, not
preferred, and not consulted at runtime. Two playlists bound to the same display do not conflict —
both appear in that picker and the user chooses. Dragging the playlist list to reorder it is
therefore ordering, not precedence.

This is what makes the unplugged case answer itself: a picker exists only for an attached display, so
a playlist bound to a display that is gone appears in no picker. There is nothing to fall back to and
no new default to choose. The binding remains visible and removable in the management page, which is
why `DisplayBinding` carries `nameWhenBound` — `Display.localizedName` resolves through
`NSScreen.screens` and returns the hardcoded `<Unknown name>` for a display that is not attached.

### D4 — a copy starts unbound

Duplicating a bound playlist would otherwise put a second, identical entry in that display's picker
without the user having asked for one. The copy's binding starts at "none", which is also the shape
of the use case: duplicate the default twice, then bind each.

### D5 — the panel gains a picker rather than repurposing one

The existing chooser stays, listing websites; a playlist picker is added above it. The column grows
by 37pt — one 28pt control and one 9pt gap — which two side-by-side columns pay once between them,
not each. There is room: the popover sits well under the height of the display it opens on.

`DisplayPanel` already argues for the grouping this pressures. Mute and power sit *on* the picture
deliberately, so that what is under the picture reads as one thing:

> these two say what this display is *doing*, and the row below says what to show on it. Keeping
> them apart stops the column reading as five controls in a stack with no grouping.

Under the picture there will now be four rows, three of which say "what to show" at different
grains. That is a layout problem to solve, not a reason to merge the two pickers back into one.

## 4. The six sites

| | Today | After |
|---|---|---|
| `displaysInUse` | Distinct `effectiveDisplay` over the websites; a display nothing names gets no scene | Every attached display gets a scene. The direction inverts here and nowhere else |
| `currentFlags(displays:…)` | Keeps one `isCurrent` true per display | Deleted. Write `[displayKey: Website.ID]` |
| `firstLaunchPlacements` | Nth featured site pinned to Nth display, to make the second screen exist | Deleted. Everything installs into one default playlist |
| `eligible(for:)` / `canRotate` | Two derivations: `onDisplay.count > 1` against the set intersected with the schedule | One expression: the selected playlist's members intersected with the schedule |
| `DisplayPanelModel.column(for:)` | `websites.filter { $0.effectiveDisplay == scene.display }` | The selected playlist's members |
| `WebsiteDisplaySetting` | A display picker in the website editor | Deleted |

## 5. Invariants, and what holds them

| | Invariant | Symptom when broken | Guardrail |
|---|---|---|---|
| **I1** | "What is showing where" has one home | Two answers disagree, silently | `ScopeTests`: no `isCurrent`-shaped field on `Website`; one writer for the cursor |
| **I2** | "Can it rotate" and "rotate to what" come from one expression | K24 returns: arrows lit, pressing does nothing | Source shape: `canRotate`'s implementation must name `eligible` |
| **I3** | A binding's display name is a snapshot | `<Unknown name>` reaches the UI once a display is unplugged | `Display.localizedName` must not appear on the playlist drawing path |

I1 and I2 are the two that make the refactor worth doing rather than merely different. Both are
cheap to pin and expensive to discover.

## 6. Order

```
PR1   Rename today's Playlist.swift                         independent
      It is rotation and scheduling, not a user-facing list. The word has to be free
      before anything else can use it. Also renames playlistTimer, playlistMinutes,
      resetPlaylistTimer — 33 identifier uses.

PR2   Introduce Playlist, migrate the existing list          independent
      Everything into one default playlist. Website.display still readable, no longer written.

PR2.5 Re-key PerPageDefaults from URL to website.id          before PR6
      Scroll position, last address and page zoom are keyed by URL. Two copies of one
      website share a URL, so duplication makes K31 the normal configuration — the exact
      thing sync groups used to do. Costs the saved positions once.

PR3   Move the cursor off Website.isCurrent                  needs PR2
      This is I1. The only step that can be wrong while green.

PR4   Invert displaysInUse                                   needs PR2
      Attached displays get scenes. firstLaunchPlacements deleted.

PR5   Panel: add the playlist picker                         needs PR3, PR4
      Website chooser reads the selected playlist. canRotate reads eligible (I2).
      K17 and K24 close here.

PR6   Management page: list, drag, ⋮ menu, bind, duplicate   needs PR2.5
      Can run beside PR5.

PR7   Delete Website.display, WebsiteDisplaySetting,
      keepWallpaperWhenDisplayUnplugged                      last
```

PR1 and PR2 are the first two links of a chain; PR5 and PR6 can be opened in parallel once their
dependencies land.

## 7. Open

**Empty picker.** If every playlist is bound to one display, another display's picker has nothing in
it and that screen shows nothing. The cheap guard is to refuse a binding on the default playlist, so
every picker has at least one entry. Not decided.

**`keepWallpaperWhenDisplayUnplugged` has no owner after this.** Its meaning today — the wallpaper
follows its website's pinned display, or goes away with it — depends on a website being pinned.
Bindings only filter a picker, so nothing corresponds. Deleting it is the honest move; keeping it
would mean inventing a new behaviour ("the unplugged display's playlist temporarily takes over the
main one"), which is a feature and not part of this.

**A duplicate is logged out.** Data stores are keyed by `website.id`
(`WKWebsiteDataStore(forIdentifier:)`), so a deep copy gets a new, empty store. For the stated use
case that costs nothing, but it is what "duplicate" means here: the configuration is copied, the
session is not. Worth a sentence in the confirmation rather than a mechanism.

## 8. Migration

There is no upgrade mechanism at all — E23 says so, and says the shape of one is still free to
choose because nobody is upgrading from anything yet. This is the change that needs it.

The existing list is the first case to carry: websites with `display` set become members of a
playlist bound to that display; the rest become the default playlist. Per-display settings
(`rotationModes`, `rotationIntervals`, `disabledDisplays`) are keyed by display and stay that way —
they describe the screen, not the content.
