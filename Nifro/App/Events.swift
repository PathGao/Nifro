import Cocoa
import Combine
import KeyboardShortcuts

extension AppState {
	func setUpEvents() {
		powerSourceWatcher?.didChangePublisher
			.sink { [self] _ in
				guard Defaults[.deactivateOnBattery] else {
					return
				}

				setEnabledStatus()
			}
			.store(in: &cancellables)

		// Plugging or unplugging a display changes how many wallpapers there should be.
		//
		// `applyWebsiteChanges` rather than `rebuildScenes`, because a scene that has just been built
		// has nothing in it: `rebuildScenes` assigns the website and installs the content view, but the
		// web view is born hidden and only a load reveals it. Plugging in a display that some website
		// names therefore gave that display a permanently blank wallpaper. `applyWebsiteChanges` is the
		// same rebuild followed by a load of exactly the scenes whose page is not already the right
		// one, so it costs nothing on the screens that did not change.
		NSScreen.publisher
			.sink { [self] in
				applyWebsiteChanges()
			}
			.store(in: &cancellables)

		// Sends its current value on subscribe, which is also what puts the first page on screen at
		// launch. Rebuilding everything is right either way: the compiled rule list is baked into a web
		// view when the web view is made, so a new one only reaches a page that is made again — and no
		// website changed, so `applyWebsiteChanges` would correctly reload nothing.
		Defaults.publisher(.contentRulesURL)
			.sink { [self] _ in
				Task {
					await ContentRules.refresh()
					reloadEverything()
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

		// Four things decide how see-through the wallpaper is, and the answer to all four is the same
		// one line. Written out four times, a fifth input is a fifth chance to forget it.
		Publishers.MergeMany(
			Defaults.publisher(.opacity).map { _ in }.eraseToAnyPublisher(),
			Defaults.publisher(.dimWhenUnfocused, options: []).map { _ in }.eraseToAnyPublisher(),
			Defaults.publisher(.dimmedOpacityFactor, options: []).map { _ in }.eraseToAnyPublisher(),
			NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).map { _ in }.eraseToAnyPublisher()
		)
			.sink { [self] in
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
