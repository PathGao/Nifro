# Shelved: multi-display sync

**Status: removed from the app. Nothing here is built, linted, scanned or shipped.**

This file is the whole of what is left of the feature that let one display show what another display
showed. The code that made it work is gone from the repository; this is not a pointer to it. The
surface — the button, the menu, the way a follower's controls went quiet — is preserved below as the
actual Swift it was, doc comments intact, because the arguments in those comments are the part that
was expensive to arrive at. Everything underneath the surface was deleted without being archived as
code, so § 3 is the only record of how it worked and has to be read as the specification, not as a
summary of something you can go and look at.

Why the file is here and not in `docs/` proper: `docs/shelved/` participates in nothing. No Xcode
target lists it, `Package.swift` does not name it, `swiftlint` and `periphery` never read a markdown
file, and the release disk image contains the built `.app` and an Applications symlink and nothing
else from the repository. It is markdown rather than an unbuilt `.swift` file for one reason:
`.swiftlint.yml` has no `included:` key, so SwiftLint walks the whole working tree and a stray
`.swift` file anywhere in it would be linted — the feature would still be in the build, just quietly.

Removed on the maintainer's decision after three audits on real two-display hardware found the
defects in § 4. It is on the roadmap to be reclaimed. Read § 4 and § 5 before rebuilding it.

---

## 1. What a person could do

Two displays, each showing its own website. On either column of the display panel, a `link` button
sat beside the display's name. Pressing it opened a short menu offering the other displays by name:
**Show what *Studio Display* shows**. Choosing one made *this* display a follower of that one — the
display you were standing at gave up deciding, and the other carried on exactly as it was. Within a
moment the follower was showing the leader's page, and from then on any change made to the leader's
website — a different site, a new URL, custom CSS, a crop, a schedule — appeared on the follower too.
If both were playing video, the two pictures held to the same position in the video for as long as
they were up. Only the leader made sound.

The follower's own column then went dim and stopped responding: its picker, its arrows, its rotation
mode, its interval field, its mute, its power button and its Crop button were all inert. The one
thing that stayed live was its `link` button, now lit, whose menu had exactly one entry: **Stop
following *Studio Display***, ticked. Choosing it gave the display back to itself.

On the leader's column the `link` button was lit too. Its menu offered the displays that were not
already following it, plus one more entry at the bottom once anything was: **Release every display
following this one**.

The arrangement survived quitting and relaunching the app.

---

## 2. The UI, preserved

Verbatim from `Nifro/Screens/DisplayPanel.swift` and `Nifro/Screens/DisplayPanelModel.swift` as they
stood at removal. Nothing here compiles any more — `SyncGroup` and `Display.settingsKey`'s sync use
are gone — and it is not meant to. Read the doc comments; they are the design.

### 2.1 The title row and the `link` button

The button, its lit state, the menu and its three entries, and the argument for why it is a button at
all rather than a menu hung on the title.

```swift
	/**
	The display's name, with a button beside it for syncing this display to another.

	A button rather than a menu on the title itself. The title looked like a title, so the way into
	syncing was a thing you had to already know was there — the one control in the panel with no
	affordance at all.

	Lit when this display is in a group. A ticked entry means already synced; choosing it again breaks
	that pairing, and the entry that leaves is the one that was picked rather than the one whose menu
	it is — the leader's menu is the one that stays usable.
	*/
	@ViewBuilder
	private var displayName: some View {
		HStack(spacing: 5) {
			Text(column.displayName)
				.font(.headline)
				.lineLimit(1)
				.truncationMode(.middle)

			if !column.syncOptions.isEmpty {
				Menu {
					ForEach(column.syncOptions) { option in
						Button {
							model.apply(option, on: column.display)
						} label: {
							switch option {
							case .follow(_, let name):
								Text("Show what \(name) shows")
							case .unfollow(let name):
								Label(String(localized: "Stop following \(name)"), systemImage: "checkmark")
							case .releaseAll:
								Text("Release every display following this one")
							}
						}
					}
				} label: {
					Image(systemName: "link")
						.font(PanelMetrics.symbolFont)
						.frame(width: 22, height: 20)
						.foregroundStyle(isSynced ? PanelMetrics.onForeground : AnyShapeStyle(.secondary))
						.background(
							isSynced ? AnyShapeStyle(PanelMetrics.onTint) : AnyShapeStyle(.quinary),
							in: RoundedRectangle(cornerRadius: PanelMetrics.controlRadius)
						)
				}
				.menuStyle(.borderlessButton)
				.menuIndicator(.hidden)
				.fixedSize()
				.help(String(localized: "Show the same wallpaper as another display"))
				// The exemption above is from following, not from loading. A group can outlive the
				// display that leads it, so a follower has to keep its way out — a load cannot outlive
				// anything, it is a few seconds and it lets go of the button by itself.
				.disabled(column.isLoading)
				.opacity(column.isLoading ? 0.45 : 1)
			}
		}
		.frame(maxWidth: PanelMetrics.columnWidth)
	}

	/**
	Lit when this display is part of an arrangement, whether it leads it or follows it.
	*/
	private var isSynced: Bool {
		column.isFollowing || column.syncOptions.contains { if case .releaseAll = $0 { true } else { false } }
	}
```

