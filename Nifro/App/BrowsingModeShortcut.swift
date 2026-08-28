import AppKit
import KeyboardShortcuts

/**
One key for Browsing Mode: hold it to use the page while it is down, tap it to leave the page usable.

These were two shortcuts, and the split was the mistake. Both do the same thing to the same display
and differ only in how long you want it — so the user had to pick a second key combination, remember
which was which, and the Settings list spent two rows saying "Browsing Mode" twice. How long a key is
held is something the key can answer for itself.

Holding is the one that gets the direct path. Browsing Mode as a toggle assumes you want to work in
the page for a while; most of the time you want the opposite — click one thing, scroll a little, and
have the wallpaper go back to being a wallpaper without having to remember to turn it off. The
wallpaper is interactive exactly as long as your finger is down.

Leaving on key up alone is not enough. A shortcut has modifiers, and releasing the modifier before the
key means the hotkey's key-up never arrives, which would strand the wallpaper in front of everything.
So a released modifier ends the hold too.
*/
@MainActor
final class BrowsingModeShortcut {
	/**
	How long the key has to stay down before it counts as a hold rather than a tap.

	Apple's own number, and it is the same number twice: `NSPressGestureRecognizer`,
	`UILongPressGestureRecognizer` and SwiftUI's `onLongPressGesture` all default to half a second, and
	stock "Delay Until Repeat" — the moment macOS itself decides a key is being held down rather than
	typed — reports 0.5 s through `NSEvent.keyRepeatDelay`.

	Not read from `keyRepeatDelay` at run time, though it would follow the user's own tuning. That
	setting answers how fast they want text to repeat, which is a different question, and someone who
	set it short to type quickly would find every tap here turning into a hold. No setting of its own
	either, for now: a second number to explain, in service of a threshold nobody has yet said is
	wrong.
	*/
	private static let holdThreshold = Duration.milliseconds(500)

	private var pendingHold: Task<Void, Never>?
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
		KeyboardShortcuts.onKeyDown(for: Shortcut.browsingMode.name) { [weak self] in
			self?.keyDown()
		}

		KeyboardShortcuts.onKeyUp(for: Shortcut.browsingMode.name) { [weak self] in
			self?.keyUp()
		}
	}

	private func keyDown() {
		guard pendingHold == nil, !isHolding else {
			return
		}

		requiredModifiers = KeyboardShortcuts.getShortcut(for: Shortcut.browsingMode.name)?.modifiers ?? []

		pendingHold = Task { [weak self] in
			try? await Task.sleep(for: Self.holdThreshold)

			guard !Task.isCancelled else {
				return
			}

			self?.begin()
		}
	}

	private func keyUp() {
		guard !isHolding else {
			end()
			return
		}

		pendingHold?.cancel()
		pendingHold = nil

		// The whole press was shorter than the threshold, so it was a tap. Through `Action` rather than
		// straight to `setBrowsingMode` because the shared verb underneath it carries the first-time
		// explanation, and this is the same toggle the panel button and `nifro://` run.
		Action.toggleBrowsingMode.run(from: .pointer)
	}

	private func begin() {
		pendingHold = nil

		let scene = AppState.shared.actingScene

		guard
			// The key-up for a hotkey never arrives when the modifiers go up first, so the press can
			// already be over by the time the threshold lands. Entering the hold then would leave the
			// wallpaper in front with nothing at all to put it back; the press is spent as a tap instead,
			// which is at least visible and undone by the same key.
			NSEvent.modifierFlags.contains(requiredModifiers),
			// This display is already browsing for another reason — the panel's button, an earlier tap.
			// Ending the hold must not cancel that. Asked of the display the hold is about to act on and
			// not of the app: with the app-wide question here, holding the key over the monitor did
			// nothing at all whenever the laptop happened to be browsing.
			!AppState.shared.isBrowsingMode(on: scene.display)
		else {
			Action.toggleBrowsingMode.run(from: .pointer)
			return
		}

		isHolding = true
		holdingScene = scene
		AppState.shared.setBrowsingMode(true, on: scene.display)

		watchForReleasedModifiers()
	}

	private func end() {
		guard isHolding else {
			return
		}

		isHolding = false
		stopWatchingModifiers()

		// Here rather than in `begin()`, which is where every other route says it — and the difference
		// is the key. An `NSAlert` is app-modal: it runs a run loop of its own until somebody clicks it,
		// and the hold has exactly two ways out, the Carbon key-up and the local `.flagsChanged`
		// monitor above. A modal session filtering or delaying either one leaves `end()` unreachable
		// with the wallpaper raised over the desktop icons, taking the clicks meant for them, and the
		// hotkey refusing to help because it sees the display already browsing. That is the state this
		// whole class is built to make unreachable, so the explanation waits until the hold is over
		// rather than being raised in the middle of it.
		//
		// Above the guard below, because a hold whose display was unplugged is still a hold somebody
		// made and still the first time they saw Browsing Mode.
		AppState.shared.explainBrowsingModeOnce()

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
