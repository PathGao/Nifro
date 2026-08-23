import Cocoa
import KeyboardShortcuts

extension AppState {
	func setUpEvents() {
		menu.onUpdate = { [self] in
			updateMenu()
		}

		menu.onOpen = {
			KeyboardShortcuts.disable(Shortcut.allNames)
		}

		menu.onClose = {
			KeyboardShortcuts.enable(Shortcut.allNames)
		}

		powerSourceWatcher?.didChangePublisher
			.sink { [self] _ in
				guard Defaults[.deactivateOnBattery] else {
					return
				}

				setEnabledStatus()
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
					applyWebsiteChanges()
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
				// Sound and the framed region are the settings people change while looking at the thing
				// they apply to, and they are the two the page already up can absorb. Everything else is
				// baked into the page when it is created, so everything else needs a new one.
				if differOnlyInLiveSettings($0.oldValue, $0.newValue) {
					applyLiveSettings()
					return
				}

				resetTimer()
				applyWebsiteChanges()

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

		Shortcut.install()
	}
}
