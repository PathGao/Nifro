import WebKit

final class SSWebView: WKWebView {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

		Defaults.publisher(.isBrowsingMode)
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

		if
			let website = WebsitesController.shared.current,
			let url = url?.normalized(),
			website.url.normalized() != url
		{
			let menuItem = menu.addCallbackItem(String(localized: "Update Website to Current")) {
				WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
					$0.url = url
				}
			}

			menuItem.toolTip = String(localized: "Points the stored website at the URL currently loaded")
		}

		menu.addSeparator()

		// Move the “Inspect Element” menu item to the end.
		if let menuItem = (menu.items.first { MenuItemIdentifier($0) == .inspectElement }) {
			menu.items = menu.items.movingToEnd(menuItem)
		}

		if Defaults[.hideMenuBarIcon] {
			menu.addCallbackItem("Show Menu Bar Icon") {
				AppState.shared.handleMenuBarIcon()
			}
		}

		// For the implicit “Services” menu.
		menu.addSeparator()
	}

	func toggleBrowsingModeClass() {
		// `plash-is-browsing-mode` stays alongside ours so the custom CSS people wrote for Plash keeps working.
		let method = Defaults[.isBrowsingMode] ? "add" : "remove"

		// The async variant hands back `Any`, which cannot cross an actor boundary under Swift 6. Nothing here needs the result.
		evaluateJavaScript(
			"""
			const list = document.documentElement.classList;
			list.\(method)("nifro-is-browsing-mode");
			list.\(method)("plash-is-browsing-mode");
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

		let keyPart = url
			.normalized(removeFragment: true, removeQuery: true)
			.absoluteString
			.removingSchemeAndWWWFromURL
			.toData
			.base64EncodedString()

		return .init("zoomLevel_\(keyPart)")
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
