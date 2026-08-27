import AppKit
import SwiftUI

/**
What the panel draws, and the one place it is assembled.

Held apart from the view because the snapshots are asynchronous and the scenes are not: this waits
for the pictures and the columns arrive together, rather than popping in one at a time.

Held apart from the view because it also outlives it. The panel is one popover shown over and over,
and the columns it last drew are still here when it comes back — which is what lets a reopening start
at the right size instead of growing into it, and is also why `prepareForOpening` exists. The
pictures in those columns are the one part of them that must not be reused.
*/
@MainActor
final class DisplayPanelModel: ObservableObject {
	struct Column: Identifiable {
		let display: Display?
		let displayName: String
		let websiteID: Website.ID?
		let websiteName: String?
		let snapshot: NSImage?

		/**
		The websites this display owns.

		Carried on the column rather than looked up by the view, so a column is a finished description
		of one display and the view has nothing left to ask.
		*/
		let choices: [Website]

		/**
		Everything this display's controls need to draw themselves.
		*/
		let isShowing: Bool
		let isMuted: Bool
		let rotationMode: RotationMode

		/**
		How long this display waits between websites. Only shown while it is actually rotating.
		*/
		let rotationIntervalMinutes: Double

		let canRotate: Bool

		/**
		Whether a page is on its way to this display.

		Per display, not per app. A load takes a few seconds, and locking the panel for all of them
		because one screen is fetching a page would make the other screen's controls unusable for
		something that is none of its business.
		*/
		let isLoading: Bool

		// `nil` display means the main display — the one with the menu bar, not a display named in any
		// setting — and there is only ever one of those, so the display's own id is the identity when it
		// has one and a fixed stand-in when it does not.
		var id: String { display?.id.uuidString ?? "default" }
	}

	@Published private(set) var columns: [Column] = []

	private var liveRefresh: Task<Void, Never>?

	/**
	Which opening of the panel the columns belong to.

	A snapshot is awaited, so a `refresh` begun for one opening can finish after the panel has been
	closed and opened again. Counting the openings is how a late arrival finds out it is late.
	*/
	private var openings = 0

	/**
	Keep the pictures moving while the panel is up.

	A single snapshot on open makes a wallpaper look like a screenshot of itself, which is the wrong
	thing to show for a page whose whole point is that it moves. A snapshot costs a few tens of
	milliseconds and this is a popover that closes the moment attention goes elsewhere, so it can
	afford a few a second — and it stops the instant it closes, which is the part that matters. Nothing
	here runs while nobody is looking.
	*/
	func startLiveRefresh() {
		liveRefresh?.cancel()

		liveRefresh = Task { [weak self] in
			while !Task.isCancelled {
				await self?.refresh()

				// After the work rather than before it, so a slow refresh spaces itself out instead of
				// queueing up behind the last one.
				try? await Task.sleep(for: .milliseconds(80))
			}
		}
	}

	func stopLiveRefresh() {
		liveRefresh?.cancel()
		liveRefresh = nil
	}

	/**
	Everything the panel opens with except the pictures.

	Synchronous, and that is the whole point of it. Every field of a column but the snapshot is a value
	already sitting in memory, so this costs nothing worth measuring. The snapshot is the one part that
	has to be photographed, at a measured 12.5ms a display, and photographing every display before the
	popover appears is a menu bar item that does not open for up to a fifth of a second after the click.

	So the panel opens on the click at the right size with the right names, and a bare rectangle stands
	in for each picture until the first refresh fills it in about a frame later. What it replaces is the
	pictures the columns are still holding, which are of what the displays showed the last time the
	panel was up: a real photograph of a real page, which is exactly why nobody reads it as stale.
	*/
	func prepareForOpening() {
		// Before the columns are rebuilt rather than after, so a snapshot already in the air for the
		// previous opening cannot land on top of what this just put up. `refresh` writes `columns` at
		// the end, after its awaits.
		openings += 1

		let websites = WebsitesController.shared.all
		columns = AppState.shared.scenes.map { column(for: $0, snapshot: nil, websites: websites) }
	}

	/**
	Rebuild every column, pictures included.

	One after another rather than at once. A snapshot is a copy of a view that already exists, so it
	costs milliseconds, and a machine with more displays than that is not the case this is written for.
	*/
	func refresh() async {
		let opening = openings
		var built: [Column] = []

		// Read once for the whole pass rather than once per column. `all` is `Defaults[.websites]`,
		// which decodes the entire list on every read, and every column then resolves
		// `effectiveDisplay` for every website in it — so this ran at the panel's refresh rate,
		// multiplied by the number of displays. The columns are published together as one array
		// anyway, so one read is also the only way they can agree with each other.
		let websites = WebsitesController.shared.all

		for scene in AppState.shared.scenes {
			built.append(column(for: scene, snapshot: await scene.snapshot(), websites: websites))
		}

		// The panel was closed and opened again while these were being taken, so they are pictures of
		// the previous opening and `prepareForOpening` has already put the right thing up. Dropping them
		// is the difference between a placeholder that fills in and a stale photograph that comes back.
		guard opening == openings else {
			return
		}

		columns = built
	}

