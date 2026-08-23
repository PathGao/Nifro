import Cocoa
import KeyboardShortcuts

extension AppState {
	func setUpEvents() {
		menu.onUpdate = { [self] in
			updateMenu()
		}

		menu.onOpen = {
			KeyboardShortcuts.disable(KeyboardShortcuts.Name.all)
		}

		menu.onClose = {
			KeyboardShortcuts.enable(KeyboardShortcuts.Name.all)
		}

		powerSourceWatcher?.didChangePublisher
			.sink { [self] _ in
				guard Defaults[.deactivateOnBattery] else {
					return
				}

				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.freezeWhenCovered, options: [])
			.sink { [self] _ in
				for scene in scenes {
					scene.applyVisibilityState()
				}
			}
			.store(in: &cancellables)

		// Plugging or unplugging a display changes how many wallpapers there should be.
		NSScreen.publisher
			.sink { [self] in
				rebuildScenes()
			}
			.store(in: &cancellables)

		Defaults.publisher(.contentRulesURL)
			.sink { [self] _ in
				Task {
					await ContentRules.refresh()
					recreateWebViewAndReload()
				}
			}
			.store(in: &cancellables)

		SSEvents.deviceDidWake
			.sink { [self] in
				// Some pages hold state that a reload throws away, such as a signed-in dashboard mid-view, or a page that took a while to settle. Plash#127.
				guard Defaults[.reloadOnWake] else {
					return
				}

				reloadWebsite()
			}
			.store(in: &cancellables)

		SSEvents.isScreenLocked
			.sink { [self] in
				isScreenLocked = $0
				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.websites, options: [])
			.receive(on: DispatchQueue.main)
			.sink { [self] in
				// Sound is the one setting people change while looking at the thing it applies to, and
				// it is the one the page can be told about without being rebuilt. Everything else is
				// baked into the page when it is created, so everything else needs a new one.
				if differOnlyInAudio($0.oldValue, $0.newValue) {
					applyAudioSetting()
					return
				}

				resetTimer()
				recreateWebViewAndReload()

				// We never destroy the webview, so we have to make sure it's not in browsing mode when there are no websites.
				if $0.newValue.isEmpty {
					Defaults[.isBrowsingMode] = false
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.isBrowsingMode)
			.receive(on: DispatchQueue.main)
			.sink { [self] change in
				isBrowsingMode = change.newValue
			}
			.store(in: &cancellables)

		Defaults.publisher(.hideMenuBarIcon)
			.sink { [self] _ in
				handleMenuBarIcon()
			}
			.store(in: &cancellables)

		Defaults.publisher(.opacity)
			.sink { [self] _ in
				for scene in scenes {
					scene.applyOpacity()
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.dimWhenUnfocused, options: [])
			.sink { [self] _ in
				for scene in scenes {
					scene.applyOpacity()
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.dimmedOpacityFactor, options: [])
			.sink { [self] _ in
				for scene in scenes {
					scene.applyOpacity()
				}
			}
			.store(in: &cancellables)

		NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
			.sink { [self] _ in
				for scene in scenes {
					scene.applyOpacity()
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.playlistInterval, options: [])
			.sink { [self] _ in
				for scene in scenes {
					scene.resetPlaylistTimer()
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.reloadInterval)
			.sink { [self] _ in
				resetTimer()
			}
			.store(in: &cancellables)

		Defaults.publisher(.display, options: [])
			.sink { [self] _ in
				rebuildScenes()
			}
			.store(in: &cancellables)

		Defaults.publisher(.deactivateOnBattery)
			.sink { [self] _ in
				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.showOnAllSpaces)
			.sink { [self] change in
				for scene in scenes {
					scene.window.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: change.newValue)
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.bringBrowsingModeToFront, options: [])
			.sink { [self] _ in
				for scene in scenes {
					scene.window.isInteractive = scene.window.isInteractive
				}
			}
			.store(in: &cancellables)

		holdToInteract.install()

		KeyboardShortcuts.onKeyUp(for: .toggleBrowsingMode) {
			Defaults[.isBrowsingMode].toggle()
		}

		KeyboardShortcuts.onKeyUp(for: .toggleSound) {
			guard let website = WebsitesController.shared.current else {
				return
			}

			WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
				$0.audio = $0.audio == .unmuted ? .muted : .unmuted
			}
		}

		KeyboardShortcuts.onKeyUp(for: .chooseRegion) { [self] in
			beginCropSelection()
		}

		KeyboardShortcuts.onKeyUp(for: .toggleEnabled) { [self] in
			isManuallyDisabled.toggle()
		}

		KeyboardShortcuts.onKeyUp(for: .reload) { [self] in
			reloadWebsite()
		}

		KeyboardShortcuts.onKeyUp(for: .nextWebsite) {
			WebsitesController.shared.makeNextCurrent()
		}

		KeyboardShortcuts.onKeyUp(for: .previousWebsite) {
			WebsitesController.shared.makePreviousCurrent()
		}

		KeyboardShortcuts.onKeyUp(for: .randomWebsite) {
			WebsitesController.shared.makeRandomCurrent()
		}
	}
}
