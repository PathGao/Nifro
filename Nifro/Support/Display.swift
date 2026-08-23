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
	This can be useful if you store a reference to a `NSScreen` instance as it may have been disconnected.
	*/
	var isConnected: Bool {
		Self.screens.contains { $0.id == id }
	}


	/**
	Whether the screen shows a status bar that takes up space.
	*/
	var hasStatusBar: Bool { statusBarThickness > 0 }

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

		// Account for the status bar if the window is on the main screen and the status bar is permanently visible, or if on a secondary screen and secondary screens are set to show the status bar.
		if hasStatusBar {
			frame.size.height -= statusBarThickness
		}

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
	The main display.
	*/
	static let main = Self(transientID: CGMainDisplayID())

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
	Whether the display is connected.
	*/
	var isConnected: Bool { screen?.isConnected ?? false }

	/**
	Get the main display if the current display is not connected.
	*/
	var withFallbackToMain: Self? { isConnected ? self : .main }

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
