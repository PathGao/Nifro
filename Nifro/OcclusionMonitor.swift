import AppKit
@preconcurrency import Combine

/**
Tells whether the desktop window is *effectively* hidden — covered by other windows to the point where rendering a live web page is wasted work.

`NSWindow.occlusionState` cannot answer this. The system calls a window visible if any sliver of it shows through, and two slivers essentially always show: the menu bar strip, and the Dock, which is translucent and therefore keeps the wallpaper behind it rendering. A maximized window leaves the desktop window `.visible` forever, so anything keyed off `occlusionState` never fires.

We compute the uncovered area ourselves instead. `NSScreen.visibleFrame` is already the screen minus the menu bar and minus the Dock, which is exactly the region where the wallpaper is worth anything, so those two are excluded by construction rather than by special-casing.
*/
@MainActor
final class OcclusionMonitor {
	/**
	Fraction of the usable screen that must stay uncovered for the wallpaper to be worth rendering live.
	*/
	private static let visibleFractionThreshold = 0.02

	// ponytail: coverage by grid rasterization instead of exact rectangle union. 64×40 cells is ~0.04% of the screen per cell, an order of magnitude finer than the threshold it feeds. Swap in a sweep-line union if this ever shows up in a profile.
	private static let gridColumns = 64
	private static let gridRows = 40

	/**
	How often we re-check while the app is running.

	Window moves and resizes by *other* apps post no notification we can observe without the Accessibility API, so the notifications below cannot be the only trigger.
	*/
	private static let pollInterval = 2.0

	/**
	Windows that span the screen without painting anything, and would otherwise read as full coverage.
	*/
	private static let ignoredOwners: Set<String> = [
		"Window Server", // Menu bar, and various full-screen scaffolding.
		"WallpaperAgent",
		"Notification Center",
		"Control Center",
		"Spotlight"
	]

	private let subject = CurrentValueSubject<Bool, Never>(false)
	private var cancellables = Set<AnyCancellable>()
	private var timer: Timer?

	/**
	Publishes `true` when the wallpaper is effectively hidden.
	*/
	var isHiddenPublisher: AnyPublisher<Bool, Never> {
		subject.removeDuplicates().eraseToAnyPublisher()
	}

	var isHidden: Bool { subject.value }

	/**
	The screen to judge. `nil` means the main screen.
	*/
	var screen: NSScreen? {
		didSet {
			update()
		}
	}

	init() {
		let workspaceNotifications: [NSNotification.Name] = [
			NSWorkspace.didActivateApplicationNotification,
			NSWorkspace.didHideApplicationNotification,
			NSWorkspace.didUnhideApplicationNotification,
			NSWorkspace.activeSpaceDidChangeNotification,
			NSWorkspace.didLaunchApplicationNotification,
			NSWorkspace.didTerminateApplicationNotification
		]

		for name in workspaceNotifications {
			NSWorkspace.shared.notificationCenter.publisher(for: name)
				.sink { [weak self] _ in
					Task { @MainActor in
						self?.update()
					}
				}
				.store(in: &cancellables)
		}

		timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.update()
			}
		}

		update()
	}

	// No `deinit` invalidating the timer: this object lives as long as the app does, and a nonisolated deinit cannot touch a `Timer` under Swift 6 anyway. The timer block holds `self` weakly, so nothing is kept alive by it.

	/**
	Force a re-check. Cheap: one window-list snapshot and a grid fill.
	*/
	func update() {
		subject.send(computeIsHidden())
	}

	private func computeIsHidden() -> Bool {
		guard let screen = screen ?? .main else {
			return false
		}

		let region = screen.visibleFrame

		guard region.width > 0, region.height > 0 else {
			return false
		}

		return currentUncoveredFraction(of: region) < Self.visibleFractionThreshold
	}

	/**
	Fraction of `region` not covered by any opaque window sitting above the desktop.

	`region` is in AppKit screen coordinates (origin bottom-left); the window list reports Core Graphics coordinates (origin top-left), so the windows get flipped before they are compared.
	*/
	private func currentUncoveredFraction(of region: CGRect) -> Double {
		guard
			let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
		else {
			// If we cannot tell, assume visible. Rendering a wallpaper nobody sees is cheaper than blanking one somebody does.
			return 1
		}

		let ownPID = ProcessInfo.processInfo.processIdentifier
		let arrangementHeight = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }.maxY

		var coveringRects = [CGRect]()

		for window in windowList {
			guard
				let layer = window[kCGWindowLayer as String] as? Int,
				// Below zero is the desktop, the desktop icons, and the wallpaper itself — none of which hide us.
				layer >= 0,
				let alpha = window[kCGWindowAlpha as String] as? Double,
				alpha > 0.9,
				let pid = window[kCGWindowOwnerPID as String] as? Int32,
				pid != ownPID,
				let owner = window[kCGWindowOwnerName as String] as? String,
				!Self.ignoredOwners.contains(owner),
				let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
				let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
			else {
				continue
			}

			coveringRects.append(flippingFromWindowServer(cgBounds, arrangementHeight: arrangementHeight))
		}

		return uncoveredFraction(of: region, covering: coveringRects)
	}
}
