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
			menu.addDisabled(String(localized: "Error: \(webViewError.localizedDescription)").wordWrapped(atLength: 36).toNSAttributedString)
			menu.addSeparator()
		}

		addInfoMenuItem()

		menu.addSeparator()

		if !WebsitesController.shared.all.isEmpty {
			menu.addCallbackItem(
				String(localized: "Reload"),
				isEnabled: WebsitesController.shared.current != nil
			) {
				Action.reload.run()
			}
			.setShortcut(for: Shortcut.reload.name)

			if
				let website = WebsitesController.shared.current,
				let url = primaryScene.webViewController.webView.navigatedURL(for: website)
			{
				let menuItem = menu.addCallbackItem(String(localized: "Update Website to Current")) {
					WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
						$0.url = url
					}
				}

				menuItem.toolTip = String(localized: "Points the stored website at the URL currently loaded")
			}

			menu.addCallbackItem(
				String(localized: "Browsing Mode"),
				isEnabled: WebsitesController.shared.current != nil,
				isChecked: Defaults[.isBrowsingMode]
			) {
				Action.toggleBrowsingMode.run()
			}
			.setShortcut(for: Shortcut.toggleBrowsingMode.name)

			if let website = WebsitesController.shared.current {
				menu.addCallbackItem(
					String(localized: "Sound"),
					isChecked: website.audio == .unmuted
				) {
					Action.toggleSound.run()
				}
				.setShortcut(for: Shortcut.toggleSound.name)

				menu.items.last?.toolTip = String(localized: "Whether this website is allowed to make noise. Remembered per website, so a clock stays silent and a live stream does not.")
			}

			menu.addCallbackItem(
				String(localized: "Edit…"),
				isEnabled: WebsitesController.shared.current != nil
			) {
				Constants.openWebsitesWindow()

				// TODO: Find a better way to do this.
				NotificationCenter.default.post(name: .showEditWebsiteDialog, object: nil)
			}
		}

		// Its own section. Framing a region is usually not a single attempt, so the way back has to sit
		// next to the way in rather than in a settings window.
		if let website = WebsitesController.shared.current {
			menu.addSeparator()

			menu.addCallbackItem(String(localized: "Choose Region…")) {
				Action.chooseRegion.run()
			}
			.setShortcut(for: Shortcut.chooseRegion.name)

			menu.items.last?.toolTip = String(localized: "Move the wallpaper until it shows what you want. Drag or scroll to move it, pinch to zoom.")

			menu.addCallbackItem(
				String(localized: "Show Whole Page"),
				isEnabled: website.zoom != nil
			) {
				WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
					$0.zoom = nil
				}
			}
			.toolTip = String(localized: "Undo the region and go back to the whole page.")
		}

		menu.addSeparator()

		if WebsitesController.shared.all.count > 1 {
			menu.addCallbackItem(String(localized: "Next")) {
				Action.nextWebsite.run()
			}
			.setShortcut(for: Shortcut.nextWebsite.name)

			menu.addCallbackItem(String(localized: "Previous")) {
				Action.previousWebsite.run()
			}
			.setShortcut(for: Shortcut.previousWebsite.name)

			menu.addCallbackItem(String(localized: "Random")) {
				Action.randomWebsite.run()
			}
			.setShortcut(for: Shortcut.randomWebsite.name)

			menu.addItem(String(localized: "Switch"))
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
			String(localized: "Default display"),
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

		menu.addItem(String(localized: "Show on"))
			.withSubmenu(submenu)
	}

	func updateMenu() {
		menu.removeAllItems()

		if (isEnabled || isManuallyDisabled) || (!Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == false) {
			menu.addCallbackItem(
				isManuallyDisabled ? String(localized: "Enable") : String(localized: "Disable")
			) {
				Action.toggleEnabled.run()
			}
			.setShortcut(for: Shortcut.toggleEnabled.name)
		}

		menu.addSeparator()

		// Right under the on/off switch, where someone with nothing set up yet looks first. It opens in the app rather than the browser because each catalogue entry carries the settings that make the page work. A web page would leave people copying those in by hand.
		menu.addCallbackItem(String(localized: "Site Gallery…")) {
			Constants.openSiteGalleryWindow()
		}

		menu.addSeparator()

		if isEnabled {
			addWebsiteItems()
		} else if !isManuallyDisabled {
			menu.addDisabled(String(localized: "Deactivated While on Battery"))
		}

		// Adding and managing websites works whether or not the wallpaper is showing. Leaving these out while disabled left the app with no way to set anything up until you turned it back on.
		menu.addSeparator()

		menu.addCallbackItem(String(localized: "Add Website…")) {
			Constants.openWebsitesWindow()

			// TODO: Find a better way to do this.
			NotificationCenter.default.post(name: .showAddWebsiteDialog, object: nil)
		}

		menu.addCallbackItem(String(localized: "Manage Websites…")) {
			Constants.openWebsitesWindow()
		}

		addDisplayItemIfNeeded()

		menu.addSeparator()

		menu.addSettingsItem()

		menu.addSeparator()

		menu.addQuitItem()
	}
}
