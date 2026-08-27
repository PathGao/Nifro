# The App's Visual Vocabulary

[简体中文](VISUAL-SYSTEM.zh-Hans.md)

> Written 2026-08-27 against `dead3a6` (v0.1.3). Every number below was produced by a command that is
> printed next to it, so it can be re-run rather than believed.

The panel and the settings windows do not look like one app, and no mechanism requires them to. This
document says how far apart they actually are, which of the differences are decisions and which are
accidents, and proposes the smallest thing that would make "somebody hardcoded a colour" fail CI
instead of waiting for an eye to catch it.

Nothing here has been implemented. Sections 5 and 6 are a plan, and section 7 lists what needs your
decision before any of it is worth starting.

---

## 1. How many hardcoded visual literals there are

```sh
# Per file, per category. Run from the repo root.
for f in $(git ls-files 'Nifro/*.swift' | grep -v generated); do
  r=$(grep -cE "(cornerRadius|xRadius|yRadius): *[0-9]" $f)
  o=$(grep -cE "\.(system|systemFont|monospacedSystemFont|monospacedDigitSystemFont)\((of)?[Ss]ize: *[1-9]" $f)
  s=$(grep -cE "spacing: *[1-9]" $f)
  p=$(grep -cE "\.padding\((\.[a-zA-Z]+, *)?[1-9]" $f)
  w=$(grep -cE "\.frame\(.*(width|height): *[1-9]" $f)
  c=$(grep -cE "Color\(red:|(NS)?Color\.(white|black)|withAlphaComponent\(|\.opacity\(0?\.[0-9]" $f)
  [ $((r+o+s+p+w+c)) -gt 0 ] && printf "%-42s %2s %2s %2s %2s %2s %2s = %s\n" $f $r $o $s $p $w $c $((r+o+s+p+w+c))
done
```

| File | radius | font pt | spacing | padding | frame | colour | total |
|---|---:|---:|---:|---:|---:|---:|---:|
| `Screens/DisplayPanel.swift` | 9 | 1 | 8 | 7 | 5 | 1 | **31** |
| `Screens/SiteGalleryScreen.swift` | 0 | 0 | 5 | 4 | 2 | 0 | 11 |
| `Screens/PanelControls.swift` | 2 | 3 | 1 | 0 | 1 | 1 | 8 |
| `Screens/WebsitesScreen.swift` | 1 | 0 | 2 | 1 | 3 | 1 | 8 |
| `Zoom/CropSelectionView.swift` | 1 | 2 | 0 | 0 | 0 | 5 | 8 |
| `Screens/AddWebsiteScreen.swift` | 0 | 2 | 1 | 0 | 4 | 0 | 7 |
| `Screens/AboutSettings.swift` | 0 | 0 | 2 | 1 | 1 | 0 | 4 |
| `Screens/SettingsScreen.swift` | 0 | 0 | 2 | 0 | 1 | 0 | 3 |
| `Screens/SettingHelp.swift` | 0 | 0 | 1 | 0 | 1 | 0 | 2 |
| `Screens/IntervalField.swift` | 0 | 0 | 0 | 0 | 2 | 0 | 2 |
| `Support/ScrollableTextView.swift` | 0 | 0 | 0 | 0 | 1 | 0 | 1 |
| `Visibility/MenuBarBand.swift` | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| | | | | | | | **85** |

Two rows carry most of the argument. `DisplayPanel.swift` holds 31 of the 85 — more than a third of
the app's visual literals are in the one file that also holds the only named metrics. And
`MenuBarBand.swift` holds none: it takes its colour off the page, so it has nothing a design system
could give it. It is exempt on the strongest ground available, not by concession.

**Which values repeat.** Multiplicity is what turns a literal into a defect; a number used once is
just a number.

```sh
grep -rhoE --include='*.swift' "(cornerRadius|xRadius|yRadius): *[0-9]+" Nifro/Screens Nifro/Zoom |
  grep -oE "[0-9]+$" | sort -n | uniq -c
```

