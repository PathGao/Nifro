import AppKit
import KeyboardShortcuts
import SwiftUI

/**
Opens the panel under the menu bar icon.

Either mouse button, and nothing else: the old right-click menu is gone, and `AppState` says why.
*/
@MainActor
final class DisplayPanelController {
	private let model = DisplayPanelModel()

	init() {
		model.onClose = { [weak self] in
			self?.popover.performClose(nil)
		}
	}

	private lazy var popover = with(NSPopover()) {
		$0.behavior = .transient
		$0.animates = false
		$0.delegate = closeWatcher
		$0.contentViewController = NSHostingController(rootView: DisplayPanel(model: model))
	}

	private lazy var closeWatcher = CloseWatcher { [weak self] in
		// Put back what showing the panel took away.
		KeyboardShortcuts.enable(Shortcut.allNames)
		self?.model.stopLiveRefresh()
	}

	/**
	Show the panel under `button`, or put it away if it is already up.
	*/
	func toggle(relativeTo button: NSStatusBarButton) {
		guard !popover.isShown else {
			popover.performClose(nil)
			return
		}

		// The panel has its own buttons and its own menus, and a global shortcut firing while somebody
		// is aiming at one of them acts on the wallpaper behind it. The menu this replaces did the same
		// thing for the same reason.
		KeyboardShortcuts.disable(Shortcut.allNames)

		// An accessory app has no active application to hand the popover keyboard focus, so without
		// this the panel comes up behind whatever the user was working in.
		SSApp.forceActivate()

		popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
		model.startLiveRefresh()
	}
}


/**
Tells the controller when the panel goes away.

A popover closes on its own — clicking elsewhere, pressing Escape — so "it is gone" cannot be
inferred from the thing that opened it.
*/
private final class CloseWatcher: NSObject, NSPopoverDelegate {
	private let onClose: () -> Void

	init(onClose: @escaping () -> Void) {
		self.onClose = onClose
	}

	func popoverDidClose(_ notification: Notification) {
		onClose()
	}
}
