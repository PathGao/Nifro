import AppKit
import SwiftUI

/**
Opens the panel under the menu bar icon.

The old menu is still there on a right-click, and stays until the panel carries everything it does.
Replacing it in one move would mean a build where the panel is the only way in and half the actions
have nowhere to live.
*/
@MainActor
final class DisplayPanelController {
	private let model = DisplayPanelModel()

	private lazy var popover = with(NSPopover()) {
		$0.behavior = .transient
		$0.animates = false
		$0.contentViewController = NSHostingController(rootView: DisplayPanel(model: model))
	}

	var isShown: Bool { popover.isShown }

	/**
	Show the panel under `button`, or put it away if it is already up.
	*/
	func toggle(relativeTo button: NSStatusBarButton) {
		guard !popover.isShown else {
			popover.performClose(nil)
			return
		}

		// An accessory app has no active application to hand the popover keyboard focus, so without
		// this the panel comes up behind whatever the user was working in.
		SSApp.forceActivate()

		popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)

		// Fresh pictures every time it opens. A wallpaper that moves would otherwise be shown as it
		// looked the first time anybody looked.
		Task {
			await model.refresh()
		}
	}
}
