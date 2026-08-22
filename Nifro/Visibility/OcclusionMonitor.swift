import AppKit
@preconcurrency import Combine

/**
Tells whether other windows cover the desktop window enough that rendering a live web page is wasted work.

`NSWindow.occlusionState` cannot answer this. The system calls a window visible if any sliver of it shows through, and two slivers almost always show. One is the menu bar strip. The other is the Dock, which is translucent, so the wallpaper behind it keeps rendering. A maximized window leaves the desktop window `.visible` forever, so anything keyed off `occlusionState` never fires.

We measure the uncovered area ourselves instead, over the whole screen frame. Those two strips are where the wallpaper survives when everything else is covered, so they count as visible rather than being excluded.
*/
@MainActor
final class OcclusionMonitor {


	/**
	How often we re-check while the app is running.

	Window moves and resizes by *other* apps post no notification we can observe without the Accessibility API, so the notifications below cannot be the only trigger.
	*/
	private static let pollInterval = 2.0

	/**
	Windows that do not hide the wallpaper, either because they paint nothing or because you can see straight through them.

	The Dock is the interesting one. Its window is fully opaque as far as the window server is concerned, but what it draws is translucent, so the page carries on showing through it. Counting it as coverage would throw that sliver away.
	*/
	private static let ignoredOwners: Set<String> = [
		"Window Server", // Menu bar, and various full-screen scaffolding.
		"Dock",
		"WallpaperAgent",
		"Notification Center",
		"Control Center",
		"Spotlight"
	]

	private let subject = CurrentValueSubject<CGRect, Never>(.zero)
	private(set) var largestVisibleRegion: (rect: CGRect, area: Double) = (.zero, 0)
	private var cancellables = Set<AnyCancellable>()

	/**
	Held only to keep the timer alive. Nothing reads it. A repeating `Timer` that nobody retains stops firing.
	*/
	private var timer: Timer?

	/**
	Publishes the largest patch of wallpaper still on show, whenever it changes.
	*/
	var visibleRegionPublisher: AnyPublisher<CGRect, Never> {
		subject.removeDuplicates().eraseToAnyPublisher()
	}

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

	// No `deinit` invalidating the timer. This object lives as long as the app does, and a nonisolated deinit cannot touch a `Timer` under Swift 6 anyway. The timer block holds `self` weakly, so it keeps nothing alive.

	/**
	Force a re-check. Costs one window-list snapshot and a grid fill.
	*/
	func update() {
		guard let screen = screen ?? .main else {
			return
		}

		// The whole screen, not `visibleFrame`. The strips behind the Dock and the menu bar are where the wallpaper survives when everything else is covered, and they are worth rendering for.
		let region = screen.frame

		guard region.width > 0, region.height > 0 else {
			return
		}

		largestVisibleRegion = currentLargestRegion(of: region)
		subject.send(largestVisibleRegion.rect)
	}

	/**
	The largest patch of `region` that no opaque window above the desktop covers.

	`region` is in AppKit screen coordinates (origin bottom-left); the window list reports Core Graphics coordinates (origin top-left), so the windows get flipped before they are compared.
	*/
	private func currentLargestRegion(of region: CGRect) -> (rect: CGRect, area: Double) {
		guard
			let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
		else {
			// If we cannot tell, assume fully visible. Rendering a wallpaper nobody sees is cheaper than freezing one somebody is looking at.
			return (region, region.width * region.height)
		}

		let ownPID = ProcessInfo.processInfo.processIdentifier
		let arrangementHeight = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }.maxY

		var coveringRects = [CGRect]()

		for window in windowList {
			guard
				let layer = window[kCGWindowLayer as String] as? Int,
				// Below zero is the desktop, the desktop icons, and the wallpaper itself. None of those hide us.
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

		return largestUncoveredRegion(of: region, covering: coveringRects)
	}
}