### 2.2 The follower treatment on the rest of the column

The column's body. The dimming, the disabling, the picker held outside the dimming, and the
comment arguing the title-row exemption.

```swift
	var body: some View {
		VStack(spacing: 9) {
			displayName

			VStack(spacing: 9) {
				VStack(spacing: 9) {
					MarqueeText(text: column.websiteName ?? String(localized: "No Website"), isActive: isHovering)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.frame(width: PanelMetrics.columnWidth, height: 16)

					preview

					rotationControls
				}
				.opacity(inertOpacity)

				// Outside the dimming, and only that. It is disabled with the rest of the column, but
				// while a page is on its way it is also the thing reporting that — and a pulse under a
				// 0.45 veil is not one.
				picker
					.opacity(column.isFollowing ? 0.45 : 1)

				modeButtons
					.opacity(inertOpacity)
			}
			// A follower shows the leader's wallpaper, so its own controls would be arguing with the next
			// correction five seconds later. A load is the other reason a column cannot be used: the page
			// being asked for has not arrived, so every control here would be aimed at a display that is
			// already on its way somewhere.
			//
			// Everything below the title is inert for both. The sync button in the title is exempt from
			// the first and not the second: a follower keeps its way out, because disabling it would
			// leave a group with no way out at all if the leader's display went away, while a load lasts
			// a few seconds and lets go of the button by itself.
			.disabled(column.isFollowing || column.isLoading)
		}
```

### 2.3 One dimness for both reasons

```swift
	/**
	How dim a control looks while the column cannot be used.

	One value for both reasons, because they mean the same thing to the person looking at it: nothing
	here will answer right now.
	*/
	private var inertOpacity: Double {
		column.isFollowing || column.isLoading ? 0.45 : 1
	}
```

### 2.4 What the column carried

The two fields of `DisplayPanelModel.Column` the UI above read, with the argument for the follower
treatment stated where the data is rather than where it is drawn.

```swift
		/**
		The displays this one could be synced with, and whether it already is.
		*/
		let syncOptions: [SyncOption]

		/**
		Whether this display is following another rather than leading.

		A follower shows what the leader shows, so its own controls would be arguing with the next
		correction five seconds later. It is dimmed and inert, except for the one control that can
		undo the arrangement.
		*/
		let isFollowing: Bool
```

### 2.5 The shape the menu was built from

`SyncOption` and the rule for what the menu offered in each state. The two calls into `SyncGroup`
are the deleted half — what matters here is the doc comment, which is the whole argument for why a
follower is offered one entry and a leader is offered the rest.

```swift
	/**
	What this display's sync button offers.

	A follower is offered only the way out: it shows what its leader shows, and picking a third display
	from there would be asking two screens to decide the same thing.

	A display that is followed is offered the rest, plus the way to release everyone at once. That last
	entry is the only thing its button has to say when everything else is already following it —
	otherwise the button would open an empty menu.
	*/
	func syncOptions(for display: Display?) -> [SyncOption] {
		if let leader = SyncGroup.leader(of: display) {
			return [.unfollow(name: name(of: leader))]
		}

		let followers = SyncGroup.followers(of: display).map { Display.settingsKey(for: $0) }

		var options: [SyncOption] = AppState.shared.scenes
			.map(\.display)
			.filter {
				let key = Display.settingsKey(for: $0)
				return key != Display.settingsKey(for: display) && !followers.contains(key)
			}
			.map { .follow(display: $0, name: name(of: $0)) }

		if !followers.isEmpty {
			options.append(.releaseAll)
		}

		return options
	}

	enum SyncOption: Identifiable {
		/// Follow that display: this one stops deciding.
		case follow(display: Display?, name: String)

		/// Stop following, named so the user can see what they are leaving.
		case unfollow(name: String)

		/// Let go of everything following this display.
		case releaseAll

		var id: String {
			switch self {
			case .follow(let display, _):
				"follow-\(Display.settingsKey(for: display))"
			case .unfollow:
				"unfollow"
			case .releaseAll:
				"release"
			}
		}
	}

	private func name(of display: Display?) -> String {
		display?.localizedName ?? String(localized: "Main Display")
	}
```

