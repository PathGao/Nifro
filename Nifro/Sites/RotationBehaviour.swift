import AppKit

/**
Rotating between the websites on a display, and letting a website say when it is allowed to be up.

Two requests that turned out to be one mechanism. Rotation is the obvious half. The other is a schedule. A news page in the morning, something calmer at night. Both answer "which of this display's websites should be showing right now", so they share one answer instead of fighting over the same state.

A website with no hours set is always eligible. If a schedule leaves a display with nothing eligible, that display ignores the schedule rather than going blank. An empty desktop is worse than the wrong page.
*/
extension Website {
	/**
	Whether this website is allowed to be showing at `date`.
	*/
	fileprivate func isScheduled(at date: Date, calendar: Calendar = .current) -> Bool {
		guard
			let startHour,
			let endHour
		else {
			return true
		}

		return isHour(calendar.component(.hour, from: date), within: startHour, until: endHour)
	}
}

extension WebsitesController {
	/**
	The websites the playlist on `display` allows to be showing right now, in list order.

	The filter used to be "the websites pinned to this display" over the whole website list, which is
	the direction the playlists inverted: a display could only offer what already named it, so a second
	monitor's chooser had exactly one item in it and its rotation arrows had nothing to step to.
	*/
	private func eligible(for display: Display?, at date: Date = .now) -> [Website] {
		eligible(in: playlist(for: display, in: Defaults[.playlists]), at: date)
	}

	/**
	The same question asked of a playlist already in hand.

	Split out because the panel asks it too, and that is the whole of I2: "can this display rotate" and
	"rotate to what" have to be one expression. They were two — the arrows lit on the count of the
	display's websites and stepped through this, which narrowed it by the schedule — so a display with
	one website it could show and one it could not lit both arrows and did nothing when either was
	pressed. Deriving the first from the second is what closes that, and it only works if there is one
	of these to derive from.

	Handed the playlist rather than the display, because the panel resolves it once per refresh and
	builds a column per display off the same list; going back through `Defaults[.playlists]` here would
	decode every website in every playlist again, once per display, on every pass of
	`DisplayPanelModel.startLiveRefresh`.
	*/
	func eligible(in playlist: Playlist?, at date: Date = .now) -> [Website] {
		let members = playlist?.websites ?? []
		let scheduled = members.filter { $0.isScheduled(at: date) }

		// Never let a schedule empty a display.
		return scheduled.isEmpty ? members : scheduled
	}

	/**
	Whether this display decides an order in advance rather than taking its playlist as it comes.

	One predicate with two readers — `ordered` below and the end of a pass in `makeNextCurrent` — for
	the reason every pair in this file is one expression: the two are asking whether the same display
	is shuffled, and two spellings of that is a display whose order is consulted and never renewed.
	*/
	private func isShuffled(_ display: Display?) -> Bool {
		Defaults[.rotationModes][Display.settingsKey(for: display)] == .random
	}

