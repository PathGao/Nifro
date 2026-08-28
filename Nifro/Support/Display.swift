import SwiftUI
import Combine


extension NSScreen: @retroactive Identifiable {
	public var id: CGDirectDisplayID {
		deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
	}
}

extension NSScreen {
	/**
	Convert a persistent display ID to a transient one.
	*/
	static func uuidFromID(_ id: CGDirectDisplayID) -> UUID? {
		// We force an optional as it can be `nil` in some cases even though it's not annotated as that.
		// https://github.com/lwouis/alt-tab-macos/issues/330
		let cfUUID: CFUUID? = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
		return cfUUID?.toUUID
	}


	/**
	The persistent identifier of the screen.

	The `.id` property is only persistent for the current session.
	*/
	var uuid: UUID? { Self.uuidFromID(id) }
}

extension NSScreen {
	/**
	Returns a publisher that sends updates when anything related to screens change.

	This includes screens being added/removed, resolution change, and the screen frame changing (dock and menu bar being toggled).
	*/
	static var publisher: some Publisher<Void, Never> {
		Publishers.Merge(
			SSEvents.screenParametersDidChange,
			// We use a wake up notification as the screen setup might have changed during sleep. For example, a screen could have been unplugged.
			SSEvents.deviceDidWake
		)
	}

	/**
	The thickness of the status bar on the screen, or `0` when it does not take up space.
	*/
	var statusBarThickness: Double {
		menuBarStripHeight(frame: frame, visibleFrame: visibleFrame)
	}

	/**
	Get the frame of the actual visible part of the screen. This means under the dock, but *not* under the status bar if there's a status bar. This is different from `.visibleFrame` which also includes the space under the status bar.
	*/
	var frameWithoutStatusBar: CGRect {
		var frame = frame
		frame.size.height -= statusBarThickness
		return frame
	}
}


struct Display: Hashable, Codable, Identifiable {
	/**
	Self wrapped in an observable that updates when display change.
	*/
	@MainActor static let observable = ObservableValue(
		value: Self.self,
		publisher: NSScreen.publisher
	)

	/**
	The display with the menu bar.

	A `var`, because which display that is changes: rearranging displays in System Settings moves the
	menu bar, and so does docking. As a `let` it was whatever `CGMainDisplayID()` said the first time
	anything asked, kept for the life of the process — and the callers with no display of their own to
	name fall back to this, so a stale answer sends a wallpaper to a display that may itself be gone.
	*/
	static var main: Self? { Self(transientID: CGMainDisplayID()) }

	/**
	All displays.
	*/
	static var all: [Self] {
		NSScreen.screens.compactMap { self.init(screen: $0) }
	}

	/**
	The persistent ID of the display.
	*/
	let id: UUID


	/**
	The `NSScreen` for the display.
	*/
	var screen: NSScreen? {
		NSScreen.screens.first { $0.uuid == id }
	}

	/**
	The localized name of the display.
	*/
	var localizedName: String { screen?.localizedName ?? "<Unknown name>" }

	/**
	The display the pointer is on, or `nil` when it cannot be placed on one.

	`frame` rather than `visibleFrame` or `pageFrame`: those cut away the menu bar, and the pointer
	being *on* the menu bar is the moment this matters most — it is where the app's own icon is.
	`CGRect.contains` is half-open, so the seam between two screens belongs to exactly one of them.

	Optional because there are moments when the answer is nothing: the tens of milliseconds while
	displays are being reconfigured, every screen asleep, and the dead corners of a non-rectangular
	arrangement. Every caller falls back rather than forcing it.
	*/
	@MainActor
	static var underMouse: Self? {
		let point = NSEvent.mouseLocation

		return NSScreen.screens
			.first { $0.frame.contains(point) }
			.flatMap(Self.init(screen:))
	}

	/**
	The screen a wallpaper with no display of its own belongs on.

	Written out rather than left to `?? .main`, which in an `NSScreen?` position means
	`NSScreen.main` — **the screen holding the window with keyboard focus**, not the display with the
	menu bar. Measured on two displays: the primary was the built-in one, focus was on the external,
	and the wallpaper followed the focus. It also moves, so a wallpaper could change screens because
	the user clicked something.
	*/
	@MainActor
	static var mainScreen: NSScreen? { main?.screen ?? NSScreen.screens.first }

	init(_ id: UUID) {
		self.id = id
	}

	init?(transientID: CGDirectDisplayID) {
		guard let id = NSScreen.uuidFromID(transientID) else {
			return nil
		}

		self.init(id)
	}

	init?(screen: NSScreen) {
		self.init(transientID: screen.id)
	}
}

extension Display: Defaults.Serializable {
	struct Bridge: Defaults.Bridge {
		typealias Value = Display
		typealias Serializable = UUID

		func serialize(_ value: Value?) -> Serializable? {
			value?.id
		}

		func deserialize(_ object: Serializable?) -> Value? {
			guard let object else {
				return nil
			}

			return .init(object)
		}
	}

	static let bridge = Bridge()
}

extension NSScreen {
	/**
	The screen rectangle a wallpaper page lays out in.

	Both the size the page is given and the origin its coordinates are measured from have to come
	from here. They were separate answers to one question once, and a crop stored against one and
	displayed against the other lands a menu bar height away from where it was framed.

	Never the strip behind the menu bar. Anything the page puts up there cannot be read and cannot be
	clicked; the menu bar's tint is handled by a band of solid colour instead, which is the only part
	of being up there that was ever worth having.
	*/
	var pageFrame: CGRect { frameWithoutStatusBar }
}
