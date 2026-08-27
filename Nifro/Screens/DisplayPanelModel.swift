import AppKit
import SwiftUI

/**
What the panel draws, and the one place it is assembled.

Held apart from the view because the snapshots are asynchronous and the scenes are not: the view asks
once when it appears, this waits for the pictures, and the columns arrive together rather than
popping in one at a time.
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
		let canRotate: Bool

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

		// `nil` display means "whatever Settings says", and there is only ever one of those, so the
		// display's own id is the identity when it has one and a fixed stand-in when it does not.
		var id: String { display?.id.uuidString ?? "default" }
	}

	@Published private(set) var columns: [Column] = []

	private var liveRefresh: Task<Void, Never>?

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
	Rebuild every column, pictures included.

	One after another rather than at once. A snapshot is a copy of a view that already exists, so it
	costs milliseconds, and a machine with more displays than that is not the case this is written for.
	*/
	func refresh() async {
		var built: [Column] = []

		for scene in AppState.shared.scenes {
			built.append(
				Column(
					display: scene.display,
					displayName: scene.display?.localizedName ?? String(localized: "Main Display"),
					websiteID: scene.website?.id,
					websiteName: scene.website?.menuTitle.nilIfEmpty,
					snapshot: await scene.snapshot(),
					choices: WebsitesController.shared.all.filter { $0.effectiveDisplay == scene.display },
					isShowing: !scene.isDisabledForDisplay,
					isMuted: !scene.shouldPlaySound,
					rotationMode: scene.rotationMode,
					// One website has nothing to rotate to, and a control that does nothing should say so
					// rather than shrug when pressed.
					canRotate: WebsitesController.shared.all.count { $0.effectiveDisplay == scene.display } > 1,
					syncOptions: syncOptions(for: scene.display),
					isFollowing: SyncGroup.leader(of: scene.display) != nil
				)
			)
		}

		columns = built
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

	/**
	Act on one entry of the sync menu.
	*/
	func apply(_ option: SyncOption, on display: Display?) {
		switch option {
		case .follow(let other, _):
			SyncGroup.follow(display, following: other)
			WebsitesController.shared.mirrorAcrossSyncGroup(from: other)
		case .unfollow:
			SyncGroup.leave(display)
		case .releaseAll:
			SyncGroup.releaseFollowers(of: display)
		}

		MediaSync.forgetQuietPeriods()
		MediaSync.restart()

		// Who is audible is a property of the group, so it changes when the group does.
		AppState.shared.applyAudioSetting()

		Task {
			await refresh()
		}
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

		AppState.shared.setDisplayEnabled(scene.isDisabledForDisplay, on: display)

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
