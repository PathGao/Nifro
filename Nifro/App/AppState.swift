import SwiftUI

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	var cancellables = Set<AnyCancellable>()

	let menu = SSMenu()
	let powerSourceWatcher = PowerSourceWatcher()

	private(set) lazy var statusItem = with(NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)) {
		$0.isVisible = true
		$0.behavior = [.removalAllowed, .terminationOnRemoval]
		$0.menu = menu
		$0.button!.image = .menuBarIcon
		$0.button!.setAccessibilityTitle(SSApp.name)
	}

	private(set) lazy var statusItemButton = statusItem.button!

	/**
	One wallpaper per display in use. Always at least one.
	*/
	private(set) var scenes: [WallpaperScene] = []

	/**
	The scene the menu and the settings act on when nothing says otherwise.
	*/
	var primaryScene: WallpaperScene {
		if let match = scenes.first(where: { $0.display == Defaults[.display] }) {
			return match
		}

		if scenes.isEmpty {
			rebuildScenes()
		}

		return scenes[0]
	}

	var desktopWindow: DesktopWindow { primaryScene.window }
	var webViewController: WebViewController { primaryScene.webViewController }

	var isBrowsingMode = false {
		didSet {
			guard isEnabled else {
				return
			}

			for scene in scenes {
				scene.window.isInteractive = isBrowsingMode
				scene.applyOpacity()
				scene.applyVisibilityState()
				scene.resetTimer()
			}

			// Making the window key is not enough when the app is an accessory: the window comes forward but keystrokes still go to whatever was active, so the page cannot be typed into. Plash#114.
			if isBrowsingMode {
				SSApp.forceActivate()
			}
		}
	}

	var isEnabled = true {
		didSet {
			statusItemButton.appearsDisabled = !isEnabled

			for scene in scenes {
				if isEnabled {
					scene.loadWebsite()
					scene.window.makeKeyAndOrderFront(self)
				} else {
					scene.window.orderOut(self)
					scene.releaseWebView()
				}

				scene.resetTimer()
				scene.resetPlaylistTimer()
			}
		}
	}

	var isScreenLocked = false

	var isManuallyDisabled = false {
		didSet {
			setEnabledStatus()
		}
	}

	/**
	The overlay shown while the user is dragging out a crop region, and the crop that was in place before they started.
	*/
	var cropSelectionView: CropSelectionView?
	var cropSelectionPreviousCrop: CGRect?

	var webViewError: Error? {
		didSet {
			if let webViewError {
				statusItemButton.toolTip = "Error: \(webViewError.localizedDescription)"

				// TODO: There's a macOS bug that makes it black instead of a color.
//				statusItemButton.contentTintColor = .systemRed

				// TODO: Also present the error when the user just added it from the input box as then it's also "interactive".
				if
					isBrowsingMode,
					!webViewError.localizedDescription.contains("No internet connection")
				{
					webViewError.presentAsModal()
				}

				return
			}

			statusItemButton.contentTintColor = nil
		}
	}

	private init() {
		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		_ = statusItemButton
		rebuildScenes()
		setUpEvents()
		showWelcomeScreenIfNeeded()

		#if DEBUG
//		SSApp.showSettingsWindow()
//		Constants.openWebsitesWindow()
		#endif
	}

	func handleMenuBarIcon() {
		statusItem.isVisible = true

		delay(.seconds(5)) { [self] in
			guard Defaults[.hideMenuBarIcon] else {
				return
			}

			statusItem.isVisible = false
		}
	}

	func handleAppReopen() {
		handleMenuBarIcon()
	}

	func setEnabledStatus() {
		isEnabled = !isManuallyDisabled && !isScreenLocked && !(Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true)
	}

	/**
	Create one scene per display that should show a wallpaper, reusing the ones that already match.

	Called whenever the set of displays or the assignment of websites to them changes. Scenes for displays that went away are torn down; the rest keep their web views and whatever they had loaded.
	*/
	func rebuildScenes() {
		let wanted = WebsitesController.shared.displaysInUse

		var kept: [WallpaperScene] = []

		for display in wanted {
			if let existing = scenes.first(where: { $0.display == display }) {
				kept.append(existing)
			} else {
				kept.append(WallpaperScene(display: display))
			}
		}

		for scene in scenes where !kept.contains(where: { $0 === scene }) {
			scene.tearDown()
		}

		scenes = kept

		for scene in scenes {
			scene.website = WebsitesController.shared.current(for: scene.display)
			scene.installContentView()
			scene.window.isInteractive = isBrowsingMode
			scene.applyOpacity(animated: false)
			scene.resetPlaylistTimer()
		}
	}

	func resetTimer() {
		for scene in scenes {
			scene.resetTimer()
			scene.resetPlaylistTimer()
		}
	}

	func recreateWebView() {
		for scene in scenes {
			scene.recreateWebView()
		}
	}

	func installContentView() {
		for scene in scenes {
			scene.installContentView()
		}
	}

	func recreateWebViewAndReload() {
		rebuildScenes()

		for scene in scenes {
			scene.recreateWebView()
			scene.loadWebsite()
		}
	}

	func reloadWebsite() {
		for scene in scenes {
			scene.reload()
		}
	}

	func loadUserURL() {
		for scene in scenes {
			scene.loadWebsite()
		}
	}

	func toggleBrowsingMode() {
		Defaults[.isBrowsingMode].toggle()
	}
}