- **Corner radii: 5 (×4), 7 (×1), 8 (×4), 12 (×5)** — and `PanelMetrics.cornerRadius = 6`, a fifth
  radius with exactly one user. Five corner radii inside one popover.
- **Point sizes: 11 (×4), 12, 13 (×2), 22** — and `PanelMetrics` already names both 11 and 13.
- **Widths: 260 (×3), 44 (×3), 560 (×3), 500/56/70/22/16 (×2 each).** 260 is the panel column and is
  named nowhere.

---

## 2. The inconsistencies, by the three shapes

Against `WORKSPACE_GUIDE.md` § "缺陷的三个形状".

### ① The same expression, copied

- **`Font.system(size: 11, weight: .semibold)`** is `PanelMetrics.symbolFont`
  (`PanelControls.swift:25`) and is also written out character for character at
  `DisplayPanel.swift:256`. One is a copy of the other.
- **Size 13** is `PanelMetrics.font` (`PanelControls.swift:21`) and `.system(size: 13, weight:
  .medium)` at `PanelControls.swift:57` — the same size declared twice in the same file, differing
  only in weight.
- **The column width, 260**, at `DisplayPanel.swift:122`, `:139` and `:299`. Worse, `PanelMetrics
  .chooserWidth = 195` (`PanelControls.swift:32`) is documented as "three quarters of the picture
  above it" — that is `0.75 × 260`, a derivation recorded as prose instead of as code. Change the
  column width and the comment becomes a lie silently.
- **The on-state foreground, `AnyShapeStyle(.white)`**, at `PanelControls.swift:82`, `:131` and
  `DisplayPanel.swift:258`. `onTint` is named; the colour that goes on top of it is not.
- **Radius 12 ×3** (`DisplayPanel.swift:142,149,152`) and **radius 8 ×4** (`:285,292,300,302`) — in
  both cases fill, clip shape and stroke of one element, which must agree or the border misses the
  corner.

### ② A mechanism with members that never joined

- **`PanelMetrics` has six members and `PanelMetrics.` appears 16 times**, eight in each of the two
  panel files:

  ```sh
  grep -rc "PanelMetrics\." Nifro/Screens/*.swift   # DisplayPanel 8, PanelControls 8
  ```

  Against 39 visual literals in those same two files. The mechanism covers roughly a fifth of what
  it exists for.
- **The sync-link button (`DisplayPanel.swift:254-267`) redraws `PanelButton` by hand.** It sets its
  own font (line 256, the copy noted above), its own frame `22×20` where `PanelButton` uses `26×22`
  (`PanelControls.swift:58`), its own `cornerRadius: 5`, its own on-tint branch — and it reads no
  hover state at all, while both of its neighbours dip and light on hover. It is not a `PanelButton`
  because `PanelButton` wraps a `Button` and this needs a `Menu`; nothing else about it wanted to be
  different.
- **`PanelMetrics.cornerRadius = 6` has one user**, `PanelWideButton`. `PanelButton` — which sits in
  the same footer row, 10 points away (`DisplayPanel.swift:60`) — uses 5. The token existed and the
  sibling control did not join it.

### ③ Two independent answers to one question

- **The on-state colour's own rule is not applied consistently.** `PanelMetrics.onTint`'s comment
  (`PanelControls.swift:37-40`) states a real judgement: the system accent says *this is selected*,
  the icon's orange says *this is running*. Checked against every caller, one disagrees.
  `DisplayPanel.swift:319-321` passes `isOn: !column.isShowing`, so the power button lights orange
  **while that display's wallpaper is switched off**. Under the written rule that is backwards; under
  a different rule ("the button is toggled on") it is right. Both readings are defensible and only
  one is written down, which is the defect. The other four callers agree with the comment.
- **One hover state, two colour systems, and one only works in the dark.** Hovering a column draws a
  border in `Color.accentColor` (`DisplayPanel.swift:150`) and a fill of
  `Color.white.opacity(0.15)` (`:143`). The border follows the theme and the user's accent; the fill
  is fixed white, so over a light-appearance popover it is close to invisible, while the buttons
  inside the same column use `.quaternary` for the same purpose. Three answers to "what does hover
  look like", one of them appearance-dependent.