	/**
	The same list in the order this display walks it.

	**A permutation and never anything else**: the same websites, the same count, a different order. That
	is what lets the panel go on lighting its arrows with `eligible(in:).count > 1` while the arrows step
	through this — `ScopeTests` has that pair on record as one question with one derivation, and a
	permutation cannot make the two disagree.

	In every mode but Random this is the playlist's own order and this function is the identity. In
	Random it is the shuffled order, and this is the only place one is decided, renewed or thrown away.

	**The invalidation is here, where the order is read, rather than on a publisher.** What it replaced
	watched `playlists` and compared the flattened website ids, which could not see a playlist switch —
	the same websites are in the app either way — and there is a fourth change no key moves for at all:
	a website leaves `eligible(in:at:)` when its scheduled hours end, on the turn of the hour, silently.
	Asked here, all four are the same question — *is this order still made of the websites this display
	can show* — and the answer costs a set and a filter over a list of tens, on a path that runs on an
	edit and on a tick rather than on a frame.

	Two ways for the answer to be no, and they are not the same no. A website added or removed leaves an
	order that is still recognisably this display's, and `orderCarriedForward` keeps it — the argument
	for appending rather than reshuffling is written there. A playlist switch leaves nothing of it, and
	the order is decided again.

	The stored playlist is asked first and is not merely an optimisation for that second case: two
	playlists sharing a website would carry a single survivor forward and append the whole new list
	behind it in list order, which is a shuffle that has not been shuffled. `Defaults[.currentPlaylists]`
	rather than the resolved playlist, because that is a dictionary of ids and the resolved one is a
	decode of every website in every list. **The ceiling**: the key holds no entry for a display that has
	never been pointed anywhere, so explicitly choosing the default playlist a display was already
	falling back to reads as a switch and costs one reshuffle. `orderCarriedForward` is what makes that
	the ceiling and not a hole — a stored id naming a deleted playlist agrees with itself forever, and
	the carry-forward finds nothing of that order left and starts again anyway.
	*/
	func ordered(_ candidates: [Website], on display: Display?) -> [Website] {
		let key = Display.settingsKey(for: display)

		guard
			isShuffled(display),
			!candidates.isEmpty
		else {
			return candidates
		}

		guard
			let held = shuffledOrders[key],
			held.playlist == Defaults[.currentPlaylists][key]
		else {
			return reshuffle(candidates, on: display)
		}

		let carried = orderCarriedForward(held.websites, through: candidates.map(\.id))

		guard !carried.isEmpty else {
			return reshuffle(candidates, on: display)
		}

		shuffledOrders[key] = .init(playlist: held.playlist, websites: carried)

		return carried.compactMap { candidates[id: $0] }
	}

	/**
	Decide this display's order again, and hand it back.

	The one writer of a fresh order, so that "a new order starts at the website already on screen" is
	said once. Three things ask for one: a display with no order yet, which is every display on the
	first tick after a relaunch; a pass that has reached its end; and the Random command, which is a
	request for a website that is not the next one in the plan and therefore a request for another plan.

	Stored for a display that is not in Random mode too, and not guarded against, because the Random
	command is offered whatever the mode is. A looping display simply never reads it — until it is set
	to Random, and then it picks up the order the command left, which is the answer that surprises
	nobody: the shuffle it starts is the shuffle it was just given.
	*/
	private func reshuffle(_ candidates: [Website], on display: Display?) -> [Website] {
		let key = Display.settingsKey(for: display)
		let ids = shuffledOrder(of: candidates.map(\.id), startingWith: currentWebsiteID(on: display))

		shuffledOrders[key] = .init(playlist: Defaults[.currentPlaylists][key], websites: ids)

		return ids.compactMap { candidates[id: $0] }
	}

	/**
	The website that should be showing on `display` right now, taking the schedule into account.
	*/
	func scheduled(for display: Display?, at date: Date = .now) -> Website? {
		scheduled(in: ordered(eligible(for: display, at: date), on: display), on: display)
	}

	/**
	The same question asked of a candidate list already in hand.

	Split out for the reason `eligible(in:)` above was, and by the same cut: Next and Previous each
	want the list *and* the position in it, and asking for the position separately went back through
	`eligible(for:)` — so one arrow press decoded every website in every playlist twice, `css` and
	`javaScript` strings and all, and then linear-scanned the second list for a whole `Website` that
	had come out of the first.

	The pair also each took their own `.now`, so a press landing on the hour could look a position up
	in a list the schedule had already moved on from. One list resolved once has no such seam.
	*/
	private func scheduled(in candidates: [Website], on display: Display?) -> Website? {
		showingPosition(in: candidates, on: display).map { candidates[$0] }
	}

