import AppKit
import WebKit
import Combine

/**
One wallpaper. A window on one display, the web view inside it, and everything that decides what that web view is doing.

All of this used to be singletons on `AppState`, one window and one web view and one current website, which blocked every feature that needs more than one of anything. A different page per display, the most-asked-for thing in the upstream tracker, could not be built at all. Rotation could not run two pages at once.

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
	var pendingWebView: SSWebView? {
		didSet {
			loadingStateChanged()
		}
	}

	var pendingLoad: Task<Void, Never>?

	/**
	The website whose page is actually on screen, as it stood when the page was loaded.

	`website` is where the scene is heading; this is where it is. The two differ for as long as a
	replacement takes to load out of sight, which is the whole point of swap loading.

	The whole value, not just the identity, so `applyWebsiteChanges` can tell "this scene already
	shows exactly this" from "this scene shows an older version of it" and skip the reload in the
	first case.
	*/
	private(set) var loadedWebsite: Website? {
		didSet {
			loadingStateChanged()
		}
	}

	var loadedWebsiteID: Website.ID? { loadedWebsite?.id }

	/**
	Whether the page for the current load has been put on screen yet.
	*/
	private(set) var hasRevealedPage = false {
		didSet {
			loadingStateChanged()
		}
	}

	/**
	Whether a page is on its way to this display right now.

	Switching website takes a few seconds and said nothing while it did. Swap loading keeps the old
	page up for all of it — which is the point — so the wallpaper cannot be the thing that reports it,
	and choosing a website and watching an unchanged desktop reads as the choice not having
	registered. Two things report it, and this is the only state either of them reads: the panel's
	chooser for this column, which names the display, and the menu bar icon, which does not but is on
	screen when the panel is not — a website switched by keyboard shortcut, by rotation, from the
	Websites window or from a Shortcuts intent happens with the panel closed, which is nearly always.

	Read rather than counted. There was a counter on `AppState`, incremented and decremented around
	each load, and it could be left behind: on the plain-load path `load` can run twice before a
	single reveal, and revealing is idempotent, so the second increment never got its decrement and
	the icon pulsed until the app was quit. Both loading paths already keep a piece of state saying a
	page is outstanding. Derived from those, it cannot disagree with them and there is no pairing to
	get wrong.

	`pendingWebView` covers the swap: it is set for as long as a replacement is being fetched out of
	sight, and cleared by whoever finishes, fails or is cancelled.

	The second clause covers the plain load, which is the first load of the session or the one after
	nothing was showing — `load` adopts the website and clears `hasRevealedPage`, and `revealPage` sets
	it again when the page goes up, on the load settling either way or on the backstop behind it. The
	`loadedWebsite` check is what keeps a scene that has never loaded anything, or one that was
	suspended, from reading as busy: both leave it `nil`.
	*/
	var isLoading: Bool {
		pendingWebView != nil || (loadedWebsite != nil && !hasRevealedPage)
	}

	/**
	How long a page is given to finish before the app stops believing it will.

	One number for both loading paths, because they ask the same question about the same kind of
	page. A swap gives up and keeps what is on screen; a plain load has nothing to keep, so it puts
	up whatever the page has painted by then.

	It used to be five seconds on the plain load and thirty on the swap. Five is not a backstop:
	measured on a cold launch, it beat `didFinish` on an ordinary site by six seconds, so what the
	user got as their wallpaper was whatever the page happened to have drawn at the five-second mark,
	and the rest of it appeared afterwards. A backstop that outruns the thing it is backing up is not
	a backstop, it is a shorter and worse schedule.
	*/
	static let loadTimeout = Duration.seconds(30)

	/**
	How long one stroke of the "a page is on its way" pulse takes.

	One animation shows it: the menu bar icon, in `NSStatusBarButton.setShowingActivity`. It breathes
	once every `2 * loadingPulseDuration`, easing in and out.

	It was two. The panel drew a pill behind its website chooser and animated it on this same constant,
	so the two would read as one thing happening rather than two; the panel shows a stock `ProgressView`
	now, which paces itself. A status item is the one surface with nothing system-drawn to reach for, so
	this is what is left.

	Here rather than in the menu bar's own file because it is a fact about the state being drawn, not
	about the status item — `previewWidth` below is a drawing number kept here for the same reason.
	*/
	static let loadingPulseDuration = 0.7

	/**
	Re-ask the menu bar whether anything is loading.

	`isLoading` is computed, so nothing is published when it moves and every watcher would otherwise
	have to be told by hand at each of the six places its inputs are written — `load`, `revealPage`,
	the backstop, the swap starting, the swap finishing, and `releaseWebView`. Told by hand is told
	from a list, and a list is what the seventh writer forgets.

	So this hangs off `didSet` on the three stored properties `isLoading` reads, and nothing calls it
	directly. A new place that starts or ends a load cannot avoid going through one of those
	properties — that is what starting or ending a load *is* here — so it cannot avoid this. Whether
	the value actually changed is not checked: `didSet` fires on every assignment, and both sides of
	this are cheap and idempotent.

	The panel needs no equivalent. It rebuilds every column from the scenes about twelve times a
	second while it is open, and reads `isLoading` fresh each time.
	*/
	private func loadingStateChanged() {
		AppState.shared.refreshLoadingIndicator()
	}

	private var reloadTimer: Timer?
	var rotationTimer: Timer?

	/**
	Minutes since this display last moved to another website.

	The rotation timer ticks once a minute whatever the display's interval is, because the schedule has
	to be looked at that often regardless — see `resetRotationTimer`. This is what turns those ticks
	back into the interval the user asked for.
	*/
	var rotationMinutes = 0

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
					AppState.shared.refreshStatusItemTooltip()
				case .failure(let error):
					AppState.shared.setWebViewError(error, on: display)
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

	Does nothing at all while this display is being framed. Passing `nil` for the region was not
	enough: `content`'s observer fires on assignment rather than on change, so writing the same value
	still reaches `applyContent`, which reassigns `window.contentView` — and the framing overlay is a
	subview of the view being replaced, so it goes with it while `isSelectingCrop` stays true and the
	mode can no longer be left. Everything that reloads, switches website or edits the list comes back
	through here, and a rebuild runs on every display change and every wake, so framing had a few
	seconds to survive rather than as long as the user needed.

	`beginCropSelection` has already set the page to `.live(zoom: nil)`, and it holds until
	`finishCropSelection` calls this again with the flag cleared. That is the whole of what framing
	needs from this method: the page holds still, or the frame's magnification multiplies with the
	page's and one drag appears to do two different amounts of the same thing.
	*/
	func installContentView() {
		guard !window.isFramingRegion else {
			return
		}

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
		AppState.shared.setWebViewError(nil, on: display)

		guard
			// Nothing is watching this display, so nothing should be fetched for it. Loading is what
			// made the other two symptoms possible: it sets `loadedWebsite`, which is what let the
			// panel photograph the page, and it reveals it, which is what let the menu bar band sample
			// a colour off it. `reloadWebsite` reaches every scene unconditionally, including the one
			// `rebuildScenes` suspended a line earlier.
			!isSwitchedOff,
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

		// Only for a page that settles neither way. A load that finishes or fails reveals the page
		// itself — see `WebViewController.pageDidSettle` — so what is left is a main frame that never
		// stops loading at all, which is real: `loadAndWait` polls for the same reason. Without this
		// the desktop would keep whatever was behind the wallpaper for as long as the app ran.
		delay(Self.loadTimeout) { [weak self] in
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

	Driven by the load settling now — finished or failed — with a backstop behind it for the page that
	does neither. Unhides the web view itself rather than whatever view is installed by then: the page
	may be inside a wrapper, and unhiding the wrapper would leave the real web view hidden for the
	rest of the session, which is a blank wallpaper with no way back.
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

		// This display's own Browsing Mode, not the app's — the same argument `resetRotationTimer` makes
		// beside the same guard: a reload throws away a form somebody is filling in, and only the
		// display they are filling it in on has one.
		guard
			!isSwitchedOff,
			!AppState.shared.isBrowsingMode(on: display),
			let reloadInterval = website?.effectiveReloadInterval
		else {
			return
		}

		reloadTimer = Timer.scheduledTimer(withTimeInterval: reloadInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.reload()
			}
		}

		// A tenth of the interval, the same argument `resetRotationTimer` makes beside its own timer:
		// zero tolerance means macOS may not coalesce this with anything, and this one also runs for
		// the life of the app on every display. Proportional rather than a fixed number of seconds
		// because this interval is the user's, from one second to whatever they typed, and a tenth is
		// the floor Apple's guidance suggests. Nobody can see a wallpaper reload arrive late by a tenth
		// of the gap between reloads.
		reloadTimer?.tolerance = reloadInterval / 10
	}

	// MARK: - Appearance

	func applyOpacity(animated: Bool = true) {
		// A page being framed is shown at full strength, because what is being framed has to be
		// visible while it is chosen. `beginCropSelection` sets that, and `rebuildScenes` calls this on
		// every scene a runloop turn later — so the page dimmed a moment after the mode began.
		// `finishCropSelection` clears the flag before it puts the opacity back.
		guard !window.isFramingRegion else {
			return
		}

		let target = AppState.shared.targetOpacity(on: display)
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
	How wide the panel draws a preview. Snapshots are taken at this size rather than the display's.
	*/
	static let previewWidth = 260

	/**
	A picture of what this display is showing right now.

	Taken from our own web view, which needs no permission at all — this is the app photographing its
	own view, not the screen. Screen Recording would be the other way to get this, and asking a
	wallpaper app for it to draw a thumbnail is a trade nobody should have to make.

	`nil` when there is nothing to photograph: this display is switched off, it has no website, or its
	page has not arrived yet. The panel draws its own reading for each rather than a blank rectangle
	that looks like a broken page.

	The first of those is not covered by the other two. A switched-off display keeps its website, and
	the load that should never have happened left `loadedWebsite` set — so this went on handing the
	panel a live, moving photograph of a page the user had switched off, which is what they saw and
	reported. `isSwitchedOff` is the same question the load path now asks; with loading refused this
	is belt and braces, and it is the cheap half of the pair.
	*/
	func snapshot() async -> NSImage? {
		guard
			!isSwitchedOff,
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
		rotationTimer?.invalidate()
		rotationTimer = nil
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
		rotationTimer?.invalidate()
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