- **Five windows, five widths, decided independently.** 400 (`SettingsScreen.swift:19`), 480
  (`WebsitesScreen.swift:71`), 500 (`AddWebsiteScreen.swift:60`), 520×560
  (`AddWebsiteScreen.swift:494`), 560×560 (`SiteGalleryScreen.swift:47`). Nothing requires any two to
  agree. They may legitimately differ — see § 4 — but no one has ever decided that they do.
- **A stale comment about the boundary itself.** `DisplayPanelController.swift:8` says "The old menu
  is still there on a right-click, and stays until the panel carries everything it does."
  `AppState.swift:30` says "The menu is gone." `Menus.swift` was deleted in #21 and
  `sendAction(on: [.leftMouseUp, .rightMouseUp])` (`AppState.swift:24`) sends both buttons to the
  same handler. The first comment describes an app that no longer exists, and it is the one a reader
  reaches first when asking which surface owns what. (The scaffolding behind it is ROADMAP W9,
  which is now down to `CallbackMenuItem.validateCallback`; this entry is the comment, not the code.)

---

## 3. What is *not* wrong

Recorded so the next pass does not re-raise them.

- **`MenuBarBand`** has no visual literals and should never acquire any. Its one colour is sampled
  from the wallpaper.
- **The four `Form(.formStyle(.grouped))` screens** are right to use stock controls. They are
  ordinary windows about ordinary settings; stock controls are what follow the user's accent colour,
  Increase Contrast, Reduce Transparency and VoiceOver for free.
- **`CropSelectionView`'s black and white** are not brand colours that escaped the system. They are
  contrast decisions against an arbitrary web page, which is the one surface where a theme-aware
  colour would be the wrong answer.
- **The animation durations** — 0.12 (×2), 0.2, and the 0.2/0.82 spring. ROADMAP N3 already ruled
  that two durations changing for different reasons should not be merged; the same test applies
  here, and the press dips and the marquee reset fail it. Not tokens.
- **Repeated `spacing:` and `padding:` inside one view.** `VStack(spacing: 9)` twice in
  `DisplayColumn` is one layout expressed twice, not a shared vocabulary. § 5 deliberately leaves
  these unguarded and § 6 says what it would cost to change that.

---

## 4. Where the line between system and custom should be

The line that exists today is right in three places and undrawn in one.

| Surface | Should be | Why |
|---|---|---|
| Settings, Websites, Add Website, Site Gallery | **system** | Ordinary windows about ordinary settings. Stock controls are the only ones that follow accent colour, Increase Contrast, Reduce Transparency and VoiceOver without being asked |
| The display panel | **custom** | Argued already at `PanelControls.swift:6-9`: the control acts on a page the user cannot see, so the button has to be the whole of the feedback |
| `CropSelectionView` | **custom** | It sits over an arbitrary web page. Nothing system-drawn stays legible over unknown content |
| `MenuBarBand` | **neither** | Not a control. Its colour comes from the page |

**Where it is accidental rather than drawn:** inside the panel. Three of the panel's controls are
system `Menu`s wearing hand-drawn labels — the website chooser (`DisplayPanel.swift:344-380`), the
sync link (`:239-267`) — so the popup list is system-drawn inside a hand-drawn panel and the token
layer only ever reaches the label. That is a reasonable place to stop, and nothing says so, which
means the next control added has no rule to follow.

**The judgement that does exist is worth keeping.** `onTint`'s comment — accent means selected,
orange means running — is a genuine semantic distinction, not decoration, and it is the reason the
token layer below is *semantic* (`onTint`, `hoverFill`) rather than a palette of colour names. It
just needs to be enforced by something other than the person who remembers it. § 7 Q1 asks you to
settle the one caller that disagrees with it.

---

## 5. The proposal

