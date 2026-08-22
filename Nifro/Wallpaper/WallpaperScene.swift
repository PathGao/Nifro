import AppKit
import Combine

/**
One wallpaper: a window on one display, the web view inside it, and everything that decides what that web view is doing.

Until now all of this was a set of singletons on `AppState` — one window, one web view, one current website — and every feature that needs more than one of anything ran into that. Showing a different page per display is the most-asked-for thing in the upstream tracker and could not be built at all; a playlist could not run two pages at once; the snapshot backend needs a second, offscreen renderer alongside the live one.

So the unit is the scene, and the app owns a list of them. A single-display setup has exactly one and behaves as before.
*/
@MainActor
final class WallpaperScene {
	/**
	The display this scene lives on. `nil` follows the main display.
	*/
	let display: Display?

	let window: DesktopWindow
	private(set) var webViewController = WebViewController()

	/**
	The website this scene shows, if any.
	*/
	var website: Website?

	// MARK: - Rendering state

	/**
	The last rendered frame, standing in for the web view while frozen.
	*/
	var frozenView: NSImageView?

	/**
	The screen region currently being rendered, when the window has been shrunk to what is still on show.
	*/
	var renderedRegion: CGRect?

	/**
	Opaque band covering the strip of wallpaper behind the menu bar, when the user asked for colour without content.
	*/
	var menuBarBand: MenuBarBandView?

	/**
	The replacement page being loaded out of sight, and the task driving it.
	*/
	var pendingWebView: SSWebView?
	var pendingLoad: Task<Void, Never>?

	/**
	A reload came due while frozen and still has to happen.
	*/
	var isReloadPending = false

	var reloadTimer: Timer?
	var playlistTimer: Timer?

	/**
	The still being shown in place of a live page, and the task producing the next one.
	*/
	var snapshotView: NSImageView?
	var snapshotTask: Task<Void, Never>?

	let occlusionMonitor: OcclusionMonitor

	private var cancellables = Set<AnyCancellable>()

	init(display: Display?) {
		self.display = display
		self.window = DesktopWindow(display: display)
		self.occlusionMonitor = OcclusionMonitor()

		webViewController.scene = self
		occlusionMonitor.screen = display?.screen
		window.contentView = webViewController.webView
		window.contentView?.isHidden = true

		occlusionMonitor.visibleRegionPublisher
			.sink { [weak self] _ in
				self?.applyVisibilityState()
			}
			.store(in: &cancellables)
	}

	// MARK: - Content

	var screen: NSScreen? { window.targetDisplay?.screen ?? .main }

	/**
	Puts the web view into the window, wrapped in a crop when the website has one.

	The page lays out at full screen size even when cropped. Letting it lay out at the crop size instead would change the site's own layout, and the region the user framed would no longer be the region they get.
	*/
	func installContentView() {
		window.allowsPassiveInteraction = website?.allowsInteraction ?? false

		let webView = webViewController.webView

		guard
			let crop = website?.crop,
			let screen
		else {
			window.cropRect = nil
			window.contentView = webView
			installMenuBarBandIfNeeded()
			return
		}

		window.cropRect = crop
		window.contentView = CropView(
			content: webView,
			crop: crop,
			pageSize: screen.frameWithoutStatusBar.size
		)
		installMenuBarBandIfNeeded()
	}

	func recreateWebView() {
		webViewController.recreateWebView()
		installContentView()
	}

	func adoptWebView(_ replacement: SSWebView) {
		webViewController.adopt(replacement)
	}

	/**
	Drop the page and the process behind it.
	*/
	func releaseWebView() {
		pendingLoad?.cancel()
		pendingWebView = nil
		frozenView = nil
		renderedRegion = nil
		window.cropRect = nil
		webViewController.releaseWebView()
		window.contentView = webViewController.webView
	}

	// MARK: - Loading

	func loadWebsite() {
		guard !usesSnapshotRendering else {
			refreshSnapshot()
			return
		}

		stopSnapshotRendering()
		load(website?.url)
	}

	func reload() {
		guard !usesSnapshotRendering else {
			refreshSnapshot()
			return
		}

		captureScrollPosition()

		// Always the URL the user specified rather than the current one: it may be a redirect that resolves differently each time.
		loadBySwapping(website?.url)
	}

	func load(_ url: URL?) {
		AppState.shared.webViewError = nil

		guard
			var url,
			url.isValid
		else {
			return
		}

		do {
			url = try replacePlaceholders(of: url) ?? url
		} catch {
			error.presentAsModal()
			return
		}

		webViewController.loadURL(url)

		// The web view starts hidden so the first frame is not a flash of white. Unhide the web view itself rather than whatever view happens to be installed a second from now: by then the visibility policy may have swapped in a still or a crop container, and unhiding that would leave the real web view hidden for the rest of the session — a blank wallpaper with no way back.
		delay(.seconds(1)) { [weak self] in
			guard let self else {
				return
			}

			webViewController.webView.isHidden = false
			window.contentView?.isHidden = false
		}
	}

	/**
	Replaces app-specific placeholder strings in the given URL with a corresponding value.
	*/
	func replacePlaceholders(of url: URL) throws -> URL? {
		guard let screen else {
			return nil
		}

		return try url
			.replacingPlaceholder("[[screenWidth]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.width))
			.replacingPlaceholder("[[screenHeight]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.height))
	}

	// MARK: - Timing

	func resetTimer() {
		reloadTimer?.invalidate()
		reloadTimer = nil

		guard
			AppState.shared.isEnabled,
			!AppState.shared.isBrowsingMode,
			website != nil,
			let reloadInterval = Defaults[.reloadInterval]
		else {
			return
		}

		// While frozen there is nothing to reload into. Remember that one came due so the thaw can settle it.
		guard frozenView == nil else {
			isReloadPending = true
			return
		}

		reloadTimer = Timer.scheduledTimer(withTimeInterval: reloadInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.reload()
			}
		}
	}

	// MARK: - Appearance

	func applyOpacity(animated: Bool = true) {
		let target = AppState.shared.targetOpacity
		let window = window

		guard window.alphaValue != target else {
			return
		}

		guard animated else {
			window.alphaValue = target
			return
		}

		NSAnimationContext.runAnimationGroup {
			$0.duration = 0.25
			window.animator().alphaValue = target
		}
	}

	func tearDown() {
		reloadTimer?.invalidate()
		playlistTimer?.invalidate()
		snapshotTask?.cancel()
		pendingLoad?.cancel()
		window.orderOut(nil)
		window.contentView = nil
	}
}
