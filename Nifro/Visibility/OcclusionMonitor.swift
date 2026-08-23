import AppKit
@preconcurrency import Combine

/**
Tells whether other windows cover the desktop window enough that rendering a live web page is wasted work.

`NSWindow.occlusionState` cannot answer this. The system calls a window visible if any sliver of it shows through, and two slivers almost always show. One is the menu bar strip. The other is the Dock, which is translucent, so the wallpaper behind it keeps rendering. A maximized window leaves the desktop window `.visible` forever, so anything keyed off `occlusionState` never fires.

We measure the uncovered area ourselves instead, over the whole screen frame. Those two strips are where the wallpaper survives when everything else is covered, so they count as visible rather than being excluded. Which windows count as coverage is `Coverage.hidesWallpaper`.
*/
@MainActor
final class OcclusionMonitor {
	/**
	How often we re-check while the app is running.

	Window moves and resizes by *other* apps post no notification we can observe without the Accessibility API, so the notifications below cannot be the only trigger.
	*/
	private static let pollInterval = 2.0

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
		start()
	}

	/**
	Begin watching, or begin again after `stop()`.

	Separate from `init` so that stopping is reversible. It has to be: disabling the wallpaper stops
	every scene, and enabling it again reuses the same scene objects rather than building new ones —
	a monitor that could only be started once would leave those scenes never measuring anything again,
	which reads as the wallpaper simply not reacting to windows any more.
	*/
	func start() {
		guard timer == nil else {
			return
		}

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

	/**
	Stop polling.

	Needed because there is one of these per scene, and scenes are torn down whenever a display is
	plugged in or out. A `deinit` cannot do it: a nonisolated deinit cannot touch a `Timer` under
	Swift 6. The timer block holds `self` weakly, so nothing is kept alive by it, but the timer keeps
	firing on the run loop until told otherwise.
	*/
	func stop() {
		timer?.invalidate()
		timer = nil
		cancellables.removeAll()
	}


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

		// One lookup per process rather than per window. A busy desktop reports the same handful of
		// applications over and over, and this runs every two seconds.
		var bundleIdentifiers = [Int32: String?]()

		var coveringRects = [CGRect]()

		for window in windowList {
			guard
				let layer = window[kCGWindowLayer as String] as? Int,
				let alpha = window[kCGWindowAlpha as String] as? Double,
				let pid = window[kCGWindowOwnerPID as String] as? Int32,
				let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
				let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
			else {
				continue
			}

			let bundleIdentifier = bundleIdentifiers[pid] ?? {
				let resolved = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
				bundleIdentifiers[pid] = resolved
				return resolved
			}()

			guard
				Coverage.hidesWallpaper(
					layer: layer,
					alpha: alpha,
					bundleIdentifier: bundleIdentifier,
					processName: window[kCGWindowOwnerName as String] as? String,
					isOwnWindow: pid == ownPID
				)
			else {
				continue
			}

			coveringRects.append(flippingFromWindowServer(cgBounds, arrangementHeight: arrangementHeight))
		}

		return largestUncoveredRegion(of: region, covering: coveringRects)
	}
}