	/**
	Where in `candidates` this display is standing.

	The position and the website standing at it are one answer asked two ways, and they have to stay one
	answer: Previous steps by handing the website to `elementBeforeOrLast`, Next steps by handing the
	number to `nextRotationIndex`, and the page on screen is the website. Worked out separately they
	agree for exactly as long as the mark names a website the list still holds, and the app has everyday
	ways of breaking that — a website falling out of its hours leaves the list from under the mark, and
	a website deleted takes the mark's answer with it.

	`showingIndex` and not a `firstIndex` of its own, because that function is where "nothing here is
	marked means the top of the list" is settled, and it is the reading `scheduled(for:)` hands to every
	scene. A mark this list does not recognise therefore means the same thing to the clock, to the arrows
	and to the page already up: position zero, which is the page already up. Next from there is the
	website after the one on screen, which is the only answer that is not a step to where the display is
	already standing.
	*/
	private func showingPosition(in candidates: [Website], on display: Display?) -> Int? {
		let current = currentWebsiteID(on: display)

		// At most one of these can be true, because there is one entry per display to be true of. That
		// used to be a promise a sweep made about a flag on every website, and the promise was broken
		// by anything that wrote the list without going through the sweep — "Show on" was a `Binding`
		// straight into it, so moving a website carried its mark to a screen that already had one.
		return showingIndex(isCurrent: candidates.map { $0.id == current })
	}

	/**
	Move `display` to the next, previous, or a random one of its own websites.

	Next, Previous and Random live here rather than beside the rest of the list because they are the
	same mechanism as the rotation timer: they move one display's rotation. Walking the whole list instead
	would let a menu item on the screen in front of you change the wallpaper on the one behind you,
	which is the version of this that shipped and is the reason they take a display at all.

	Next is also what the clock presses. It had a second implementation for a while — `advance`, which
	resolved the cursor with a `firstIndex` of its own — and the two agreed for exactly as long as the
	mark named a website the list still held. That is now one verb with one caller more, which is also
	what lets Random be a mode rather than a branch: a shuffled display is one whose candidates come back
	in a different order, and stepping does not have to know.
	*/
	func makeNextCurrent(on display: Display?) {
		let candidates = ordered(eligible(for: display), on: display)

		guard let next = nextRotationIndex(count: candidates.count, after: showingPosition(in: candidates, on: display)) else {
			return
		}

		// The end of a pass, for a display that decided an order in advance. A wallpaper never finishes,
		// so the order is decided again rather than repeated — and the fresh one starts at the website
		// standing at the end of the old one, so the first step of the new pass cannot land back on the
		// page that is already up. Index 1 for exactly that reason, and `count > 1` is what makes it a
		// position rather than a crash: a one-website display wraps to itself on every step and has no
		// pass to end. It still falls through to the write below, because a step is also a request to
		// see something and that is how a display switched off is woken.
		//
		// Only forwards. Previous wrapping past the front is a walk back into the order that still
		// stands, and a reshuffle there would mean the way back was never the way you came.
		if next == 0, candidates.count > 1, isShuffled(display) {
			makeCurrent(reshuffle(candidates, on: display)[1], on: display)
			return
		}

		makeCurrent(candidates[next], on: display)
	}

	func makePreviousCurrent(on display: Display?) {
		let candidates = ordered(eligible(for: display), on: display)

		guard let previous = candidates.elementBeforeOrLast(scheduled(in: candidates, on: display)) else {
			return
		}

		makeCurrent(previous, on: display)
	}

	/**
	Point `display` at a website that is not the one coming next.

	Which is what is left of "Random" as a command now that Random is a mode with a plan. A plan makes
	the next website knowable, so a command that means "something else" cannot be a step along it: it
	decides the plan again and takes the first website of the new one. That is a uniform choice among
	the others — `shuffledOrder` puts the page already up at the front, so index 1 is any of the rest —
	and it leaves the display with an order rather than with a jump it cannot walk back out of.
	*/
	func makeRandomCurrent(on display: Display?) {
		let candidates = eligible(for: display)

		guard let only = candidates.first else {
			return
		}

		// One website is not a choice, and this still has to mean "show me something": stepping a display
		// that is switched off is how it is woken, and a command that refused here would leave the one
		// screen with the least to say answering nothing at all.
		guard candidates.count > 1 else {
			makeCurrent(only, on: display)
			return
		}

		makeCurrent(reshuffle(candidates, on: display)[1], on: display)
	}
}