### 2.6 The strings

Four entries in `Nifro/Localizable.xcstrings`, with their translations.

| Key | zh-Hans |
|---|---|
| `Show what %@ shows` | 显示 %@ 正在显示的内容 |
| `Stop following %@` | 不再跟随 %@ |
| `Release every display following this one` | 解除所有跟随这块显示器的同步 |
| `Show the same wallpaper as another display` | 与另一块显示器显示同一个壁纸 |

The last one is the `link` button's tooltip. The first three are the menu entries, in menu order.

---

## 3. What was underneath

Organised by what the person did. Every mechanism below was deleted; none of it is archived as code.

### 3.1 The relation itself: what was stored, and where

`Defaults[.syncGroups]`, a `[String: String]` keyed by display, mapping **a follower to its leader**.
Both sides were `Display.settingsKey(for:)` — the same key the app already used for per-display
rotation modes, intervals, switched-off displays and Browsing Mode, so screens that come and go leave
nothing behind and a key never outlives the screen it names.

A flat map rather than a list of sets, because the question asked of it was always "what is *this*
display in", and a list would have to be searched to answer that.

The direction was the design decision, not an implementation detail. **The display that asks becomes
the follower.** Picking "sync with B" while looking at A is A saying *show me what B shows*, so A
stops deciding and B carries on as it was. Storing it as follower → leader made "who follows whom" a
recorded fact rather than something derived from the order displays happened to be in.

Two important consequences of the shape:

- A leader could have many followers. A follower had exactly one leader.
- Chains were forbidden. A group with a follower-of-a-follower is a group that disagrees with itself.

Nothing in the app validated the map on read; the two writers below were what kept it flat.

### 3.2 The moment "Show what B shows" was chosen

Four things happened, in this order, and the order mattered:

1. **The relation was written.** `follow(A, following: B)`. It refused if the two keys were equal.
   Before writing `A → B` it did two repairs: it removed any entry making **B** itself a follower (the
   new leader cannot be a follower, or the group has two opinions), and it re-pointed everything that
   was following **A** at **B** instead — the followers were handed over rather than left pointing at
   a display that no longer decided anything.
2. **The leader's website was mirrored onto its followers.** See § 3.4.
3. **The video clock was anchored**, from where **B** is *now* rather than from zero, so joining a
   group did not send the display that was already playing back to the start of its video. See § 3.5.
4. **Audibility was re-applied** across every scene, because who is audible is a property of the
   group and had just changed. See § 3.6.

