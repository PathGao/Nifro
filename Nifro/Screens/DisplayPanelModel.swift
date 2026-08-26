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
		let syncTargets: [(display: Display?, name: String, isSynced: Bool)]

		// `nil` display means "whatever Settings says", and there is only ever one of those, so the
		// display's own id is the identity when it has one and a fixed stand-in when it does not.
		var id: String { display?.id.uuidString ?? "default" }
	}

	@Published private(set) var columns: [Column] = []

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
					isMuted: scene.website?.audio != .unmuted,
					rotationMode: scene.rotationMode,
					// One website has nothing to rotate to, and a control that does nothing should say so
					// rather than shrug when pressed.
					canRotate: WebsitesController.shared.all.count { $0.effectiveDisplay == scene.display } > 1,
					syncTargets: syncTargets(for: scene.display)
				)
			)
		}

		columns = built
	}

	/**
	Every other display, and whether this one is already synced with it.

	Every other display rather than every other group: a display already in a group appears once per
	member, all of them ticked, because "sync with the monitor" and "sync with the group the monitor is
	in" are the same act and only one of them is a phrase anybody would say.
	*/
	private func syncTargets(for display: Display?) -> [(display: Display?, name: String, isSynced: Bool)] {
		let peers = Set(SyncGroup.peers(of: display).map { Display.settingsKey(for: $0) })

		return AppState.shared.scenes
			.map(\.display)
			.filter { Display.settingsKey(for: $0) != Display.settingsKey(for: display) }
			.map {
				(
					display: $0,
					name: $0?.localizedName ?? String(localized: "Main Display"),
					isSynced: peers.contains(Display.settingsKey(for: $0))
				)
			}
	}

	/**
	Sync `display` with `other`, or unsync it if they already are.
	*/
	func toggleSync(_ display: Display?, with other: Display?) {
		if SyncGroup.peers(of: display).contains(where: { Display.settingsKey(for: $0) == Display.settingsKey(for: other) }) {
			SyncGroup.leave(display)
		} else {
			SyncGroup.join(display, with: other)
			WebsitesController.shared.mirrorAcrossSyncGroup(from: other)
		}

		MediaSync.forgetQuietPeriods()
		MediaSync.restart()

		Task {
			await refresh()
		}
	}

	/**
	Whether Browsing Mode is on.

	App-wide, unlike everything else here: it moves the wallpaper window above the desktop icons and
	takes keyboard focus, and doing that to one screen while the others stay behind is not a state the
	window levels can express. The button appears per column because that is where the user is looking,
	not because the answer differs per display.
	*/
	var isBrowsingMode: Bool { AppState.shared.isBrowsingMode }

	func toggleBrowsingMode() {
		Action.toggleBrowsingMode.run()
		objectWillChange.send()
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
		AppState.shared.beginCropSelection()
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
