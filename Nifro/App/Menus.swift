import Cocoa

extension AppState {
	/**
	Which website this all applies to, and the way into its settings.

	Under the switch, because the switch is about this website: "Disable" and the name of the thing
	being disabled belong to each other.

	A real item rather than a label. It was a disabled one, and disabled is drawn grey however the
	title is coloured — grey says "you cannot have this" where the point is "this is the one you
	have". Making it do something removes the argument: it opens this website's settings, which is
	what a name in a menu invites you to click, and it takes the place of the separate "Edit…" that
	used to sit four items below its own subject.

	The dot is the state the switch above it is in — green while the wallpaper is showing, hollow while
	it is not — so the pair reads as one statement instead of two.
	*/
	/**
	Says a newer version exists, and only then.

	Reads what the last check wrote; it never checks. The menu is torn down and rebuilt on every open,
	so a check started here would be a network request every time somebody looked at their websites.

	This is the whole of the announcement, on purpose. Sparkle's guidance for background apps is to
	stay out of the way — no dialog, no stolen focus — and an app with no Dock icon has no badge to
	put a number on either. So it waits in the menu, which is the only place this app is ever looked
	at, and says nothing anywhere else.
	*/
	private func addUpdateItemIfNeeded() {
		guard
			let latest = Defaults[.latestKnownVersion],
			UpdateCheck.isNewer(latest, than: SSApp.version)
		else {
			return
		}

		menu.addCallbackItem(String(localized: "Update to \(latest)…")) {
			Constants.latestReleaseURL.open()
		}
	}

	private func addInfoMenuItem() {
		guard
			let website = currentWebsite,
			!website.menuTitle.isEmpty
		else {
			return
		}

		do {
			_ = try primaryScene.replacePlaceholders(of: website.url)
		} catch {
			error.presentAsModal()
			return
		}

		let menuItem = menu.addCallbackItem(website.menuTitle.truncating(to: 30)) {
			Constants.openWebsitesWindow()

			// TODO: Find a better way to do this.
			NotificationCenter.default.post(name: .showEditWebsiteDialog, object: nil)
		}

		menuItem.image = Self.statusDot(isOn: isEnabled)
		menuItem.toolTip = "\(website.tooltip)\n \n\(String(localized: "Click to edit this website."))"
	}

	/**
	A dot the size of the text beside it, filled while the wallpaper is showing and outlined while it
	is not.
	*/
	private static func statusDot(isOn: Bool) -> NSImage? {
		let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
			.applying(NSImage.SymbolConfiguration(paletteColors: [isOn ? .systemGreen : .tertiaryLabelColor]))

		return NSImage(
			systemSymbolName: isOn ? "circle.fill" : "circle",
			accessibilityDescription: isOn ? String(localized: "Showing") : String(localized: "Not showing")
		)?
		.withSymbolConfiguration(configuration)
	}

	/**
	Every website, across every display, with this display's one ticked.

	Deliberately the whole list rather than this display's share of it: picking a website that lives
	on another screen is how you move the wallpaper there without going into Settings first, and the
	tick answers "which one am I looking at" for the screen the menu bar is on.
	*/
	private func createSwitchMenu() -> SSMenu {
		let menu = SSMenu()

		for website in WebsitesController.shared.all {
			let menuItem = menu.addCallbackItem(
				website.menuTitle.truncating(to: 40),
				isChecked: website.id == currentWebsite?.id
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

		if !WebsitesController.shared.all.isEmpty {
			menu.addCallbackItem(
				String(localized: "Reload"),
				isEnabled: currentWebsite != nil
			) {
				Action.reload.run()
			}
			.setShortcut(for: Shortcut.reload.name)

			if
				let website = currentWebsite,
				let url = primaryScene.webViewController.webView.navigatedURL(for: website)
			{
				let menuItem = menu.addCallbackItem(String(localized: "Update Website to Current")) {
					WebsitesController.shared.update(website.id) {
						$0.url = url
					}
				}

				menuItem.toolTip = String(localized: "Points the stored website at the URL currently loaded")
			}

			menu.addCallbackItem(
				String(localized: "Browsing Mode"),
				isEnabled: currentWebsite != nil,
				isChecked: Defaults[.isBrowsingMode]
			) {
				Action.toggleBrowsingMode.run()
			}
			.setShortcut(for: Shortcut.toggleBrowsingMode.name)

			if let website = currentWebsite {
				menu.addCallbackItem(
					String(localized: "Sound"),
					isChecked: website.audio == .unmuted
				) {
					Action.toggleSound.run()
				}
				.setShortcut(for: Shortcut.toggleSound.name)

				menu.items.last?.toolTip = String(localized: "Whether this website is allowed to make noise. Remembered per website, so a clock stays silent and a live stream does not.")
			}
		}

		// Its own section. Framing a region is usually not a single attempt, so the way back has to sit
		// next to the way in rather than in a settings window.
		if let website = currentWebsite {
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
				WebsitesController.shared.update(website.id) {
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
			let website = currentWebsite
		else {
			return
		}

		menu.addSeparator()

		let submenu = SSMenu()

		submenu.addCallbackItem(
			String(localized: "Default display"),
			isChecked: website.display == nil
		) {
			WebsitesController.shared.update(website.id) {
				$0.display = nil
			}
		}

		for display in displays {
			submenu.addCallbackItem(
				display.localizedName,
				isChecked: website.display == display
			) {
				WebsitesController.shared.update(website.id) {
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

		addUpdateItemIfNeeded()
		addInfoMenuItem()

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

		// Next to Settings: both open a window of the app rather than doing something to the wallpaper.
		// It opens in the app rather than in a browser because each entry carries the settings that make
		// its page work.
		menu.addCallbackItem(String(localized: "Site Gallery…")) {
			Constants.openSiteGalleryWindow()
		}

		menu.addSettingsItem()

		menu.addSeparator()

		menu.addQuitItem()
	}
}
