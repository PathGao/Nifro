import SwiftUI


final class SSMenu: NSMenu, NSMenuDelegate {
	var onUpdate: (() -> Void)?

	private(set) var isOpen = false

	override init(title: String) {
		super.init(title: title)
		self.delegate = self
		self.autoenablesItems = false
	}

	@available(*, unavailable)
	required init(coder decoder: NSCoder) {
		fatalError(because: .notYetImplemented)
	}

	func menuWillOpen(_ menu: NSMenu) {
		isOpen = true
	}

	func menuDidClose(_ menu: NSMenu) {
		isOpen = false
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		onUpdate?()
	}
}


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
	private func action(_ sender: NSMenuItem) {
		callback()
	}
}

extension CallbackMenuItem: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		Self.validateCallback?(menuItem) ?? true
	}
}


extension NSMenuItem {
	convenience init(
		_ title: String,
		key: String = "",
		keyModifiers: NSEvent.ModifierFlags? = nil,
		isEnabled: Bool = true,
		isChecked: Bool = false,
		isHidden: Bool = false
	) {
		self.init(title: title, action: nil, keyEquivalent: key)
		self.isEnabled = isEnabled
		self.isChecked = isChecked
		self.isHidden = isHidden

		if let keyModifiers {
			self.keyEquivalentModifierMask = keyModifiers
		}
	}

	convenience init(
		_ attributedTitle: NSAttributedString,
		key: String = "",
		keyModifiers: NSEvent.ModifierFlags? = nil,
		isEnabled: Bool = true,
		isChecked: Bool = false,
		isHidden: Bool = false
	) {
		self.init(
			"",
			key: key,
			keyModifiers: keyModifiers,
			isEnabled: isEnabled,
			isChecked: isChecked,
			isHidden: isHidden
		)
		self.attributedTitle = attributedTitle
	}

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
	func addDisabled(_ title: String) -> NSMenuItem {
		let menuItem = NSMenuItem(title)
		menuItem.isEnabled = false
		addItem(menuItem)
		return menuItem
	}

	@discardableResult
	func addDisabled(_ attributedTitle: NSAttributedString) -> NSMenuItem {
		let menuItem = NSMenuItem(attributedTitle)
		menuItem.isEnabled = false
		addItem(menuItem)
		return menuItem
	}

	@discardableResult
	func addItem(
		_ title: String,
		key: String = "",
		keyModifiers: NSEvent.ModifierFlags? = nil,
		isEnabled: Bool = true,
		isChecked: Bool = false,
		isHidden: Bool = false
	) -> NSMenuItem {
		let menuItem = NSMenuItem(
			title,
			key: key,
			keyModifiers: keyModifiers,
			isEnabled: isEnabled,
			isChecked: isChecked,
			isHidden: isHidden
		)
		addItem(menuItem)
		return menuItem
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


	@MainActor
	@discardableResult
	func addSettingsItem() -> NSMenuItem {
		addCallbackItem("Settings…", key: ",") {
			SSApp.showSettingsWindow()
		}
	}





	@MainActor
	@discardableResult
	func addQuitItem() -> NSMenuItem {
		addSeparator()

		return addCallbackItem("Quit \(SSApp.name)", key: "q") {
			SSApp.quit()
		}
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
	fileprivate func handleAction(_ sender: AnyObject) {
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
	/**
	The menu is only created when it's enabled.

	```
	menu.addItem("Foo")
		.withSubmenu(createCalendarEventMenu(with: event))
	```
	*/
	@discardableResult
	func withSubmenu(_ menu: @autoclosure () -> NSMenu) -> Self {
		submenu = isEnabled ? menu() : NSMenu()
		return self
	}

}