"Stop following" wrote one deletion (`leave`: remove this display's key). "Release every display
following this one" filtered the map for entries whose value was this display's key and dropped them
all. Neither of those two anchored anything; both restarted the media clock, which noticed the group
was smaller or gone.

### 3.3 What the follower's controls did, and why

`Column.isFollowing` was `SyncGroup.leader(of: display) != nil`, recomputed every time the panel
rebuilt its columns (about twelve times a second while the panel was open).

Everything below the display's name was `.disabled(column.isFollowing || column.isLoading)` and
drawn at `0.45` opacity. The reason was not politeness: a follower shows the leader's wallpaper, so
its own controls would be arguing with the next mirror. Pressing Next on a follower and watching the
leader's page reappear a moment later is a control that lies about what it does.

Loading was the second reason for the same treatment, and the two were deliberately given one
appearance because they mean the same thing to the person looking: *nothing here will answer right
now*. That is what `inertOpacity` was for.

The `link` button was exempt from the first and not the second. A follower had to keep its way out,
because a group could outlive the display that led it and a disabled button would leave it with no
way out at all; a load lasts a few seconds and lets go of the button by itself. The website picker
was likewise held outside the *dimming* (though not outside the disabling), because while a page is
on its way the picker is also the thing reporting that, and a pulse under a 0.45 veil is not one.

### 3.4 What propagated, from where, and when

**From the leader, on every edit to any website, to all of that leader's followers.**

The hook was `WebsitesController.update(_:_:)` — the single read-modify-write every edit to a website
already went through. It ended by mirroring from the edited website's display. Putting it there
rather than at each call site was the point: the call sites were seven at the time, and hooking each
one means finding all of them again whenever an eighth is added.

The mirror itself:

- **It resolved the source first.** `SyncGroup.leader(of: display) ?? display`. A follower has
  nothing to say; what it shows is decided by the display it follows. **This one line is the cause of
  defect K16 in § 4 — read it there before reusing it.**
- **It copied the leader's whole entry onto each follower**, except two fields that are the entry's
  *identity* rather than its *contents*: `id` and `display`. Copying `display` would move the website
  instead of mirroring it; copying `id` would make two entries the same entry. The follower's data
  store, thumbnail and remembered scroll position are all filed under its `id`, which is why `id`
  had to survive the copy — and why `Website.id` was a `var` at all.
- **`zoom` was copied like everything else.** This is the one that looks wrong and was not. A region
  is stored as a centre and a magnification, not a rectangle, so the same value on a wider screen
  shows the same part of the page across a wider view — which is exactly what "the same wallpaper on
  both" should mean. Two screens on one website are still two entries with their own crop, sound and
  zoom, which is what lets a 27-inch and a 14-inch show a page at the same *physical* size with the
  big one simply showing more of it. Syncing did not undo that; it said the two entries were the same
  wallpaper. A screen that wanted its own framing stopped following.
- **A follower with no entry got one created.** Syncing a display that was empty should fill it; the
  alternative is a group where one member silently shows nothing.
- **It guarded against its own re-entry** with a static `isMirroring` flag. Mirroring writes to the
  followers, and writing to a follower is exactly what asks for a mirror — without the guard the
  first sync recursed until the stack ran out.

Mirroring ended by making each written entry current on its display, so the page actually changed
rather than only the stored record.

### 3.5 How two videos were kept at the same place

**Nobody followed anybody.** The app handed every page in a group one number — the wall-clock moment
that group's video was at zero — and each page worked out where it should be from that number and its
own clock, four times a second, for as long as it was up. Two web views on one Mac read the same
system clock, so two pages given the same epoch agree without exchanging anything.

Frame-exact was never on offer and was never claimed: independent decoders, independent compositing,
no genlock, and `currentTime` is itself defined as an approximation.

**That design replaced the obvious one, and the reason is the most valuable thing in this section.**
Reading the leader's position and correcting the follower towards it was built and measured for a
fortnight of afternoons and never got below a second of error. A seek aims at where the leader *was*
while the leader keeps moving; a stall on one display drags the other; and a round trip through the
app puts a floor under how often it can even look. None of those exist in the epoch design. A page
that stalls comes back onto the same curve by itself, and the page beside it never knew.

The app still had to be the hub for the one number, because every website has its own
`WKWebsiteDataStore`: the pages share no storage at all — `BroadcastChannel`, `localStorage`,
`SharedWorker` and service workers are all partitioned per store — so they have no way to speak to
each other. But it was one number stated every couple of seconds, not a correction negotiated five
times a minute.

**Stored as** `Defaults[.syncEpochs]`, a `[String: Double]` keyed by the *leader's* display key —
seconds since 1970. One number per group. A page's epoch was found by resolving its own key to its
leader's key (or to itself, if anything followed it) and reading that entry.

**Re-stated** every 2 seconds by a `Timer`, to every scene, so a page that had just reloaded — a
rotation, a reload interval, a display switched back on — was told again without anything having to
notice that it had reloaded. The timer ran only while `syncGroups` was non-empty, and stopping it
broadcast `nil` once on the way out so a dissolved group's pages let go of their epoch.

**Scrubbing.** A drag on a progress bar moved the whole group rather than being undone a quarter of a
second later: the page reported the position it had been dragged to, whoever dragged became the new
zero, and every other display converged on it. The page told our own seeks apart from a person's by
remembering the last position it had seeked to and ignoring anything within 0.5s of it.

**The page-side script** rode in `.defaultClient` alongside the audio control, because that is the
only content world the app can talk to — `addJavaScript` puts each script in a fresh anonymous world,
which is write-only from Swift. It was injected with `forMainFrameOnly: false` so a copy landed
inside the framed player too, where the media element is same-origin and can simply be read. That is
why this needed no YouTube IFrame API — which could not have done the job anyway, since its
`setPlaybackRate` accepts only the discrete rates the player offers and there is no 1.1 among them.

What the script did, every 250ms: find the largest video with a finite duration; compute where it
should be from `(now − epoch) mod duration`; wrap the drift around the loop point, since without
wrapping a looping wallpaper video gets seeked the instant it returns to zero; and then correct.
Separately, every 1000ms, each frame that had media reported its reading upward to the top frame,
which kept it for the app to read — `evaluateJavaScript` only ever reaches the main frame, and a
framed player's main frame has no media of its own to notice. Of two readings the top frame kept the
one showing more picture, unless the one it held was more than 3 seconds stale, so a player that has
been replaced stops holding the answer forever; a page with an advertisement beside the player has
several videos and keeping whichever arrived last made the reading hop between them.

It spent nothing on a player that could not keep playing — `element.seeking` or `readyState < 3` and
it returned. Measured: a jump onto a video that was still buffering landed, and the video then
resumed a second and a half behind.

**The four thresholds, with the measurements behind them.** These are the part that wants re-tuning
against real screens, and they were interpolated into the script rather than read from it.

| | Value | Why that number |
|---|---|---|
| `engage` | 0.06s | Above this, start correcting. Every page holds itself to the clock, so two displays are at worst *twice* this apart — the number to compare against what anybody can see is `2 × engage`. At a sixth of a second, where this started, the pair sat at a steady third of a second and the dead zone was the whole of the remaining error. |
| `release` | 0.02s | Below this, stop correcting. Separate from `engage` on purpose: one threshold for both switches the correction on and off around the same number, and every switch costs a visible hitch on WebKit — `playbackRate` interrupts playback briefly on each change there (WebKit bug 208142, which dash.js works around by refusing rate changes under 0.25 on Safari). With a gap between the two, one correction is one rate change in and one out. |
| `seek` | 2.0s | Above this, jump instead of nudging. Past a couple of seconds it is an *event* — a loop, a wake, a page that reloaded — and not something playing faster can close. Deliberately not lower, though a second out of step is plainly visible: seeking a streaming player costs a re-buffer, and a re-buffer is about as long as the error being corrected. |
| `nudge` | 0.10 | How much faster or slower a page runs while correcting. A tenth is well inside what anybody sees. A hundred observers watching football were not spontaneously aware of speed changes up to twelve percent, and asked to discriminate they managed about nine — with the sound on. |

### 3.6 What decided audibility

`WallpaperScene.shouldPlaySound` was the website's own `audio` setting **and** one rule on top of it:
in a sync group, only the leader is audible.

The others are showing the same video a fraction of a second apart, and two copies of the same
soundtrack that close together is not stereo — it is an echo, and it is worse than either one alone.
Supermarket walls of televisions do the same thing: many pictures, one sound.

The stored setting was never touched, so a display leaving a group got its own sound back. The rule
was applied by re-running `applyAudioSetting()` over every scene whenever the group changed, and read
again by the panel to draw each column's mute button.

### 3.7 What happened when a display arrived or left

**On launch**, `applyToFollowers()` ran before the media clock started: for every distinct leader in
the map, it mirrored that leader's page onto its followers. This existed because the group survived a
quit and nothing was re-applying it on the way back up — a follower came back correctly greyed out
while still showing whatever it had been showing before, so the group looked joined and behaved as
two unrelated displays until somebody picked it again.

**When a display was attached or removed**, nothing touched the map. The map is keyed by display key,
so an unplugged display's entry simply sat there, and re-attaching it restored the arrangement. That
was the intent.

**But the map was read through the live scene list.** `leader(of:)` looked its answer up in
`Defaults[.syncGroups]` and then resolved that key to a `Display` by searching
`AppState.shared.scenes`. With the leader's display gone there was no scene to find, so it returned
`nil` — and every caller read `nil` as "this display is in no group". **This is defect K-leader in
§ 4.** The stored relation and the resolved relation were two different things and only one of them
survived a display going away.

---

## 4. What went wrong

Three defects, all measured on real two-display hardware. A rebuild that does not answer these
reproduces them.

### K16 — Editing any setting on a follower destroyed that website

The worst of the three, and the reason the feature was removed rather than repaired in place.

`update()` ended in a mirror, and the mirror resolved its source with
`SyncGroup.leader(of: display) ?? display`. Editing a *follower's* website therefore resolved to the
**leader**, and the mirror then copied the leader's entry over the entry that was being edited. The
URL, title, custom CSS, custom JavaScript, schedule and crop the user had just changed were gone —
not set aside, gone, with no way back. Leaving the group did not bring them back, because there was
nothing left to bring back.

Measured on the maintainer's own list: six of eight entries were copies of one leader's page, and two
originals were unrecoverable. The appended copies were bounded at one per follower display that
started empty, and nothing ever removed them.

Both halves of this are one decision: a mirrored entry is a **view** of the leader's entry, not a
website in its own right, and it should never have been in the website list at all.

### K-step — Next and Previous broke the group without saying so

The panel disabled the arrows for a follower. The keyboard shortcut and the App Intent went straight
to `WebsitesController.makeNextCurrent(on:)` and had no such guard. Stepping a follower from a
shortcut therefore changed the follower's own current website, while the panel — reading
`isFollowing` from the still-intact map — went on drawing it as synced and inert.

The guard was in the view. The rule belonged in the controller, where every route passes.

### K-leader — A group whose leader went away dissolved in silence

Unplug the leader's display and `leader(of:)` returned `nil` for every follower, because it resolved
through the live scene list (§ 3.7). Nothing announced this. All four consequences happened at once:

- Followers started playing sound, because the audio rule read the same `nil`.
- The panel offered each former follower the full menu, as though it had never been in a group.
- Mirroring stopped, because `followers(of:)` also filtered through the scene list.
- `MediaSync` kept anchoring to the departed leader's epoch key, which nothing was reading any more,
  so scrubbing a follower snapped back within two seconds.

The stored map, meanwhile, was untouched and still said the group existed. Re-attaching the display
brought the whole arrangement back, which is the one part that worked as intended and is also what
made the failure so hard to see.

---

## 5. What a rebuild must decide before writing any code

These three are not implementation questions. Each of the defects above is one of them left
unanswered, and no amount of care in the mirroring code substitutes for answering them.

### 5.1 What does an edit on a follower *mean*?

There are only three honest answers, and the old code accidentally picked a fourth:

- **It is impossible.** The follower's entry is not editable anywhere — not in the panel, not in the
  websites list, not by shortcut, not by intent. This is the only answer that needs no guard at every
  route, because there is nothing to guard: a mirrored entry is not in the list.
- **It leaves the group.** Editing a follower is how you say "I want my own again", and the edit is
  applied to a website that is now the display's own.
- **It edits the leader**, and therefore the whole group. Coherent, and surprising — the person is
  looking at one display and changing two.

The old code chose none of them and instead applied the edit and then overwrote it, which is the one
answer nobody would have chosen.

Whichever is picked, it has to hold on **every route into an edit** — panel, websites window, keyboard
shortcut, App Intent, URL command — which is a strong argument for making it a property of the data
(the entry does not exist to be edited) rather than a check in each caller.

### 5.2 What does "following a display that is not attached" mean?

Two coherent answers, and the old code had one of each in different places:

- **The relation is to a display key**, and it persists whether the screen is plugged in or not. Then
  every reader must be able to say "this display follows a display that is not here" and behave
  deliberately — which probably means the follower keeps showing what it last showed, stays inert,
  stays silent, and says so in the panel rather than silently becoming a free display again.
- **The relation is to an attached display**, and unplugging the leader dissolves the group for real
  — the map is written, not just read differently, and the followers are given back to themselves
  properly, with sound, controls and their own websites.

What cannot happen again is the map saying one thing and every reader saying another.

### 5.3 Does the relation belong to displays, or to websites?

The old feature said *displays* — "this screen shows what that screen shows" — but implemented it by
copying *websites*, and every defect above lives in that gap.

If the relation belongs to displays, then a follower has no website of its own while it follows; it
has a *reference* to the leader's, resolved at the moment of drawing. There is nothing to overwrite,
nothing to accumulate in the list, and nothing to edit. The per-display things that must stay
per-display — crop, zoom framing, sound — are then explicitly named as such rather than being
whatever the copy happened to leave alone.

If the relation belongs to websites — "these two entries are one wallpaper" — then it is a different
feature with a different UI, and it should not be reached from a button in a display's title row.

Answer this one first. The other two mostly follow from it.

### 5.4 A note on the two preference keys still on disk

`syncGroups` and `syncEpochs` were deliberately **not** removed from existing users' preferences when
the feature was deleted. Nothing declares them any more, so nothing reads them and they cost two
dictionary entries; writing a migration to delete them would have meant shipping code for a feature
that no longer exists.

That has one consequence for a rebuild. If it declares `syncGroups` again with the same name and a
different value shape, `Defaults` will fail to decode what is on disk and fall back to the default —
silently. Either keep the old shape (`[String: String]`, follower key → leader key) and inherit
arrangements that were set up before the removal, which is a small gift, or pick a new key name and
leave the old ones dead.