extension WallpaperScene {
	/**
	Whether this display should be the one making the noise.

	The website's own setting and nothing else. Sound is per display because a website is per display:
	a display with no website on it has nothing to play, and every other display answers for itself.

	There used to be a second rule on top — in a sync group only the leader was audible, because two
	copies of one soundtrack a fraction of a second apart is an echo rather than stereo. That rule
	went with sync groups; `docs/shelved/MULTI-DISPLAY-SYNC.md` keeps it, because a rebuild needs it.
	*/
	var shouldPlaySound: Bool {
		website?.audio == .unmuted
	}

	/**
	Whether this display is switched off on its own.

	Separate from the app-wide Disable, and beneath it: turning the app off turns every display off,
	turning it back on returns each display to whatever it was set to. Two switches that both mean
	"off" would otherwise disagree about what "on" restores.
	*/
	var isDisabledForDisplay: Bool {
		get { Defaults[.disabledDisplays].contains(Display.settingsKey(for: display)) }
		set {
			if newValue {
				Defaults[.disabledDisplays].insert(Display.settingsKey(for: display))
			} else {
				Defaults[.disabledDisplays].remove(Display.settingsKey(for: display))
			}
		}
	}

	/**
	Whether this scene should have anything running, on screen, or worth photographing.

	The one place either "off" is asked, and the reason it exists is that until now nowhere asked
	both. Three things a switched-off display must not do each consulted its own subset: loading
	consulted neither switch, so `reloadWebsite` loaded the page `rebuildScenes` had just suspended;
	the two timers and the menu bar band consulted only the app-wide one, so a display switched off
	on its own kept its reload timer and kept tinting the menu bar with the colour of a page nobody
	could see; and the panel's picture consulted only "has something loaded", which the load nobody
	wanted had just made true. One switch was a member of a mechanism it had never joined.

	Asked here rather than spelled out at each of those sites, so a third thing that means "off"
	joins this expression and every site inherits it by existing. That is the argument `suspend()`
	makes for being one method rather than a list of four things at the call site, from the other
	end: `suspend()` is the one place a scene is stopped, this is the one place it is asked whether
	it should be running at all.

	Derived, not stored, and the two switches stay separate underneath — see `isDisabledForDisplay`
	directly above. Merging their storage would lose the thing that doc argues for: what the app-wide
	switch restores when it comes back on is each display's own setting, and one flag cannot remember
	that.
	*/
	var isSwitchedOff: Bool {
		!AppState.shared.isEnabled || isDisabledForDisplay
	}

	/**
	How this display rotates.
	*/
	var rotationMode: RotationMode {
		get { Defaults[.rotationModes][Display.settingsKey(for: display)] ?? .pinned }
		set { Defaults[.rotationModes][Display.settingsKey(for: display)] = newValue }
	}

	/**
	How many minutes this display waits between websites.

	Falls back to the machine-wide number this replaced when the display has none of its own — see
	`rotationInterval(stored:legacySeconds:)`, which is where that and the bounds live.
	*/
	var rotationIntervalMinutes: Double {
		get {
			rotationInterval(
				stored: Defaults[.rotationIntervals][Display.settingsKey(for: display)],
				legacySeconds: Defaults[.playlistInterval]
			)
		}
		set { Defaults[.rotationIntervals][Display.settingsKey(for: display)] = newValue }
	}

