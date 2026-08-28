import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

/**
Opens the panel under the menu bar icon.

Either mouse button, and nothing else: the old right-click menu is gone, and `AppState` says why.
*/
@MainActor
final class DisplayPanelController {
	private let model = DisplayPanelModel()

	/**
	The subscriptions that say whether the panel can be seen. Live only while it is up.

	Held here rather than taken out once at init because the popover has no window until it is shown
	and is given a different one each time, so the occlusion notification below has nothing to name
	until then. Dropping them on close is also what keeps the panel from processing a notification per
	window per occlusion change for the entire life of the app, on a machine whose wallpaper windows
	are the ones changing.
	*/
	private var visibility = Set<AnyCancellable>()

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
		self?.visibility = []
		self?.model.stopLiveRefresh()
	}

	/**
	The window the popover is drawing in, or `nil` while it is down.

	Asked for rather than held: a popover has no window until it is shown, and does not keep the same
	one between showings.
	*/
	private var panelWindow: NSWindow? {
		popover.contentViewController?.view.window
	}

	/**
	Run the pictures only while somebody can see them.

	Closing the panel was the whole stop condition, and every dismissal route does reach
	`popoverDidClose` — but a transient popover self-closes on outside interaction and on nothing
	else. Lock the screen, let the displays sleep, switch Space or press Mission Control and the panel
	is still open with nobody in front of it, which is how the refresh loop came to go on photographing
	every display through a lock screen.

	Two signals, because neither of them answers for the other.

	The occlusion state is AppKit's own answer to "is any part of this window on screen", the same one
	App Nap is built on, and it is the only one of the two that covers Spaces and Mission Control. It
	is read off the window rather than tracked, so there is no second copy of it here to go stale.

	The screen lock is `SSEvents.isScreenLocked` — the app's existing lock signal, the very publisher
	that suspends the wallpapers themselves in `setUpEvents`. Reused rather than re-derived: the panel
	deciding for itself what a locked screen means is the shape of every defect `SwitchedOffTests`
	exists to keep out, and it is also the one case here that cannot be checked without locking a real
	screen — if occlusion turns out to cover the lock too, this is belt and braces at the cost of one
	subscription.

	The lock value is passed in rather than read back out of `AppState`, because this and `AppState`
	sink the same publisher and this one subscribes first: at the moment of locking, `isScreenLocked`
	over there has not been written yet. The occlusion path does read it, where a stale answer is
	harmless — a locked screen is an occluded window, so that path stops the loop on the occlusion
	alone and the lock sink arrives behind it with the same verdict.
	*/
	private func syncLiveRefresh(screenIsLocked: Bool) {
		guard
			let panelWindow,
			panelWindow.occlusionState.contains(.visible),
			!screenIsLocked
		else {
			model.stopLiveRefresh()
			return
		}

		model.startLiveRefresh()
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

		// Before the popover, and without waiting for anything. `columns` outlives a close, so the
		// pictures in it are of what the displays showed the last time the panel was up, and the view's
		// own `.task` runs after SwiftUI's first render — which is why a reopened panel used to spend
		// its first frames showing the previous opening's pages.
		//
		// Fetching the pictures first was tried and taken back out. It was correct on the first frame
		// and it cost 25-200ms between the click and anything at all appearing; a menu bar item that
		// does not open when it is clicked is the more expensive lie. This costs nothing measurable,
		// keeps the columns and their names, and leaves a placeholder where each picture will be once
		// the live refresh below has taken it — about a frame.
		model.prepareForOpening()

		popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)

		// Started outright rather than through `syncLiveRefresh`, and the panel is on screen because
		// the click that opened it landed on a menu bar nobody can reach through a lock screen. A
		// window's occlusion state is not promised to be settled in the same turn of the run loop as
		// the order-front that caused it, and asking it here would trade a defect nobody can see for
		// one everybody can: a panel of empty rectangles that never fills in.
		model.startLiveRefresh()

		guard let panelWindow else {
			return
		}

		NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: panelWindow)
			.sink { [weak self] _ in
				self?.syncLiveRefresh(screenIsLocked: AppState.shared.isScreenLocked)
			}
			.store(in: &visibility)

		SSEvents.isScreenLocked
			.sink { [weak self] in
				self?.syncLiveRefresh(screenIsLocked: $0)
			}
			.store(in: &visibility)
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
