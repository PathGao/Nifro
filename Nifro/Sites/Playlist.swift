import AppKit

/**
Rotating between the websites on a display, and letting a website say when it is allowed to be up.

Two requests that turned out to be one mechanism (Plash#4). Rotation is the obvious half. The other, asked for in the same thread, is a schedule. A news page in the morning, something calmer at night. Both answer "which of this display's websites should be showing right now", so they share one answer instead of fighting over the same state.

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
	The websites on `display` that are allowed to be showing right now, in list order.
	*/
	private func eligible(for display: Display?, at date: Date = .now) -> [Website] {
		let onDisplay = showable.filter { $0.effectiveDisplay == display }
		let scheduled = onDisplay.filter { $0.isScheduled(at: date) }

		// Never let a schedule empty a display.
		return scheduled.isEmpty ? onDisplay : scheduled
	}

	/**
	Move `display` to the next website in its rotation.
	*/
	@discardableResult
	fileprivate func advance(on display: Display?, at date: Date = .now) -> Website? {
		let candidates = eligible(for: display, at: date)

		guard candidates.count > 1 else {
			return candidates.first
		}

		guard let nextIndex = nextRotationIndex(count: candidates.count, after: candidates.firstIndex { $0.isCurrent }) else {
			return nil
		}

		let next = candidates[nextIndex]
		makeCurrent(next)

		return next
	}

	/**
	The website that should be showing on `display` right now, taking the schedule into account.
	*/
	func scheduled(for display: Display?, at date: Date = .now) -> Website? {
		let candidates = eligible(for: display, at: date)
		return candidates.first(where: \.isCurrent) ?? candidates.first
	}

	/**
	Move `display` to the next, previous, or a random one of its own websites.

	Next, Previous and Random live here rather than beside the rest of the list because they are the
	same mechanism as the playlist: they move one display's rotation. Walking the whole list instead
	would let a menu item on the screen in front of you change the wallpaper on the one behind you,
	which is the version of this that shipped and is the reason they take a display at all.
	*/
	func makeNextCurrent(on display: Display?) {
		guard let next = eligible(for: display).elementAfterOrFirst(scheduled(for: display)) else {
			return
		}

		makeCurrent(next)
	}

	func makePreviousCurrent(on display: Display?) {
		guard let previous = eligible(for: display).elementBeforeOrLast(scheduled(for: display)) else {
			return
		}

		makeCurrent(previous)
	}

	func makeRandomCurrent(on display: Display?) {
		let candidates = eligible(for: display)

		// Built on demand and kept, because the point of the shuffled order is that it does not
		// repeat until it has been all the way round, and an iterator made fresh each time cannot
		// know where it had got to. Thrown away whenever a website is added or removed.
		var iterator = randomIterators[display] ?? candidates.infiniteUniformRandomSequence().makeIterator()

		defer {
			randomIterators[display] = iterator
		}

		guard let website = iterator.next() else {
			return
		}

		makeCurrent(website)
	}
}

extension WallpaperScene {
	/**
	Start, restart or stop this scene's rotation to match the current settings.
	*/
	/**
	Whether this display should be the one making the noise.

	The website's own setting, and then one rule on top of it: in a sync group only the leader is
	audible. The others are showing the same video a fraction of a second apart, and two copies of the
	same soundtrack that close together is not stereo — it is an echo, and it is worse than either one
	alone. Supermarket walls of televisions do the same thing: many pictures, one sound.

	The stored setting is not touched, so a display leaving a group gets its own sound back.
	*/
	var shouldPlaySound: Bool {
		guard website?.audio == .unmuted else {
			return false
		}

		guard let leader = MediaSync.leader(of: display) else {
			return true
		}

		return Display.settingsKey(for: leader) == Display.settingsKey(for: display)
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
	How this display rotates.
	*/
	var rotationMode: RotationMode {
		get { Defaults[.rotationModes][Display.settingsKey(for: display)] ?? .pinned }
		set { Defaults[.rotationModes][Display.settingsKey(for: display)] = newValue }
	}

	func resetPlaylistTimer() {
		playlistTimer?.invalidate()
		playlistTimer = nil

		guard
			AppState.shared.isEnabled,
			!AppState.shared.isBrowsingMode
		else {
			return
		}

		// The schedule needs checking even when rotation is off, otherwise a website whose hours just ended stays up until something else happens. Once a minute is fine for something measured in hours.
		let interval = Defaults[.playlistInterval] ?? 60

		playlistTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				guard let self else {
					return
				}

				// Rotation used to be inferred from "is an interval set", which made it one answer for the
				// whole machine. It is this display's own mode now; the interval is still shared, because
				// how often is a much weaker preference than whether.
				let rotates = Defaults[.playlistInterval] != nil && self.rotationMode != .pinned

				self.advancePlaylist(rotating: rotates)
			}
		}
	}

	/**
	Move to whatever should be showing now.

	- Parameter rotating: `true` advances to the next website; `false` only corrects a website that has fallen out of its hours.
	*/
	private func advancePlaylist(rotating: Bool) {
		let controller = WebsitesController.shared

		if rotating {
			if self.rotationMode == .random {
				controller.makeRandomCurrent(on: display)
			} else {
				controller.advance(on: display)
			}
		}

		guard let next = controller.scheduled(for: display) else {
			return
		}

		guard next.id != website?.id else {
			return
		}

		controller.makeCurrent(next)
	}
}
