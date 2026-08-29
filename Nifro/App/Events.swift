import Cocoa
import Combine
import KeyboardShortcuts

extension AppState {
	func setUpEvents() {
		// The first page of the session goes up here, before anything below can delay it. `didLaunch`
		// builds the scenes and deliberately loads nothing, so until this runs every display is
		// showing whatever was behind the wallpaper.
		//
		// It used to be the `contentRulesURL` subscription below that did this, by accident of that
		// publisher sending its current value on subscribe — and the sink awaited a content-rules
		// refresh first. With no rule list set, the default, that await costs a few milliseconds and
		// nobody could tell. With one set it is a `URLSession` fetch plus a rule-list compile, and the
		// desktop stayed empty for the length of the user's network. It was hidden until today by a
		// second, accidental load fired from `AppState.isEnabled`'s `didSet`, which put a page up
		// while the fetch was still running; removing that duplicate left the wait showing.
		//
		// So the load no longer waits for the rules. The rules catch up with it below.
		reloadEverything()

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

		// Sends its current value on subscribe, so this runs once at launch too — now behind the load
		// above rather than in front of it.
		//
		// Nothing happens unless the rules actually changed. That is what keeps the default free: with
		// no list set `refresh` finds nothing, `compiled` stays `nil`, and the page that just went up
		// is left alone, so a default launch is still exactly one load per display. It also fixes the
		// setting itself, which is a text field that republishes on every keystroke — an
		// unconditional reload here threw every page on screen away once per character typed.
		//
		// Taking a new list up needs both halves below. A compiled list is handed to a web view when
		// the web view is made, so the ones already on screen have to be given it directly; and it
		// only governs what a page fetches next, so the page has to be loaded again. The direct
		// hand-over is not made redundant by the reload: a reload builds a fresh web view only when
		// there is a page worth keeping on screen while it loads, and at launch this can land while
		// the first page is still arriving — which loads in place, into the web view already there.
		//
		// `reloadEverything` rather than `applyWebsiteChanges`, because no website changed and that
		// would correctly reload nothing.
		Defaults.publisher(.contentRulesURL)
			.sink { [self] _ in
				Task {
					let previous = ContentRules.compiled
					await ContentRules.refresh()

					guard ContentRules.compiled !== previous else {
						return
					}

					for scene in scenes {
						scene.webViewController.webView.configuration.applyContentRules()
					}

					reloadEverything()
				}
			}
			.store(in: &cancellables)

		SSEvents.deviceDidWake
			.sink { [self] in
				// Some pages hold state that a reload throws away, such as a signed-in dashboard mid-view, or a page that took a while to settle.
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

		// The playlists, which are where a website is stored. This watched the `websites` key while that
		// was a mirror written from these, so every edit reached the scenes one turn of the run loop
		// after it was made. The mirror is gone and so is the delay.
		Defaults.publisher(.playlists, options: [])
			.receive(on: DispatchQueue.main)
			.sink { [self] in
				let old = $0.oldValue.flatMap(\.websites)
				let new = $0.newValue.flatMap(\.websites)

				// Sound and the framed region are the settings people change while looking at the thing
				// they apply to, and they are the two the page already up can absorb. Everything else is
				// baked into the page when it is created, so everything else needs a new one.
				if differOnlyInLiveSettings(old, new) {
					applyLiveSettings()
					return
				}

				// No timer reset here. There was one, and it restarted both timers on every scene on
				// every edit to the list — which is every rotation tick, since a tick is an edit. So one
				// display rotating reset the other display's rotation clock, and a display told to
				// rotate every thirty minutes beside one rotating every five never reached thirty.
				// `applyWebsiteChanges` decides per scene whether the change reached it, and now settles
				// that scene's timers on the same answer.
				applyWebsiteChanges()

				// We never destroy the webview, so we have to make sure it's not in browsing mode when there are no websites.
				if new.isEmpty {
					Defaults[.browsingDisplays] = []
					applyBrowsingMode()
				}
			}
			.store(in: &cancellables)

		// Moving the mark used to be a write to the website list, so the sink above was what put the new
		// page on screen. It is a write to a key of its own now, and nothing was watching it — a
		// rotation tick, a Next, a pick in the panel and every `nifro://` command all changed the answer
		// and left the wallpaper where it was.
		//
		// `applyWebsiteChanges` and deliberately not the live-settings shortcut beside it: which website
		// a display shows is never something the page already up can absorb, it is a different page.
		//
		// The playlist alongside it, because "which website" is worked out from "which list". The two
		// keys are written together by `makeCurrent` — choosing a website out of a list is the one act
		// that commits either — so what arrives here is one change wearing two names, and merging them
		// is what makes it one event. Two keys and one sink, like the four inputs to opacity below: a
		// second sink calling the same function is a second place to forget it.
		//
		// The playlist half is not redundant even so. `clearAllWebsiteData` empties both dictionaries,
		// and it empties them separately.
		Publishers.MergeMany(
			Defaults.publisher(.currentWebsites, options: []).map { _ in }.eraseToAnyPublisher(),
			Defaults.publisher(.currentPlaylists, options: []).map { _ in }.eraseToAnyPublisher()
		)
			.receive(on: DispatchQueue.main)
			.sink { [self] in
				applyWebsiteChanges()
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

		// Every scene, not the one whose number changed: the key is one dictionary, so a change to it
		// says nothing about which display it was, and restarting a timer costs a minute of waiting at
		// most.
		Defaults.publisher(.rotationIntervals, options: [])
			.sink { [self] _ in
				for scene in scenes {
					scene.resetRotationTimer()
				}
			}
			.store(in: &cancellables)

		// The reload timer only, and every scene: the setting is the app-wide fallback for websites that
		// name no interval of their own, so a change to it can move any display's reload clock and says
		// nothing about which. The same shape as `rotationIntervals` above, and for the same reason —
		// and deliberately not the rotation clock, which this number has nothing to do with.
		Defaults.publisher(.reloadInterval)
			.sink { [self] _ in
				for scene in scenes {
					scene.resetTimer()
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.deactivateOnBattery)
			.sink { [self] _ in
				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.bringBrowsingModeToFront, options: [])
			.sink { [self] _ in
				for scene in scenes {
					scene.window.isInteractive = scene.window.isInteractive
				}
			}
			.store(in: &cancellables)

		browsingModeShortcut.install()

		Shortcut.install()
	}
}
