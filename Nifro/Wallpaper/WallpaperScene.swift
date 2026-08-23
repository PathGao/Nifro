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

	`window.contentView` is one slot and four features want to fill it: the live page, the live page shrunk to the patch still on show, the still held while the wallpaper is covered, and the still the snapshot backend draws from. Each used to write the slot itself and keep a flag beside it, so every writer had to remember to clear the other three flags and pick the matching `cropRect`. Forgetting one shipped a blank wallpaper.

	One value removes the flags instead of making them easier to clear. There is nothing left to forget because there is nothing left to clear.
	*/
	var content = WallpaperContent.live(crop: nil) {
		didSet {
			applyContent()
		}
	}

	/**
	Whether the live page has been replaced by its last frame because nothing of the wallpaper is on show.

	A snapshot still is not frozen. It refreshes on its own timer and the page behind it is meant to be gone.
	*/
	var isFrozen: Bool {
		if case .frozen = content {
			true
		} else {
			false
		}
	}

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

	private var reloadTimer: Timer?
	var playlistTimer: Timer?

	/**
	The task producing the next still for the snapshot backend.
	*/
	var snapshotTask: Task<Void, Never>?

	/**
	What watching the page said it is, once there has been enough of it to say. `nil` until then.
	*/
	var observedActivity: PageActivity?

	/**
	Readings collected since the page loaded, oldest first.
	*/
	var activitySamples: [ActivitySample] = []

	let occlusionMonitor: OcclusionMonitor

	private var cancellables = Set<AnyCancellable>()

	init(display: Display?) {
		self.display = display
		self.window = DesktopWindow(display: display)
		self.occlusionMonitor = OcclusionMonitor()

		webViewController.scene = self
		occlusionMonitor.screen = display?.screen
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

		occlusionMonitor.visibleRegionPublisher
			.sink { [weak self] _ in
				self?.applyVisibilityState()
			}
			.store(in: &cancellables)
	}

	// MARK: - Content

	var screen: NSScreen? { window.targetDisplay?.screen ?? .main }

	/**
	The size the page lays out at, cropped or not.

	A crop shows one rectangle of a page that still believes it has the whole window. Laying it out at any other size reflows the site, and the region the user framed stops being the region they get. So this is the frame `DesktopWindow` gives an uncropped window: the screen without the menu bar strip, or the whole screen when the wallpaper is set to extend under the menu bar.

	`renderOnly` used to answer this with `screen.frame.size` while `installContentView` answered with `screen.frameWithoutStatusBar.size`, so the same crop showed different content depending on which path installed it.
	*/
	var pageLayoutSize: CGSize? { screen?.pageFrame.size }

	/**
	Whether this website should be drawn from stills, either because it was told to or because
	watching it said so.
	*/
	var wantsStills: Bool {
		switch website?.rendering {
		case .snapshot:
			true
		case .automatic:
			observedActivity == .still || observedActivity == .periodic
		default:
			false
		}
	}


	/**
	Show the live page, cropped when the website asks for one.
	*/
	func installContentView() {
		content = .live(crop: website?.crop)
	}

	/**
	Put `content` on screen.

	The only place that assigns `window.contentView` or `window.cropRect` for a wallpaper window, and the only place that installs the menu bar band.
	*/
	private func applyContent() {
		window.allowsPassiveInteraction = renderingMode == .interactive

		var crop: CGRect?
		var view: NSView?

		switch content {
		case .empty:
			break
		case .live(let websiteCrop):
			(crop, view) = pageView(crop: websiteCrop)
		case .reduced(let region):
			(crop, view) = pageView(crop: region)
		case .frozen(let image):
			view = stillView(image)
		case .snapshot(let image, let websiteCrop):
			crop = websiteCrop
			view = stillView(image)
		}

		// The crop goes first because it resizes the window, and the content view is laid out against the size it ends up with.
		window.cropRect = crop
		window.contentView = view

		installMenuBarBandIfNeeded()
	}

	/**
	The live web view, wrapped in a crop container when there is a region to show and a page size to lay it out at.

	Returns the crop it actually installed, which is nothing when the screen went away and there is no size to lay the page out at.
	*/
	private func pageView(crop: CGRect?) -> (crop: CGRect?, view: NSView) {
		let webView = webViewController.webView

		guard
			let crop,
			let pageSize = pageLayoutSize
		else {
			return (nil, webView)
		}

		return (
			crop,
			CropView(
				content: webView,
				crop: crop,
				pageSize: pageSize
			)
		)
	}

	private func stillView(_ image: NSImage?) -> NSView {
		let view = NSImageView(frame: window.contentLayoutRect)
		view.imageScaling = .scaleAxesIndependently
		view.image = image
		view.autoresizingMask = [.width, .height]

		return view
	}

	func recreateWebView() {
		webViewController.recreateWebView()
		installContentView()
	}

	/**
	Drop the page and the process behind it.
	*/
	func releaseWebView() {
		pendingLoad?.cancel()
		pendingWebView = nil
		webViewController.releaseWebView()
		content = .live(crop: nil)
	}

	// MARK: - Loading

	func loadWebsite() {
		guard renderingMode != .snapshot else {
			refreshSnapshot()
			return
		}

		stopSnapshotRendering()
		load(website?.url)
	}

	func reload() {
		guard renderingMode != .snapshot else {
			refreshSnapshot()
			return
		}

		captureScrollPosition()

		// Always the URL the user specified rather than the current one. It may be a redirect that resolves differently each time.
		loadBySwapping(website?.url)
	}

	func load(_ url: URL?) {
		AppState.shared.webViewError = nil
		forgetObservedActivity()

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

		// The web view starts hidden so the first frame is not a flash of white. Unhide the web view itself, not whatever view happens to be installed a second from now. By then the visibility policy may have swapped in a still or a crop container, and unhiding that would leave the real web view hidden for the rest of the session. That is a blank wallpaper with no way back.
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

	/**
	How long to watch before deciding. Six ten-second windows.
	*/
	private static let samplesBeforeDeciding = 6

	/**
	Take one reading from the page and act on it once there are enough.
	*/
	func record(_ sample: ActivitySample) {
		activitySamples.append(sample)

		// Keep the window rolling so a page that starts moving later is noticed.
		if activitySamples.count > Self.samplesBeforeDeciding {
			activitySamples.removeFirst()
		}

		guard activitySamples.count >= Self.samplesBeforeDeciding else {
			return
		}

		let verdict = classify(activitySamples)

		guard verdict != observedActivity else {
			return
		}

		observedActivity = verdict

		if verdict == .periodic {
			let rate = Double(activitySamples.reduce(0) { $0 + $1.mutations })
				/ activitySamples.reduce(0) { $0 + $1.seconds }
			Defaults[.reloadInterval] = refreshInterval(forMutationRate: rate)
		}

		applyVisibilityState()
		resetTimer()

		if wantsStills {
			refreshSnapshot()
		}
	}

	/**
	Start watching again. A new page is a new question.
	*/
	func forgetObservedActivity() {
		activitySamples.removeAll()
		observedActivity = nil
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
		guard !isFrozen else {
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
		content = .empty
	}
}

/**
What a wallpaper window is showing.

Every rectangle here is in page coordinates with the origin at the top-left, the same space `Website.crop` uses.
*/
enum WallpaperContent {
	/**
	Nothing. The window has been torn down.
	*/
	case empty

	/**
	The live web view, showing one region of the page when the website asks for a crop.
	*/
	case live(crop: CGRect?)

	/**
	The live web view with the window shrunk to the patch of wallpaper still on show.

	Separate from `live` because the visibility policy owns this rectangle and the website owns the other one. Only this one gets handed back when the desktop is revealed again.
	*/
	case reduced(to: CGRect)

	/**
	The last frame of the live page, held while nothing of the wallpaper is on show.
	*/
	case frozen(NSImage?)

	/**
	A still from the snapshot backend, cropped the way the live page would have been.

	Separate from `frozen` because there is no live page waiting behind it. It refreshes on the reload timer and the visibility policy leaves it alone.
	*/
	case snapshot(NSImage?, crop: CGRect?)
}

/**
Which of the mutually exclusive ways of drawing a wallpaper applies to a scene right now.

Snapshot rendering, passive clicks and freezing when covered cannot combine. A still cannot be clicked, and a page that has to accept clicks has to be there to accept them. The rules used to be spelled out as a separate `&&` chain in each of the three files that cared, so a rule that changed had to change in all of them.
*/
enum RenderingMode {
	/**
	Stills from an offscreen renderer. No web process runs between refreshes.
	*/
	case snapshot

	/**
	A live page that takes clicks straight off the desktop, so it always renders.
	*/
	case interactive

	/**
	A live page that may shrink to the visible patch or freeze on its last frame.
	*/
	case managed

	/**
	A live page that keeps rendering in full.
	*/
	case full
}

extension WallpaperScene {
	var renderingMode: RenderingMode {
		// A still cannot be clicked, so this wins over the snapshot backend rather than sitting alongside it.
		if website?.allowsInteraction == true {
			return .interactive
		}

		// While the user is dragging out a crop region the window belongs to them. Anything that
		// replaces the content view drops the selection overlay, and the occlusion poll runs every
		// two seconds, so this is not a narrow window to lose.
		if AppState.shared.isSelectingCrop {
			return .full
		}

		// Browsing Mode puts the page in front of the user to click, which a still cannot do.
		if wantsStills, !AppState.shared.isBrowsingMode {
			return .snapshot
		}

		if
			Defaults[.freezeWhenCovered],
			AppState.shared.isEnabled,
			!AppState.shared.isBrowsingMode,
			let website,
			// A website with its own crop already decides what is shown and how big the window is. Two things moving the same window would fight.
			website.crop == nil
		{
			return .managed
		}

		return .full
	}
}
