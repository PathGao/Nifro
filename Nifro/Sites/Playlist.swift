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
		let onDisplay = all.filter { $0.effectiveDisplay == display }
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

		let currentIndex = candidates.firstIndex { $0.isCurrent } ?? -1
		let next = candidates[(currentIndex + 1) % candidates.count]

		makeCurrent(next)

		return next
	}

	/**
	The website that should be showing on `display` right now, taking the schedule into account.
	*/
	fileprivate func scheduled(for display: Display?, at date: Date = .now) -> Website? {
		let candidates = eligible(for: display, at: date)
		return candidates.first { $0.isCurrent } ?? candidates.first
	}
}

extension WallpaperScene {
	/**
	Start, restart or stop this scene's rotation to match the current settings.
	*/
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
				self?.advancePlaylist(rotating: Defaults[.playlistInterval] != nil)
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
			controller.advance(on: display)
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