	/**
	One display, described.

	The two things a column costs are both passed in. The snapshot because it has to be photographed:
	the panel is opened with `nil` and the refreshes fill it in. The website list because reading it
	decodes every website, and one pass builds a column per display off the same list.
	*/
	private func column(for scene: WallpaperScene, snapshot: NSImage?, websites: [Website]) -> Column {
		// `effectiveDisplay` asks CoreGraphics for a display's identity and walks `NSScreen.screens`,
		// so the answer costs something and every website in the list is asked. Once per column.
		let onDisplay = websites.filter { $0.effectiveDisplay == scene.display }

		return Column(
			display: scene.display,
			displayName: scene.display?.localizedName ?? String(localized: "Main Display"),
			websiteID: scene.website?.id,
			websiteName: scene.website?.menuTitle.nilIfEmpty,
			snapshot: snapshot,
			choices: onDisplay,
			// `isSwitchedOff`, not the per-display switch under it. The column was the last reader
			// asking one of the two switches on its own, so with the app disabled — on battery, on a
			// locked screen, from the Disable shortcut — every wallpaper was gone and every column still
			// read "on". The button below then acted on that reading and switched the display off for
			// real, so turning the app back on brought back a screen the user had never switched off.
			isShowing: !scene.isSwitchedOff,
			isMuted: !scene.shouldPlaySound,
			rotationMode: scene.rotationMode,
			rotationIntervalMinutes: scene.rotationIntervalMinutes,
			// One website has nothing to rotate to, and a control that does nothing should say so
			// rather than shrug when pressed.
			canRotate: onDisplay.count > 1,
			isLoading: scene.isLoading
		)
	}


	func toggleBrowsingMode(on display: Display?) {
		AppState.shared.setBrowsingMode(!AppState.shared.isBrowsingMode(on: display), on: display)
	}

	/**
	Start framing the region shown on `display`.

	The panel closes first. Framing is a full-screen gesture against the wallpaper, and a popover
	sitting over it would be in the way of the thing being framed.
	*/
	func chooseRegion(on display: Display?) {
		guard
			let scene = AppState.shared.scenes.first(where: { $0.display == display }),
			let website = scene.website
		else {
			return
		}

		onClose?()
		WebsitesController.shared.makeCurrent(website)
		AppState.shared.beginCropSelection(on: scene)
	}

	/**
	Close the panel, then do the thing.

	In that order, and always: every one of these opens a window, and a popover left up in front of the
	window it just opened is the panel getting in the way of what it was asked for.
	*/
	func run(_ action: @escaping () -> Void) {
		onClose?()
		action()
	}

	/**
	Put the panel away. Set by whatever is showing it.
	*/
	var onClose: (() -> Void)?

	/**
	Everything a column's controls do, each one naming the display it acts on.

	The display is passed rather than assumed. That is the whole point of the panel: the menu it
	replaces had no way to say which screen it meant, so every action went to whichever one last held
	a flag.
	*/
	func step(_ direction: Step, on display: Display?) {
		// Stepping a display that is switched off is how you wake it, and something does appear on it —
		// so the switch has to agree. It used to light up with a website while still reading as off.
		if AppState.shared.scenes.first(where: { $0.display == display })?.isDisabledForDisplay == true {
			AppState.shared.setDisplayEnabled(true, on: display)
		}

		switch direction {
		case .previous:
			WebsitesController.shared.makePreviousCurrent(on: display)
		case .next:
			WebsitesController.shared.makeNextCurrent(on: display)
		}

		Task {
			await refresh()
		}
	}

	enum Step {
		case previous
		case next
	}

	func cycleRotationMode(on display: Display?) {
		guard let scene = AppState.shared.scenes.first(where: { $0.display == display }) else {
			return
		}

		scene.rotationMode = scene.rotationMode.next
		scene.resetPlaylistTimer()
		objectWillChange.send()

		Task {
			await refresh()
		}
	}

	/**
	Set how many minutes `display` waits between websites.

	The number is put through `rotationInterval(entered:current:)` on the way in rather than trusted:
	this is a text field, so "0", "-3" and a number with nine digits in it are all one keystroke away,
	and each of them means a display that never changes again.

	No `resetPlaylistTimer` here — writing the key is what restarts the timers, through the publisher
	in `Events`, which also catches the same number being changed from anywhere else.
	*/
	func setRotationInterval(_ minutes: Double, on display: Display?) {
		guard let scene = AppState.shared.scenes.first(where: { $0.display == display }) else {
			return
		}

		scene.rotationIntervalMinutes = rotationInterval(entered: minutes, current: scene.rotationIntervalMinutes)
		objectWillChange.send()

		Task {
			await refresh()
		}
	}

	func toggleMuted(on display: Display?) {
		guard
			let scene = AppState.shared.scenes.first(where: { $0.display == display }),
			let website = scene.website
		else {
			return
		}

		WebsitesController.shared.update(website.id) {
			$0.audio = $0.audio == .unmuted ? .muted : .unmuted
		}

		Task {
			await refresh()
		}
	}

	func toggleShowing(on display: Display?) {
		guard let scene = AppState.shared.scenes.first(where: { $0.display == display }) else {
			return
		}

		// The same answer the column drew, so pressing the button means what the button says. Read off
		// the per-display switch it would have written the opposite of what a user pressing "on" while
		// the app was disabled had asked for.
		//
		// Switching a display on while the app is off records the setting and leaves the screen dark —
		// `setDisplayEnabled` says so, and it is the only honest answer available here: this button
		// cannot clear a Disable that came from the battery or the lock screen.
		AppState.shared.setDisplayEnabled(scene.isSwitchedOff, on: display)

		Task {
			await refresh()
		}
	}

	/**
	Show the website with `websiteID`.

	No display argument: a website belongs to one display already, and `makeCurrent` marks it per
	display, so passing one in would be a second opinion about something the website settles.
	*/
	func show(_ websiteID: Website.ID) {
		guard let website = WebsitesController.shared.all[id: websiteID] else {
			return
		}

		WebsitesController.shared.makeCurrent(website)
	}
}
