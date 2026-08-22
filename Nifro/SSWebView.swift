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
		for menuItem in menu.items {
			// Debug menu items
			// print("Menu Item:", menuItem.title, menuItem.identifier?.rawValue ?? "")

			if let identifier = MenuItemIdentifier(menuItem) {
				if
					identifier == .openImageInNewWindow,
					menuItem.title == "Open Image in New Window"
				{
					menuItem.title = "Open Image"
				}

				if
					identifier == .openMediaInNewWindow,
					menuItem.title == "Open Video in New Window"
				{
					menuItem.title = "Open Video"
				}

				if
					identifier == .openFrameInNewWindow,
					menuItem.title == "Open Frame in New Window"
				{
					menuItem.title = "Open Frame"
				}

				if
					identifier == .openLinkInNewWindow,
					menuItem.title == "Open Link in New Window"
				{
					menuItem.title = "Open Link"
				}
			}
		}

		menu.items.removeAll {
			guard let identifier = MenuItemIdentifier($0) else {
				return false
			}

			return excludedMenuItems.contains(identifier)
		}

		menu.addSeparator()

		menu.addCallbackItem("Actual Size", isEnabled: pageZoom != 1) { [weak self] in
			self?.zoomLevelWrapper = 1
		}

		menu.addCallbackItem("Zoom In") { [weak self] in
			self?.zoomLevelWrapper += 0.2
		}

		menu.addCallbackItem("Zoom Out") { [weak self] in
			self?.zoomLevelWrapper -= 0.2
		}

		menu.addSeparator()

		if
			let website = WebsitesController.shared.current,
			let url = url?.normalized(),
			website.url.normalized() != url
		{
			let menuItem = menu.addCallbackItem("Update Website to Current") {
				WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
					$0.url = url
				}
			}

			menuItem.toolTip = "Updates the URL for the stored website in Nifro to the current URL"
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
		// `plash-is-browsing-mode` is kept alongside ours so the custom CSS people wrote for Plash over the past five years keeps working.
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

	var zoomLevelDefaultsValue: Double? {
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
