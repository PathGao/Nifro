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

	private var cancellables = Set<AnyCancellable>()

	private var excludedMenuItems: Set<MenuItemIdentifier> = [
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

			return excludedMenuItems.contains(identifier)
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
		guard let url else {
			return nil
		}

		// The query goes, unlike the scroll position and the remembered address: how far in a page is
		// zoomed is a property of the page, and `?tab=2` is the same page at the same size.
		return .init(PerPageDefaults.zoomLevel.key(for: url, removeQuery: true))
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

	var zoomLevelWrapper: Double {
		get { zoomLevelDefaultsValue ?? pageZoom }
		set {
			pageZoom = newValue

			if let zoomLevelDefaultsKey {
				Defaults[zoomLevelDefaultsKey] = newValue
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
