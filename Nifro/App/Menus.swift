import Cocoa

extension AppState {
	private func addInfoMenuItem() {
		guard let website = WebsitesController.shared.current else {
			return
		}

		var url = website.url
		do {
			url = try replacePlaceholders(of: url) ?? url
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
				let url = webViewController.webView.url?.normalized(),
				website.url.normalized() != url
			{
				let menuItem = menu.addCallbackItem("Update Website to Current") {
					WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
						$0.url = url
					}
				}

				menuItem.toolTip = "Updates the URL for the stored website in Nifro to the current URL"
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
			menu.addCallbackItem("Choose Crop Region…") { [self] in
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

	Only shown when there is more than one display: on a single-display Mac the choice does not exist, and a menu item that always says the same thing is noise. Buried in Settings it is a chore for anyone who docks and undocks a laptop several times a day (Plash#195).
	*/
	private func addDisplayItemIfNeeded() {
		let displays = Display.all

		guard displays.count > 1 else {
			return
		}

		menu.addSeparator()

		let submenu = SSMenu()
		let chosen = Defaults[.display]?.withFallbackToMain ?? Display.main

		for display in displays {
			submenu.addCallbackItem(
				display.localizedName,
				isChecked: display == chosen
			) {
				Defaults[.display] = display
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
		}

		menu.addSeparator()

		// Right under the on/off switch: this is where someone who has nothing set up yet, or wants something new up there, is actually headed. Opens in the app — the whole value of the catalogue is the settings that come with each entry, and sending people to a web page to copy those by hand would be asking them to redo work somebody already did.
		menu.addCallbackItem("Site Gallery…") {
			Constants.openSiteGalleryWindow()
		}

		menu.addSeparator()

		if isEnabled {
			addWebsiteItems()
		} else if !isManuallyDisabled {
			menu.addDisabled("Deactivated While on Battery")
		}

		// Adding and managing websites has nothing to do with whether the wallpaper is currently showing. Leaving them out while disabled meant the app offered no way to set anything up until you turned it back on.
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
