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
					snapshot: await scene.snapshot()
				)
			)
		}

		columns = built
	}

	/**
	The websites that can go on `display`.

	A website belongs to one display, so this is the list that display already owns — the panel points
	a display at one of its own, it does not move websites between displays. That is what the website's
	own settings are for.
	*/
	func choices(for display: Display?) -> [Website] {
		WebsitesController.shared.all.filter { $0.effectiveDisplay == display }
	}

	/**
	Show `websiteID` on `display`.
	*/
	func show(_ websiteID: Website.ID?, on display: Display?) {
		guard
			let websiteID,
			let website = WebsitesController.shared.all[id: websiteID]
		else {
			return
		}

		WebsitesController.shared.makeCurrent(website)
	}
}
