import SwiftUI

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	var cancellables = Set<AnyCancellable>()

	let menu = SSMenu()
	let holdToInteract = HoldToInteract()
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


	var isBrowsingMode = false {
		didSet {
			guard isEnabled else {
				return
			}

			for scene in scenes {
				scene.window.isInteractive = isBrowsingMode
				scene.applyOpacity()
				scene.resetTimer()
			}

			// Making the window key is not enough when the app is an accessory. The window comes forward, but keystrokes still go to whatever was active before, so nobody can type into the page. Plash#114.
			if isBrowsingMode {
				SSApp.forceActivate()
			}
		}
	}

	var isEnabled = true {
		didSet {
			statusItemButton.appearsDisabled = !isEnabled

			guard isEnabled else {
				for scene in scenes {
					scene.suspend()
				}

				return
			}

			for scene in scenes {
				scene.resume()
				scene.loadWebsite()
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
	The overlay the user drags a crop region on, plus the crop that was in place before they started.
	*/
	var cropSelectionView: CropSelectionView?
	var cropSelectionPreviousZoom: Zoom?

	/**
	Which display the crop being framed belongs to, so finishing acts on the scene that started it.
	*/
	var croppingSceneDisplay: Display??

	private var storedWebViewError: Error?

	/**
	The last thing that went wrong loading a page, or `nil`.

	Cancellations are dropped rather than stored. Superseding a load cancels the one in flight, so a
	cancelled task reports an error that is not one — and it reached the menu reading
	"Swift.CancellationError error 1", which tells the reader nothing except that something is wrong
	with the app.

	Filtered here rather than at each `catch`, because there are four of them and the next one added
	would have to remember.
	*/
	var webViewError: Error? {
		get { storedWebViewError }
		set {
			guard let newValue else {
				storedWebViewError = nil
				statusItemButton.contentTintColor = nil
				return
			}

			guard !isCancellation(newValue) else {
				return
			}

			storedWebViewError = newValue
			report(newValue)
		}
	}

	private func report(_ webViewError: Error) {
		statusItemButton.toolTip = "Error: \(webViewError.localizedDescription)"

		// TODO: There's a macOS bug that makes it black instead of a color.
//		statusItemButton.contentTintColor = .systemRed

		// TODO: Also present the error when the user just added it from the input box as then it's also "interactive".
		guard
			isBrowsingMode,
			!webViewError.localizedDescription.contains(String(localized: "No internet connection"))
		else {
			return
		}

		webViewError.presentAsModal()
	}

	private init() {
		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		_ = statusItemButton
		WebsitesController.shared.installFeaturedWebsitesIfNeeded()
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

	func setEnabledStatus() {
		isEnabled = !isManuallyDisabled && !isScreenLocked && !(Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true)
	}

	/**
	Create one scene per display that should show a wallpaper, reusing the ones that already match.

	Call this whenever the displays change or a website moves to another display. Scenes for displays that went away get torn down. The rest keep their web views and whatever they had loaded.
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
			// `scheduled` rather than a plain lookup: rebuilding happens on display changes and on any
			// edit to the list, and a lookup that ignores the hours would put a website back on screen
			// after its window closed, until the next playlist tick noticed.
			scene.website = WebsitesController.shared.scheduled(for: scene.display)
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

	/**
	Take up whatever the website list now says.

	Through swap loading, so what is on screen stays there until the next page has arrived. It used
	to install a blank web view first and then start loading into it, which showed the desktop for as
	long as the new page took — and the menu bar band, which is only re-sampled once a page has
	loaded, kept the old website's colour across that gap. Both of those are the same fix: do not take
	the old page away before there is a new one.

	Nothing needs a new web view here. Swap loading builds one for the replacement, and it is built
	after the change, so the new website's scripts are in it.
	*/
	func applyWebsiteChanges() {
		rebuildScenes()

		for scene in scenes {
			scene.reload()
		}
	}

	/**
	Whether two versions of the website list differ in nothing but the sound setting.

	The list is republished for every edit, and every edit but this one changes something that is
	built into the page when the page is created. Telling them apart is what lets sound be changed
	without the page starting over.
	*/
	func differOnlyInAudio(_ old: [Website], _ new: [Website]) -> Bool {
		guard old.count == new.count else {
			return false
		}

		return zip(old, new).allSatisfy { before, after in
			var matched = before
			matched.audio = after.audio
			return matched == after
		}
	}

	/**
	Tell every page the sound setting it should be at.
	*/
	func applyAudioSetting() {
		let muted = WebsitesController.shared.current?.audio != .unmuted

		for scene in scenes {
			scene.webViewController.webView.setAudioMuted(muted)
		}
	}

	/**
	Put the live page back on every scene, now that framing a region is over.
	*/
	func installContentView() {
		for scene in scenes {
			scene.installContentView()
		}
	}

	func reloadWebsite() {
		for scene in scenes {
			scene.reload()
		}
	}
}
