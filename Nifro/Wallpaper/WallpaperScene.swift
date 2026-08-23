import AppKit
import Combine

/**
One wallpaper. A window on one display, the web view inside it, and everything that decides what that web view is doing.

All of this used to be singletons on `AppState`, one window and one web view and one current website, which blocked every feature that needs more than one of anything. A different page per display, the most-asked-for thing in the upstream tracker, could not be built at all. A playlist could not run two pages at once. The snapshot backend needs a second, offscreen renderer alongside the live one.

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
	What the window is showing right now.

	`window.contentView` is one slot and four features want to fill it: the live page, the live page shrunk to the patch still on show, the still held while the wallpaper is covered, and the still the snapshot backend draws from. Each used to write the slot itself and keep a flag beside it, so every writer had to remember to clear the other three flags and pick the matching window size. Forgetting one shipped a blank wallpaper.

	One value removes the flags instead of making them easier to clear. There is nothing left to forget because there is nothing left to clear.
	*/
	var content = WallpaperContent.live(zoom: nil) {
		didSet {
			applyContent()
		}
	}

	/**
	Opaque band covering the strip of wallpaper behind the menu bar, when the user asked for colour without content.
	*/
	var menuBarBand: MenuBarBandWindow?

	/**
	The replacement page being loaded out of sight, and the task driving it.
	*/
	var pendingWebView: SSWebView?
	var pendingLoad: Task<Void, Never>?

	private var reloadTimer: Timer?
	var playlistTimer: Timer?

	private var cancellables = Set<AnyCancellable>()

	init(display: Display?) {
		self.display = display
		self.window = DesktopWindow(display: display)

		webViewController.scene = self
		applyContent()

		// The web view starts hidden so the first frame is not a flash of white.
		webViewController.webView.isHidden = true

		// The scene owns its own loading lifecycle. Wiring this app-wide meant only the first scene
		// ever restored its zoom or reported its errors.
		webViewController.didLoadPublisher
			.convertToResult()
			.sink { [weak self] result in
				guard let self else {
					return
				}

				switch result {
				case .success:
					// Reapplying the persisted zoom has to happen here, once `webView.url` is set.
					let zoomLevel = webViewController.webView.zoomLevelWrapper

					if zoomLevel != 1 {
						webViewController.webView.zoomLevelWrapper = zoomLevel
					}

					AppState.shared.statusItemButton.toolTip = website?.tooltip
				case .failure(let error):
					AppState.shared.webViewError = error
				}
			}
			.store(in: &cancellables)
	}

	// MARK: - Content

	var screen: NSScreen? { window.targetDisplay?.screen ?? .main }

	/**
	The size the page lays out at, zoomed or not.

	A zoom magnifies one rectangle of a page that still believes it has the whole window. Laying it out at any other size reflows the site, and the region the user framed stops being the region they get. So this is always the frame `DesktopWindow` gives a window it has not shrunk: the screen without the menu bar strip.

	*/
	var pageLayoutSize: CGSize? { screen?.pageFrame.size }

	/**
	Show the live page, magnified to a region when the website asks for one.
	*/
	func installContentView() {
		content = .live(zoom: website?.zoom)
	}

/**
	Put `content` on screen.

	The only place that assigns `window.contentView` or `window.reducedRegion` for a wallpaper window, and the only place that installs the menu bar band.
	*/

	private func applyContent() {
		window.allowsPassiveInteraction = renderingMode == .interactive

		var view: NSView?

		switch content {
		case .empty:
			break
		case .live(let zoom):
			view = pageView(zoom: zoom)
		}

		window.contentView = view

		installMenuBarBandIfNeeded()
	}

	/**
	The live web view, wrapped when there is something to magnify or cut away and a page size to lay it out against.

	Bare when there is neither, because a page filling the window at its own size is what a wrapper
	would work out anyway.
	*/
	private func pageView(zoom: Zoom?) -> NSView {
		let webView = webViewController.webView

		guard
			let zoom,
			let pageSize = pageLayoutSize
		else {
			webView.magnification = 1
			return webView
		}

		return PageView(
			content: webView,
			zoom: zoom,
			pageSize: pageSize
		)
	}

	/**
	Drop the page and the process behind it.
	*/
	func releaseWebView() {
		pendingLoad?.cancel()
		pendingWebView = nil
		webViewController.releaseWebView()
		content = .live(zoom: nil)
	}

	// MARK: - Loading

	func loadWebsite() {
		load(website?.url)
	}

	func reload() {
		captureScrollPosition()

		// Always the URL the user specified rather than the current one. It may be a redirect that resolves differently each time.
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

		// The web view starts hidden so the first frame is not a flash of white. Unhide the web view itself, not whatever view happens to be installed a second from now. By then the visibility policy may have swapped in a still or a wrapper view, and unhiding that would leave the real web view hidden for the rest of the session. That is a blank wallpaper with no way back.
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

	// MARK: - Watching what the page does

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

	/**
	Leave nothing of this scene on screen or running.

	Disabling is meant to be indistinguishable from having quit, apart from the menu bar icon still
	being there — so everything this scene puts on screen has to go, not just the wallpaper window.
	The colour band is its own window, which is what keeps it steady while the wallpaper moves and
	resizes, and is also why nothing was taking it down: it stayed, tinting the menu bar with the
	colour of a page that was no longer being shown.

	One method rather than a list of four things at the call site, because the next thing a scene
	starts will have to be stopped here too, and a list is where that gets forgotten.
	*/
	/**
	Put back everything `suspend()` took away.
	*/
	func resume() {
		installMenuBarBandIfNeeded()
		window.makeKeyAndOrderFront(nil)
	}

	func suspend() {
		reloadTimer?.invalidate()
		reloadTimer = nil
		playlistTimer?.invalidate()
		playlistTimer = nil
		pendingLoad?.cancel()

		// Before the band: releasing installs an empty page, and installing content is one of the
		// paths that puts the band back. It refuses to now that the app is disabled, but relying on
		// the order here as well costs nothing.
		releaseWebView()

		window.orderOut(nil)
		menuBarBand?.close()
		menuBarBand = nil
	}

	func tearDown() {
		reloadTimer?.invalidate()
		playlistTimer?.invalidate()
		pendingLoad?.cancel()
		window.orderOut(nil)
		content = .empty

		// Its own window, so nothing else takes it off screen.
		menuBarBand?.close()
		menuBarBand = nil
	}
}

/**
What the window is showing.
*/
enum WallpaperContent {
	/**
	Nothing. The window has been torn down.
	*/
	case empty

	/**
	The live web view, magnified to one region of the page when the website asks for it.
	*/
	case live(zoom: Zoom?)
}

/**
Whether the page has to take clicks straight off the desktop.
*/
enum RenderingMode {
	/**
	A live page that takes clicks without Browsing Mode, so it always renders.
	*/
	case interactive

	/**
	A live page. The wallpaper renders it, always, which is the only thing this app promises to do.
	*/
	case full
}

extension WallpaperScene {
	var renderingMode: RenderingMode {
		website?.allowsInteraction == true ? .interactive : .full
	}
}