Deliberately small. `PanelMetrics` is already the design-token layer; the problem is not that it is
missing but that it is named for one screen, lives beside the views it serves, and covers a fifth of
them. So this is a rename, a handful of additions each of which has at least two existing users, and
one shared modifier — not a new framework.

### 5.1 One file: `Nifro/Screens/Appearance.swift`

`PanelMetrics` moves here and becomes `Appearance`, keeping its documentation. It gets its own file
so that the lint rule in § 5.3 can exempt one stable path; leaving it in `PanelControls.swift` would
exempt `PanelButton` and `PanelWideButton` too, which is the hole this is meant to close.

```swift
enum Appearance {
	// Control chrome. Unchanged from PanelMetrics.
	static let controlFont = Font.system(size: 13)
	static let symbolFont = Font.system(size: 11, weight: .semibold)
	static let controlHeight = 28.0
	static let controlPadding = 15.0
	static let controlRadius = 6.0            // ← § 7 Q2: is the icon button's 5 meant to differ?
	static let iconButtonSize = CGSize(width: 26, height: 22)

	// The column.
	static let columnWidth = 260.0
	static let cardRadius = 12.0
	static let pictureRadius = 8.0
	static let chooserWidth = columnWidth * 0.75   // The existing comment, made true by construction.

	// State, named for what it means rather than what colour it is.
	static let onTint = Color(red: 234 / 255, green: 115 / 255, blue: 63 / 255)
	static let onForeground = AnyShapeStyle(.white)
	static let hoverFill = AnyShapeStyle(.quaternary)
	static let restFill = AnyShapeStyle(.quinary)
}
```

Fourteen names. Every one has at least two existing call sites today except `controlRadius`, which
has one and is the subject of Q2. Nothing is added for symmetry: there is no `windowWidth`, because
§ 3's N3 test says five windows sized for five different contents are five decisions, not one.

### 5.2 One modifier, three call sites

```swift
extension View {
	/// Paint a control the way the panel paints controls.
	func panelChrome(isOn: Bool, isHovering: Bool, rest: AnyShapeStyle = Appearance.restFill) -> some View
}
```

It sets foreground (`onForeground` / `.primary`), background (`onTint` / `hoverFill` / `rest`) and
the rounded shape. `PanelButton` passes `rest: AnyShapeStyle(.clear)`; `PanelWideButton` takes the
default; **the sync-link `Menu` label uses it too**, which is what folds the second icon button back
into the mechanism. After that the only thing separating an icon button from a pill is its frame and
padding, which stay at the call site because that is the real difference.

No protocol, no style registry, no `ButtonStyle` hierarchy. There is one panel.

### 5.3 The guardrail: three SwiftLint custom rules

SwiftLint is already pinned at 0.65.1 and already runs `--strict` in CI (`ci.yml:99`), so no new tool
and no new job. Added to `.swiftlint.yml`:

```yaml
custom_rules:
  hardcoded_corner_radius:
    included: 'Nifro/(Screens|Zoom|Visibility)/.*\.swift'
    excluded: 'Nifro/(Screens/Appearance|Zoom/CropSelectionView)\.swift'
    regex: '(cornerRadius|xRadius|yRadius): *[0-9]'
    message: 'Corner radii belong in Appearance. Name it there, or disable this line with the reason it is not shared.'

  hardcoded_font_size:
    included: 'Nifro/(Screens|Zoom|Visibility)/.*\.swift'
    excluded: 'Nifro/(Screens/Appearance|Zoom/CropSelectionView)\.swift'
    regex: '\.(system|systemFont|monospacedSystemFont|monospacedDigitSystemFont)\((of)?[Ss]ize: *[1-9]'
    message: 'Point sizes belong in Appearance.'

  hardcoded_ui_colour:
    included: 'Nifro/(Screens|Zoom|Visibility)/.*\.swift'
    excluded: 'Nifro/(Screens/Appearance|Zoom/CropSelectionView)\.swift'
    regex: 'Color\(red:|(NS)?Color\.(white|black)\b|AnyShapeStyle\(\.white\)'
    message: 'A literal colour follows neither the theme nor the user accent. Use Appearance, or a semantic style.'
```