	/**
	Whether this scene's page is already the one the website list asks for.

	The test `applyWebsiteChanges` uses to decide which pages to reload, and `rebuildScenes` uses to
	decide whose timers to leave alone. Here rather than written out at both, because two copies of
	"nothing changed for this display" is how the timers came to disagree with the pages: a rebuild
	restarted every kept scene's clock, including the scenes `applyWebsiteChanges` had just decided
	were untouched.

	The whole website and not its identity, for the reason `loadedWebsite` gives: a scene showing an
	older version of the same website is not up to date.
	*/
	var isUpToDate: Bool {
		loadedWebsite == WebsitesController.shared.scheduled(for: display)
	}

	func resetRotationTimer() {
		rotationTimer?.invalidate()
		rotationTimer = nil

		// This display's own Browsing Mode, not the app's. Rotation pauses so that the page somebody is
		// interacting with does not move under them, and that is a fact about the screen they are
		// interacting with — the page behind them has nobody typing into it. Measured on two displays:
		// Browsing Mode on the built-in stopped the external rotating and reloading as well, and
		// nothing rearmed it afterwards. Nothing on this path takes focus, so there is no app-wide
		// cost to leaving the other display running — see `AppState.isBrowsingMode`.
		guard
			!isSwitchedOff,
			!AppState.shared.isBrowsingMode(on: display)
		else {
			return
		}

		// A minute, always, whatever this display's rotation is set to. The schedule needs checking even
		// when rotation is off, otherwise a website whose hours just ended stays up until something else
		// happens — and once a minute is fine for something measured in hours.
		//
		// So the timer is the tick and the interval is a count of ticks, rather than the timer being set
		// to the interval. Timing the rotation directly would tie how often the schedule is looked at to
		// a number that has nothing to do with it: a display told to rotate daily would also check its
		// hours daily, which is a website stuck up for a day. That was already true of the machine-wide
		// setting and only invisible because the field it came from was rarely moved off half an hour.
		rotationMinutes = 0

		rotationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
			Task { @MainActor in
				guard let self else {
					return
				}

				self.rotationMinutes += 1

				// Rotation used to be inferred from "is an interval set", which made it one answer for the
				// whole machine. Both halves are this display's own now: whether it rotates, and how often.
				let rotates = self.rotationMode != .pinned && Double(self.rotationMinutes) >= self.rotationIntervalMinutes

				if rotates {
					self.rotationMinutes = 0
				}

				self.advanceRotation(rotating: rotates)
			}
		}

		// Fifteen seconds of slack, so macOS is allowed to fire this alongside a wakeup it was making
		// anyway. Left at the default of zero, a repeating timer is a wakeup of its own every time, and
		// this one repeats for the life of the app on every display — which is the case Apple's energy
		// guidance names for `tolerance` in the first place.
		//
		// It promises nothing this tick was making. The tick is a minute standing in for a schedule
		// measured in hours, per the argument above. And a repeating timer works its next fire date out
		// from the original one rather than from when it actually fired, so slack cannot accumulate: a
		// display told to rotate every thirty minutes still rotates on the thirtieth tick.
		rotationTimer?.tolerance = 15
	}

	/**
	Move to whatever should be showing now.

	- Parameter rotating: `true` advances to the next website; `false` only corrects a website that has fallen out of its hours.
	*/
	private func advanceRotation(rotating: Bool) {
		let controller = WebsitesController.shared

		// One verb whatever the mode is. There were two, and the mode chose between them — which put the
		// difference between looping and shuffling in the caller, where the timer had to know about it,
		// where the panel's arrows did not, and where the two could therefore step differently. The
		// difference lives in `ordered(_:on:)` now: a shuffled display is one whose websites come back
		// in a decided order, and everything that steps steps the list it is handed.
		if rotating {
			controller.makeNextCurrent(on: display)
		}

		guard let next = controller.scheduled(for: display) else {
			return
		}

		guard next.id != website?.id else {
			return
		}

		controller.makeCurrent(next, on: display)
	}
}
