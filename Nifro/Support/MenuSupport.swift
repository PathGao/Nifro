import SwiftUI


final class CallbackMenuItem: NSMenuItem {
	@MainActor private static var validateCallback: ((NSMenuItem) -> Bool)?


	private let callback: () -> Void

	init(
		_ title: String,
		key: String = "",
		keyModifiers: NSEvent.ModifierFlags? = nil,
		isEnabled: Bool = true,
		isChecked: Bool = false,
		isHidden: Bool = false,
		action: @escaping () -> Void
	) {
		self.callback = action
		super.init(title: title, action: #selector(action(_:)), keyEquivalent: key)
		self.target = self
		self.isEnabled = isEnabled
		self.isChecked = isChecked
		self.isHidden = isHidden

		if let keyModifiers {
			self.keyEquivalentModifierMask = keyModifiers
		}
	}

	@available(*, unavailable)
	required init(coder decoder: NSCoder) {
		fatalError(because: .notYetImplemented)
	}
}

extension CallbackMenuItem {
	// Reached through `#selector` in the initialiser above; nothing references it by name.
	@objc
	private func action(_: NSMenuItem) {
		callback()
	}
}

extension CallbackMenuItem: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		Self.validateCallback?(menuItem) ?? true
	}
}


extension NSMenuItem {
	var isChecked: Bool {
		get { state == .on }
		set {
			state = newValue ? .on : .off
		}
	}
}


extension NSMenu {
	func addSeparator() {
		addItem(.separator())
	}


	@discardableResult
	func addCallbackItem(
		_ title: String,
		key: String = "",
		keyModifiers: NSEvent.ModifierFlags? = nil,
		isEnabled: Bool = true,
		isChecked: Bool = false,
		isHidden: Bool = false,
		action: @escaping () -> Void
	) -> NSMenuItem {
		let menuItem = CallbackMenuItem(
			title,
			key: key,
			keyModifiers: keyModifiers,
			isEnabled: isEnabled,
			isChecked: isChecked,
			isHidden: isHidden,
			action: action
		)
		addItem(menuItem)
		return menuItem
	}
}



//@MainActor
private final class ActionTrampoline {
	fileprivate let action: (NSEvent) -> Void

	init(action: @escaping (NSEvent) -> Void) {
		self.action = action
	}

	// Reached through `#selector`, which no static analysis can see. Deleting it compiles fine and breaks every control callback at runtime.
	@objc
	fileprivate func handleAction(_: AnyObject) {
		action(NSApp.currentEvent!)
	}
}

// Only ever used as an address for `objc_setAssociatedObject`; the value itself is never read.
nonisolated(unsafe) private var controlActionClosureProtocolAssociatedObjectKey: UInt8 = 0

extension ControlActionClosureProtocol {
	var onAction: ((NSEvent) -> Void)? {
		get {
			guard
				let trampoline = objc_getAssociatedObject(self, &controlActionClosureProtocolAssociatedObjectKey) as? ActionTrampoline
			else {
				return nil
			}

			return trampoline.action
		}
		set {
			guard let newValue else {
				objc_setAssociatedObject(self, &controlActionClosureProtocolAssociatedObjectKey, nil, .OBJC_ASSOCIATION_RETAIN)
				return
			}

			let trampoline = ActionTrampoline(action: newValue)
			target = trampoline
			action = #selector(ActionTrampoline.handleAction)
			objc_setAssociatedObject(self, &controlActionClosureProtocolAssociatedObjectKey, trampoline, .OBJC_ASSOCIATION_RETAIN)
		}
	}
}
extension NSMenuItem: ControlActionClosureProtocol {}


extension NSMenuItem {
}

extension NSStatusBarButton {
	private static let activityAnimationKey = "nifro.activity"

	/**
	Pulse the menu bar icon while a page is on its way.

	Motion rather than a second static appearance, because the static one is taken: `appearsDisabled`
	already means the wallpaper is off, and that is the convention menu bar apps follow — a paused
	state does not move, a working one does. Reusing it would have made "off" and "busy" look alike.

	Subtle and short-lived: it runs only while a page is being fetched, which is seconds, and this is
	an icon somebody chose to keep in their menu bar rather than a progress bar demanding attention.

	This was briefly deleted in favour of the panel's chooser saying the same thing per column, which
	is the better report when the panel is open — it names the display, which this cannot. The panel is
	closed almost all the time. Switching website from a keyboard shortcut, from rotation, from the
	Websites window or from a Shortcuts intent left nothing on screen saying anything at all, for the
	several seconds the desktop deliberately does not change. So both say it, and they say it at the
	same cadence — `WallpaperScene.loadingPulseDuration`, which the panel's chooser animates on too.
	They are CoreAnimation and SwiftUI and cannot share a clock, so they will not be in phase; matching
	the duration and the easing is what makes them read as one thing happening rather than two.

	Safe to call with the same value repeatedly, which is what the choke point driving it does: turning
	it on while it is already running leaves the animation where it is rather than restarting it, so a
	second display beginning a load does not make the icon jump.

	`wantsLayer` below is not what gives the button a layer, and leaving it set does not change how the
	icon draws. It reads suspicious — a flag set once and never cleared, on a view the system renders —
	and the first load of every session now reaches it, where before only a website switch did. So it
	was measured rather than argued about: a build with that line deleted still reports `layer != nil`
	on this button by the time anything asks, because the status bar window and the button's superview
	are both layer-backed and AppKit gives every descendant of a layer-backed host its own layer. The
	line asserts what is already true. The button's own rendering is byte-identical with the flag on,
	off, and forced back off after a pulse, and the pulse leaves `alphaValue` and `layer.opacity` at 1
	with no animation attached.
	*/
	func setShowingActivity(_ isShowingActivity: Bool) {
		guard isShowingActivity else {
			layer?.removeAnimation(forKey: Self.activityAnimationKey)
			return
		}

		wantsLayer = true

		guard layer?.animation(forKey: Self.activityAnimationKey) == nil else {
			return
		}

		let pulse = CABasicAnimation(keyPath: "opacity")
		pulse.fromValue = 1
		pulse.toValue = 0.4
		pulse.duration = WallpaperScene.loadingPulseDuration
		pulse.autoreverses = true
		pulse.repeatCount = .infinity
		pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

		layer?.add(pulse, forKey: Self.activityAnimationKey)
	}
}
