import Cocoa

extension AppState {
	private func addInfoMenuItem() {
		guard let website = WebsitesController.shared.current else {
			return
		}

		var url = website.url
		do {
			url = try primaryScene.replacePlaceholders(of: url) ?? url
		} catch {
			error.presentAsModal()
			return
		}

		let maxLength = 30

		if !website.menuTitle.isEmpty {
			let menuItem = menu.addDisabled(website.menuTitle.truncating(to: maxLength))
			menuItem.toolTip = website.tooltip
		}
	}

	private func createSwitchMenu() -> SSMenu {
		let menu = SSMenu()

		for website in WebsitesController.shared.all {
			let menuItem = menu.addCallbackItem(
				website.menuTitle.truncating(to: 40),
				isChecked: website.isCurrent
			) {
				website.makeCurrent()
			}

			menuItem.toolTip = website.tooltip
		}

		return menu
	}

	private func addWebsiteItems() {
		if let webViewError {
			menu.addDisabled("Error: \(webViewError.localizedDescription)".wordWrapped(atLength: 36).toNSAttributedString)
			menu.addSeparator()
		}

		addInfoMenuItem()

		menu.addSeparator()

		if !WebsitesController.shared.all.isEmpty {
			menu.addCallbackItem(
				"Reload",
				isEnabled: WebsitesController.shared.current != nil
			) { [weak self] in
				self?.reloadWebsite()
			}
			.setShortcut(for: .reload)

			// TODO: DRY this up with the one in SSWebView when everything is in SwiftUI.
			if
				let website = WebsitesController.shared.current,
				let url = primaryScene.webViewController.webView.url?.normalized(),
				website.url.normalized() != url
			{
				let menuItem = menu.addCallbackItem("Update Website to Current") {
					WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
						$0.url = url
					}
				}

				menuItem.toolTip = "Points the stored website at the URL currently loaded"
			}

			menu.addCallbackItem(
				"Browsing Mode",
				isEnabled: WebsitesController.shared.current != nil,
				isChecked: Defaults[.isBrowsingMode]
			) {
				Defaults[.isBrowsingMode].toggle()

				SSApp.runOnce(identifier: "activatedBrowsingMode") {
					DispatchQueue.main.async {
						NSAlert.showModal(
							title: "Browsing Mode lets you temporarily interact with the website. For example, to log into an account or scroll to a specific position on the website.",
							message: "If you don't currently see the website, you might need to hide some windows to reveal the desktop."
						)
					}
				}
			}
			.setShortcut(for: .toggleBrowsingMode)

			menu.addCallbackItem(
				"Edit…",
				isEnabled: WebsitesController.shared.current != nil
			) {
				Constants.openWebsitesWindow()

				// TODO: Find a better way to do this.
				NotificationCenter.default.post(name: .showEditWebsiteDialog, object: nil)
			}
		}

		if WebsitesController.shared.current != nil {
			menu.addCallbackItem("Choose Region…") { [self] in
				beginCropSelection()
			}
			.toolTip = "Drag a rectangle over the wallpaper to keep only that part of the page."
		}

		menu.addSeparator()

		if WebsitesController.shared.all.count > 1 {
			menu.addCallbackItem("Next") {
				WebsitesController.shared.makeNextCurrent()
			}
			.setShortcut(for: .nextWebsite)

			menu.addCallbackItem("Previous") {
				WebsitesController.shared.makePreviousCurrent()
			}
			.setShortcut(for: .previousWebsite)

			menu.addCallbackItem("Random") {
				WebsitesController.shared.makeRandomCurrent()
			}
			.setShortcut(for: .randomWebsite)

			menu.addItem("Switch")
				.withSubmenu(createSwitchMenu())

			menu.addSeparator()
		}

	}

	/**
	Which display to show the wallpaper on, one level down from the menu bar icon.

	Only shown when there is more than one display. A single-display Mac has no choice to make, so the item would always say the same thing. Settings is the wrong place for it, because people who dock and undock a laptop change this several times a day (Plash#195).
	*/
	private func addDisplayItemIfNeeded() {
		let displays = Display.all

		guard
			displays.count > 1,
			let website = WebsitesController.shared.current
		else {
			return
		}

		menu.addSeparator()

		let submenu = SSMenu()

		submenu.addCallbackItem(
			"Default display",
			isChecked: website.display == nil
		) {
			WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
				$0.display = nil
			}
		}

		for display in displays {
			submenu.addCallbackItem(
				display.localizedName,
				isChecked: website.display == display
			) {
				WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
					$0.display = display
				}
			}
		}

		menu.addItem("Show on")
			.withSubmenu(submenu)
	}

	func updateMenu() {
		menu.removeAllItems()

		if (isEnabled || isManuallyDisabled) || (!Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == false) {
			menu.addCallbackItem(
				isManuallyDisabled ? "Enable" : "Disable"
			) { [self] in
				isManuallyDisabled.toggle()
			}
			.setShortcut(for: .toggleEnabled)
		}

		menu.addSeparator()

		// Right under the on/off switch, where someone with nothing set up yet looks first. It opens in the app rather than the browser because each catalogue entry carries the settings that make the page work. A web page would leave people copying those in by hand.
		menu.addCallbackItem("Site Gallery…") {
			Constants.openSiteGalleryWindow()
		}

		menu.addSeparator()

		if isEnabled {
			addWebsiteItems()
		} else if !isManuallyDisabled {
			menu.addDisabled("Deactivated While on Battery")
		}

		// Adding and managing websites works whether or not the wallpaper is showing. Leaving these out while disabled left the app with no way to set anything up until you turned it back on.
		menu.addSeparator()

		menu.addCallbackItem("Add Website…") {
			Constants.openWebsitesWindow()

			// TODO: Find a better way to do this.
			NotificationCenter.default.post(name: .showAddWebsiteDialog, object: nil)
		}

		menu.addCallbackItem("Manage Websites…") {
			Constants.openWebsitesWindow()
		}

		addDisplayItemIfNeeded()

		menu.addSeparator()

		menu.addSettingsItem()

		menu.addSeparator()

		menu.addQuitItem()
	}
}
