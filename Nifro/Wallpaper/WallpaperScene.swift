import AppKit
import WebKit
import Combine

/**
One wallpaper. A window on one display, the web view inside it, and everything that decides what that web view is doing.

All of this used to be singletons on `AppState`, one window and one web view and one current website, which blocked every feature that needs more than one of anything. A different page per display, the most-asked-for thing in the upstream tracker, could not be built at all. A playlist could not run two pages at once.

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

	`window.contentView` is one slot, and it used to be written directly by whoever wanted it, with a flag kept beside it saying which of them had. Every writer had to remember to clear the other flags and pick the matching window size, and forgetting one shipped a blank wallpaper.

	One value removes the flags instead of making them easier to clear. There is nothing left to forget because there is nothing left to clear. Two cases today; the reason for the shape is that the count has changed before.
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

	/**
	The website whose page is actually on screen, as it stood when the page was loaded.

	`website` is where the scene is heading; this is where it is. The two differ for as long as a
	replacement takes to load out of sight, which is the whole point of swap loading.

	The whole value, not just the identity, so `applyWebsiteChanges` can tell "this scene already
	shows exactly this" from "this scene shows an older version of it" and skip the reload in the
	first case.
	*/
	private(set) var loadedWebsite: Website?

	var loadedWebsiteID: Website.ID? { loadedWebsite?.id }

	/**
	Whether the page for the current load has been put on screen yet.
	*/
	private(set) var hasRevealedPage = false

	private var reloadTimer: Timer?
	var playlistTimer: Timer?

	private var cancellables = Set<AnyCancellable>()

	/**
	Watches the current web view's address. Its own property rather than one of `cancellables`,
	because it has to be replaced when the web view is.
	*/
	private var addressObserver: AnyCancellable?

	init(display: Display?, website: Website?) {
		self.display = display
		self.website = website
		self.window = DesktopWindow(display: display)

		webViewController.scene = self

		// After the web view exists and before anything is on screen. `applyContent` installs the menu
		// bar band, and the band follows the page — so the page has to already be hidden by then, or
		// the band goes up on a scene that has not loaded anything and the menu bar changes colour a
		// second before the wallpaper arrives. The web view hides itself now; this only forces it to
		// exist first.
		_ = webViewController.webView
		applyContent()

		// The scene owns its own loading lifecycle. Wiring this app-wide meant only the first scene
		// ever restored its zoom or reported its errors.
		observeAddressChanges()

		webViewController.didLoadPublisher
			.convertToResult()
			.sink { [weak self] result in
				guard let self else {
					return
				}

				switch result {
				case .success:
					// The zoom used to be reapplied here. It read `webViewController.webView`, which
					// during a swap is the page on its way out, so it restored the old page's zoom onto
					// the old page and left the arriving one at 1. It belongs with the scroll position,
					// on the web view actually being handed the page — see `restorePageState`.
					AppState.shared.statusItemButton.toolTip = website?.tooltip
				case .failure(let error):
					AppState.shared.webViewError = error
				}
			}
			.store(in: &cancellables)
	}

	// MARK: - Content

	var screen: NSScreen? { window.targetDisplay?.screen ?? Display.mainScreen }

	/**
	The size the page lays out at, zoomed or not.

	A zoom magnifies one rectangle of a page that still believes it has the whole window. Laying it out at any other size reflows the site, and the region the user framed stops being the region they get. So this is always the frame `DesktopWindow` gives a window it has not shrunk: the screen without the menu bar strip.

	*/
	var pageLayoutSize: CGSize? { screen?.pageFrame.size }

	/**
	Record that the page on screen is now this scene's website, exactly as the list has it.
	*/
	func adoptLoadedWebsite() {
		loadedWebsite = website
	}

	/**
	Show the live page, magnified to a region when the website asks for one.

	Does nothing while the page on screen belongs to a different website. Switching website sets
	`website` at once and only reaches the new page seconds later, when it has finished loading out of
	sight — and installing the new website's region in between applied it to the old website's page,
	so a framed wallpaper snapped back to the whole page and stayed there until the switch completed.
	`adopt` calls this again once the new page is actually up.
	*/
	func installContentView() {
		guard loadedWebsiteID == nil || loadedWebsiteID == website?.id else {
			return
		}

		content = .live(zoom: website?.zoom)
	}

	/**
	Put `content` on screen.

	The only place that assigns `window.contentView` for a wallpaper window, and the only place that
	installs the menu bar band.
	*/
	private func applyContent() {
		window.allowsPassiveInteraction = website?.allowsInteraction == true

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
		loadedWebsite = nil
		content = .live(zoom: nil)
	}

	// MARK: - Loading

	func loadWebsite() {
		load(addressToLoad)
	}

	func reload() {
		captureScrollPosition()

		// Before the page goes, not two seconds after it last moved. Switching website reloads, and
		// somebody who moves a map and immediately switches away would otherwise lose the move.
		captureNavigatedAddress()

		// The address the user specified rather than whatever is loaded now — that may be a redirect
		// resolving differently each time — but moved to where the page last was, when the page says
		// so in its fragment.
		loadBySwapping(addressToLoad)
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

		// The page on screen is this website's from here on, so it gets this website's region. Doing
		// it here also covers coming back from disabled: suspending releases the page and leaves the
		// window holding a bare, region-less view, and nothing on the way back put the region on
		// again — so a framed wallpaper came back as the whole page.
		adoptLoadedWebsite()
		installContentView()

		hasRevealedPage = false

		// A page that never finishes still has to turn up. Long enough that an ordinary page has
		// loaded and revealed itself first, so this is the exception rather than the schedule.
		delay(.seconds(5)) { [weak self] in
			self?.revealPage()
		}
	}

	/**
	Follow the address of whichever web view is live.

	The page moving itself shows up as the address changing without a navigation, which is what a
	fragment change is. Debounced, because a page that follows a drag writes one on every frame.

	Re-subscribed whenever the web view is replaced. Set up once in `init`, it watched the first web
	view forever — and swap loading builds a new one for every website change, so after the first
	switch nothing was being watched at all and no page position was ever recorded again.
	*/
	func observeAddressChanges() {
		addressObserver = webViewController.webView.publisher(for: \.url)
			.debounce(for: .seconds(2), scheduler: DispatchQueue.main)
			.sink { [weak self] _ in
				self?.captureNavigatedAddress()
			}
	}

	/**
	Put the page on screen, once there is a page.

	It used to be a flat one-second delay, which is a guess about how long loading takes, and
	measurement says the guess is short: the reveal ran, and the page finished afterwards. Everything
	hung on this moment inherited that — most visibly the menu bar band, which went up wearing a
	colour taken off a page that had not arrived, so the menu bar changed and the wallpaper followed a
	second or two later.

	Driven by the load finishing now, with a timeout behind it. Unhides the web view itself rather
	than whatever view is installed by then: the page may be inside a wrapper, and unhiding the
	wrapper would leave the real web view hidden for the rest of the session, which is a blank
	wallpaper with no way back.
	*/
	func revealPage() {
		guard !hasRevealedPage else {
			return
		}

		hasRevealedPage = true

		webViewController.webView.isHidden = false
		window.contentView?.isHidden = false

		// In this order, and only now: the band stands in for the top of the page, so there has to be
		// a page for it to stand in for.
		refreshMenuBarBandColor()
		updateMenuBarBandVisibility()
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
			let reloadInterval = website?.effectiveReloadInterval
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
	A picture of what this display is showing right now.

	Taken from our own web view, which needs no permission at all — this is the app photographing its
	own view, not the screen. Screen Recording would be the other way to get this, and asking a
	wallpaper app for it to draw a thumbnail is a trade nobody should have to make.

	`nil` when there is nothing up: no website, or a page that has not arrived yet. The panel draws its
	own empty state rather than a blank rectangle that looks like a broken page.
	*/
	/**
	Where this display's video is, if it has one.
	*/
	func mediaClock() async -> (time: Double, duration: Double)? {
		// Asked of the live web view every time. Swap loading replaces it, and a held reference would
		// go on talking to the page that left.
		await webViewController.webView.mediaClock()
	}

	/**
	Tell this display's page which wall-clock moment its video was at zero, or `nil` when it is in no
	group.
	*/
	func setMediaEpoch(_ epoch: Double?) {
		webViewController.webView.setMediaEpoch(epoch)
	}

	/**
	Where somebody dragged this display's video to since this was last asked, if they did.
	*/
	func scrubbedPosition() async -> Double? {
		await webViewController.webView.scrubbedPosition()
	}

	/**
	How wide the panel draws a preview. Snapshots are taken at this size rather than the display's.
	*/
	static let previewWidth = 260

	func snapshot() async -> NSImage? {
		guard
			website != nil,
			loadedWebsite != nil
		else {
			return nil
		}

		let configuration = WKSnapshotConfiguration()

		// The page is already on screen, so there is nothing to wait for, and waiting on a wallpaper
		// that animates means waiting forever.
		configuration.afterScreenUpdates = false

		// At the size it will be looked at, not at the size of the display. Full resolution cost about
		// 600ms a frame on a 4K screen — a panel meant to look live updating roughly once a second —
		// and every one of those pixels was thrown away by a 260-point thumbnail anyway.
		configuration.snapshotWidth = NSNumber(value: Self.previewWidth)

		return try? await webViewController.webView.takeSnapshot(configuration: configuration)
	}

	/**
	Put back everything `suspend()` took away.
	*/
	func resume() {
		installMenuBarBandIfNeeded()
		window.makeKeyAndOrderFront(nil)
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
