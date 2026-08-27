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

	func install() {
		KeyboardShortcuts.onKeyDown(for: Shortcut.holdToInteract.name) { [weak self] in
			self?.begin()
		}

		KeyboardShortcuts.onKeyUp(for: Shortcut.holdToInteract.name) { [weak self] in
			self?.end()
		}
	}

	private func begin() {
		guard
			!isHolding,
			// Already browsing for another reason. Ending the hold must not cancel that.
			!AppState.shared.isBrowsingMode
		else {
			return
		}

		isHolding = true
		requiredModifiers = KeyboardShortcuts.getShortcut(for: Shortcut.holdToInteract.name)?.modifiers ?? []
		AppState.shared.setBrowsingMode(true, on: AppState.shared.actingScene.display)

		watchForReleasedModifiers()
	}

	private func end() {
		guard isHolding else {
			return
		}

		isHolding = false
		stopWatchingModifiers()
		AppState.shared.setBrowsingMode(false, on: AppState.shared.actingScene.display)
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
