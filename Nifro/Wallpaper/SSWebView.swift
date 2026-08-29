import WebKit

final class SSWebView: WKWebView {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	/**
	The scene this web view draws into. Weak because the scene owns it, through its controller.

	Here so the page can be told whether *its* display is in Browsing Mode. It was removed once, when
	the only thing that read it was a context-menu item that has since gone — and came straight back
	when Browsing Mode stopped being one flag for the whole app.
	*/
	weak var scene: WallpaperScene?

	/**
	The website entry this web view was built for.

	Held here rather than read off `scene?.website` at the moment it is wanted, because that is where
	the scene is *heading*: during a swap it is already the incoming website while this view still has
	the outgoing page. Set once, next to the data store, and for the same value — what the page
	remembers has to be filed under the same `id` as the store the page loaded from, or two entries on
	one address share their scroll and zoom while having separate storage.
	*/
	var websiteID: Website.ID?

	/**
	The MIME type the server gave for the document this web view is currently showing.

	Belongs to one navigation, and lives on the web view because a navigation happens inside one. It
	was a single slot on `WebViewController`, which is neither: the controller is one per display and
	outlives every page it shows, while a swap keeps two web views alive at once and both of them
	report through that one controller as their navigation delegate. So a replacement loading out of
	sight answered "is this page an image?" for the page already on screen — and whichever of the two
	finished last decided it for both.

	Cleared when a navigation starts rather than only overwritten when one produces an
	`HTTPURLResponse`, because the loads that produce none are exactly the ones that were reading
	somebody else's answer: a local folder, and the host page a framed player is loaded into. Left to
	inherit, a bare image followed by either of those centres and crops a page that is not an image,
	and the reverse order leaves a real image sitting in the corner at its natural size.
	*/
	var responseMIMEType: String?

	private var cancellables = Set<AnyCancellable>()

	private static let excludedMenuItems: Set<MenuItemIdentifier> = [
		.downloadImage,
		.downloadLinkedFile,
		.downloadMedia,
		.openLinkInNewWindow,
		.shareMenu,
		.toggleEnhancedFullScreen,
		.toggleFullScreen
	]

	override init(frame: CGRect, configuration: WKWebViewConfiguration) {
		super.init(frame: frame, configuration: configuration)

		Defaults.publisher(.browsingDisplays)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				self?.toggleBrowsingModeClass()
			}
			.store(in: &cancellables)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		// A wallpaper has no windows to open things in, so the items that say "in New Window" are
		// renamed to what they actually do here.
		//
		// Matched on the identifier alone. The previous version also checked the title against the
		// English wording, which is WebKit's own localised string: on a Mac running in any other
		// language nothing matched and every item kept saying "in New Window".
		let renamed: [MenuItemIdentifier: String] = [
			.openImageInNewWindow: String(localized: "Open Image"),
			.openMediaInNewWindow: String(localized: "Open Video"),
			.openFrameInNewWindow: String(localized: "Open Frame"),
			.openLinkInNewWindow: String(localized: "Open Link")
		]

		for menuItem in menu.items {
			guard
				let identifier = MenuItemIdentifier(menuItem),
				let title = renamed[identifier]
			else {
				continue
			}

			menuItem.title = title
		}

		menu.items.removeAll {
			guard let identifier = MenuItemIdentifier($0) else {
				return false
			}

			return Self.excludedMenuItems.contains(identifier)
		}

		menu.addSeparator()

		menu.addCallbackItem(String(localized: "Actual Size"), isEnabled: pageZoom != 1) { [weak self] in
			self?.zoomLevelWrapper = 1
		}

		menu.addCallbackItem(String(localized: "Zoom In")) { [weak self] in
			self?.zoomLevelWrapper += 0.2
		}

		menu.addCallbackItem(String(localized: "Zoom Out")) { [weak self] in
			self?.zoomLevelWrapper -= 0.2
		}

		menu.addSeparator()

		// Move the “Inspect Element” menu item to the end.
		if let menuItem = (menu.items.first { MenuItemIdentifier($0) == .inspectElement }) {
			menu.items = menu.items.movingToEnd(menuItem)
		}

		if Defaults[.hideMenuBarIcon] {
			menu.addCallbackItem(String(localized: "Show Menu Bar Icon")) {
				AppState.shared.handleMenuBarIcon()
			}
		}

		// For the implicit “Services” menu.
		menu.addSeparator()
	}

	func toggleBrowsingModeClass() {
		// This page's own display, not any display: a page that styles itself for Browsing Mode should
		// do it when *it* is the one being interacted with, not when the other screen is.
		let method = AppState.shared.isBrowsingMode(on: scene?.display) ? "add" : "remove"

		// The async variant hands back `Any`, which cannot cross an actor boundary under Swift 6. Nothing here needs the result.
		evaluateJavaScript(
			"""
			document.documentElement.classList.\(method)("nifro-is-browsing-mode");
			""",
			in: nil,
			in: .page,
			completionHandler: nil
		)
	}
}

extension SSWebView {
	private var zoomLevelDefaultsKey: Defaults.Key<Double?>? {
		guard let websiteID else {
			return nil
		}

		return .init(PerPageDefaults.zoomLevel.key(for: websiteID))
	}

	private var zoomLevelDefaultsValue: Double? {
		guard
			let zoomLevelDefaultsKey,
			let zoomLevel = Defaults[zoomLevelDefaultsKey]
		else {
			return nil
		}

		return zoomLevel
	}

	/**
	The zoom level of this page, applied to the view and remembered for the address.

	Bounded on the way in rather than at the three menu items, because this setter is where every one
	of them ends up — and so does `restoreZoomLevel`, which reads the stored level and writes it back
	on every load. Clamping here therefore also repairs a page left at 0 or below by a version that
	did not clamp: the next load stores a level that can be seen again, without the user having to
	find Actual Size in a menu they cannot reach until the wallpaper is raised.
	*/
	var zoomLevelWrapper: Double {
		get { zoomLevelDefaultsValue ?? pageZoom }
		set {
			let level = PageZoom.clamped(newValue)
			pageZoom = level

			if let zoomLevelDefaultsKey {
				Defaults[zoomLevelDefaultsKey] = level
			}
		}
	}
}

extension WKWebView {
	/**
	Where the page has ended up, when that is not where the website says it should be. `nil` when there
	is nothing worth remembering.

	Used to record where a page was so it can be put back after a reload — a map that was dragged, a
	dashboard on a particular tab. It used to also drive a menu item that wrote this into the stored
	website permanently; that is gone, because a website plus its snapshot already describes what is
	on screen, and a page that moves itself is the snapshot's business rather than an edit the user
	should be asked to make.

	A framed player is excluded. It is shown inside a page this app builds, and that page's address is
	this app's, not anywhere anybody went.
	*/
	func navigatedURL(for website: Website) -> URL? {
		guard
			VideoEmbed.hostPage(for: website.url) == nil,
			let current = url?.normalized(),
			website.url.normalized() != current
		else {
			return nil
		}

		return current
	}
}