**Why these regexes and not others.** Every one matches a *framework* symbol — SwiftUI's and
AppKit's own public parameter labels and initialisers. None matches a name anybody in this repo
chose. Renaming `PanelButton`, `isHovering` or `PanelMetrics` itself cannot turn any of them red,
which is the distinction `WORKSPACE_GUIDE.md` draws between 白红 and 真红. The `[1-9]` in the font
rule is not cosmetic: `NSFont.controlContentFont(ofSize: 0)` (`ScrollableTextView.swift:47`) is
AppKit's idiom for "the system default size", the opposite of a hardcoded size, and `[0-9]` would
red it.

**Measured, not predicted.** Both halves were run locally against a 0.65.1 that matches the CI pin:

```sh
swiftlint lint --quiet --config /path/to/probe.yml | grep -c 'warning:'
```

- The three rules fire **32 times** on `dead3a6`. Section 6 lists every one.
- Per-rule `excluded:` works: pointing it at `PanelControls.swift` drops the count 32 → 24, exactly
  that file's eight.
- `// swiftlint:disable:next hardcoded_corner_radius - <reason>` silences one line, and
  `superfluous_disable_command` — already enabled in `.swiftlint.yml` — reports the disable as a
  violation once the line under it stops violating. So an allowlist entry whose reason has expired
  fails, which is the property `WORKSPACE_GUIDE.md` asks allowlists to have and the reason this is a
  lint rule rather than a source-shape test.

**Why not a source-shape test in `Tests/`.** The `WORKSPACE_GUIDE.md` criterion is whether the
proposition is *unrunnable* or the code is merely *unreachable*. "No colour literal exists outside
`Appearance.swift`" is an absence claim over source text, so a shape test would be the right tool —
but SwiftLint already reads every file, already runs `--strict`, already has a per-line exemption
with an expiry check, and points at the offending column in the PR diff. A test would reimplement all
of that, and the `NifroLogic` package target compiles seven files and would have to reach outside
itself to read the rest. Use the tool that is already there.

### 5.4 What stays unguarded, and when to add it

`spacing:`, `.padding(…)` and `.frame(width:height:)` are not covered. Extending the rules to them
fires **45 more times** (measured the same way), and most of those are a local layout expressed once.
An allowlist of 45 entries reading "this is a layout number" is exactly the shape
`WORKSPACE_GUIDE.md` forbids. Add
them if and when a second panel exists and a spacing has to agree across the two — at that point the
number has a name to be given, and today it does not.

---

## 6. Migration, and the 32 violations

**There is no "warn first" phase.** CI already runs `swiftlint lint --strict`, so a custom rule at
default severity is red the moment it lands. The order below exists to bring the count to zero before
the rule is added, not to ease it in.

| Step | What | Verified by |
|---|---|---|
| 1 | `Appearance.swift`: move `PanelMetrics`, rename, add the eight names from § 5.1 | `git grep -c PanelMetrics` → 0; the app builds; `swift test` unchanged (the package target does not compile these files, so this step cannot break it) |
| 2 | `panelChrome`, and the sync-link button adopts it | The literal count in `DisplayPanel.swift` falls from 31 to ~20. Visible change: the sync button becomes 26×22 and gains a hover state |
| 3 | Q1 and Q2 in § 7 — decisions, not renames | Nothing to measure. Needs you |
| 4 | Add the three rules. Three violations remain and each takes a `disable:next` with its reason | `swiftlint lint --strict` exits 0. From here, a hardcoded literal is red on the pull request that writes it |

### The 32, each with its disposition

This is the list `WORKSPACE_GUIDE.md` requires: every first-run violation, argued, with nothing
swept into the allowlist unexamined.

