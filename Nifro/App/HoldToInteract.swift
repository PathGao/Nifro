import AppKit
import KeyboardShortcuts

/**
Hold a key to use the page, let go to put it back.

Browsing Mode as a toggle assumes you want to work in the page for a while. Most of the time you
want the opposite: click one thing, scroll a little, zoom in, and have the wallpaper go back to
being a wallpaper without having to remember to turn it off. Holding a key matches that. The wallpaper
is interactive exactly as long as your finger is down.

Leaving on key up alone is not enough. A shortcut has modifiers, and releasing the modifier before
the key means the hotkey's key-up never arrives, which would strand the wallpaper in front of
everything. So a released modifier ends the hold too.
*/
@MainActor
final class HoldToInteract {
	private var isHolding = false
	private var requiredModifiers: NSEvent.ModifierFlags = []
	private var flagsMonitor: Any?

	/**
	The scene the hold started on, so letting go acts on the thing that started it.

	Both ends used to resolve the display for themselves, from `Display.underMouse` at their own
	moment. Those are different moments by definition — the hold is exactly the time in between — so
	moving the pointer to the other screen before letting go, which is the natural motion after
	scrolling a wallpaper and going back to your editor, turned Browsing Mode *on* for one display and
	*off* for another. The first display was then left interactive with nothing to switch it off but
	the panel's own button: raised over its desktop icons, taking clicks meant for them, and the hotkey
	itself refused to help because pressing it again saw a display already browsing.

	It is also the answer to the pointer being nowhere at release — displays reconfiguring, every
	screen asleep — which used to fall back to `primaryScene` and switch off a display that had never
	been switched on. Nothing is resolved at release any more, so there is nothing to fall back from.

	The same fix `croppingScene` is, for the same reason, and weak for the same reason: a scene torn
	down with its display reads as gone rather than as some other scene. Nothing is owed to a display
	that left — `rebuildScenes` clears its Browsing Mode as it goes.
	*/
	private weak var holdingScene: WallpaperScene?

	func install() {
		KeyboardShortcuts.onKeyDown(for: Shortcut.holdToInteract.name) { [weak self] in
			self?.begin()
		}

		KeyboardShortcuts.onKeyUp(for: Shortcut.holdToInteract.name) { [weak self] in
			self?.end()
		}
	}

	private func begin() {
		let scene = AppState.shared.actingScene

		guard
			!isHolding,
			// This display is already browsing for another reason — the panel's button, the toggle
			// shortcut. Ending the hold must not cancel that. Asked of the display the hold is about to
			// act on and not of the app: with the app-wide question here, holding the key over the
			// monitor did nothing at all whenever the laptop happened to be browsing.
			!AppState.shared.isBrowsingMode(on: scene.display)
		else {
			return
		}

		isHolding = true
		holdingScene = scene
		requiredModifiers = KeyboardShortcuts.getShortcut(for: Shortcut.holdToInteract.name)?.modifiers ?? []
		AppState.shared.setBrowsingMode(true, on: scene.display)

		watchForReleasedModifiers()
	}

	private func end() {
		guard isHolding else {
			return
		}

		isHolding = false
		stopWatchingModifiers()

		// Optional and not substituted for: the scene went away with its display, which took its
		// Browsing Mode with it, so there is nothing to put back and no other display that should be
		// put back in its place.
		guard let scene = holdingScene else {
			return
		}

		holdingScene = nil
		AppState.shared.setBrowsingMode(false, on: scene.display)
	}

	/**
	End the hold if the modifiers stop being held, even when no key-up arrives for the combination.

	A local monitor is enough because entering the hold brings the app forward, so the events land
	here. It also needs no Accessibility permission, which a global monitor would.
	*/
	private func watchForReleasedModifiers() {
		guard !requiredModifiers.isEmpty else {
			return
		}

		flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
			guard let self else {
				return event
			}

			if !event.modifierFlags.contains(requiredModifiers) {
				end()
			}

			return event
		}
	}

	private func stopWatchingModifiers() {
		guard let flagsMonitor else {
			return
		}

		NSEvent.removeMonitor(flagsMonitor)
		self.flagsMonitor = nil
	}
}