**Fixed by step 1 — a token exists or is being added (19).**
`PanelControls.swift:21,25,41` become the token definitions themselves. `PanelControls.swift:57`
(size 13) and `DisplayPanel.swift:256` (size 11 semibold) are verbatim copies of tokens that already
exist. `PanelControls.swift:60,61` and `DisplayPanel.swift:261` are the radius-5 group, which
becomes `controlRadius` under Q2. `DisplayPanel.swift:142,149,152` become `cardRadius`;
`:285,292,300,302` become `pictureRadius`. `DisplayPanel.swift:327` (radius 7) becomes
`pictureRadius - 1` — it is a pill nested inside the 8-radius picture and 7 is that relationship,
written as a number. `PanelControls.swift:82,131` and `DisplayPanel.swift:258` become
`onForeground`.

**Fixed by step 3 — a decision, not a rename (1).**
`DisplayPanel.swift:143`, `Color.white.opacity(0.15)`. This is Q3: the hover fill that only works in
dark appearance. It should almost certainly become `hoverFill`, matching the buttons inside the same
column, but that changes how the panel looks and is your call.

**Exempted as a surface, with one reason (9).**
All of `CropSelectionView.swift` — `:152,157,170,171,174,175,190,191(×2)`. Its black scrim, white
outline and 22-point readout are contrast decisions against an arbitrary web page, the one surface in
the app where a theme-aware colour is the *wrong* answer. Nine identical per-line reasons would say
less than one file-level one, so the exemption is a path in `excluded:` with the reason written above
it in the YAML. If you would rather see nine `disable:next` lines, say so — it is a real choice, not
an oversight.

**Permanently allowed, one line each (3).**
- `AddWebsiteScreen.swift:460` and `:481`, `monospacedSystemFont(ofSize: 11)`. These are the CSS and
  JavaScript editors. A code editor's font is a code editor's font; it has no relationship to the
  chrome, and putting it in `Appearance` would couple an editor to a panel.
- `WebsitesScreen.swift:246`, `cornerRadius: 5` on a website's favicon. It is a masked 44×44 image in
  a system `Form`, not a panel control. It should arguably be macOS's own icon radius rather than
  `Appearance`'s, which is why it is allowed rather than migrated.

---

## 7. Needs your decision

- **Q1 — The power button's orange.** `DisplayPanel.swift:319-321` lights `onTint` while the display
  is switched **off**, which contradicts `onTint`'s own comment ("the icon's orange says *this is
  running*"). Either the call site inverts or the comment is rewritten to "this button is engaged".
  Whichever you pick, the other four callers must be re-read against it. Note this is adjacent to,
  but not the same as, ROADMAP K22 — K22 is about the button being *wrong*, this is about it being
  *the wrong colour*.
- **Q2 — Five corner radii, or fewer.** `PanelButton` uses 5, `PanelWideButton` uses 6, and they sit
  10 points apart in the footer. § 5 assumes they become one `controlRadius`; picking 5 or 6 is a
  look decision I should not make for you. The card's 12 and the picture's 8 stay separate either
  way.
- **Q3 — The column hover fill.** Making `Color.white.opacity(0.15)` into `.quaternary` fixes light
  appearance and changes how the panel looks in dark. Confirm before step 3.
- **Q4 — Whether `CropSelectionView` is exempted as a file or line by line.** § 6 argues for the
  file. The cost of being wrong is that a genuinely shared value could later be hardcoded there
  unnoticed.
- **Q5 — Window widths.** Five windows, five widths, never decided. § 5 deliberately does *not*
  tokenise them, on ROADMAP N3's reasoning. If you think Settings at 400 and Websites at 480 should
  match, that is a separate, smaller change and should not ride along with this one.

## 8. Explicitly not proposed

- A `ButtonStyle` or `ViewModifier` library. There is one panel; a second implementation is what
  would justify the abstraction, and it does not exist (ROADMAP X4's reasoning).
- Restyling the `Form` screens to match the panel. That would trade away the accessibility and
  appearance behaviour § 4 says is the reason to use stock controls.
- A colour asset catalogue. One colour is app-specific; the rest are semantic system styles that a
  catalogue would only obscure.
- Touching `MenuBarBand`, `DimWhenUnfocused`, or anything under `Wallpaper/`. None of them draws
  chrome.
