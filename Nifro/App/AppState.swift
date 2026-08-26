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

	/**
	The website the menu, the keyboard shortcuts, the URL commands and the Shortcuts actions act on.

	The primary scene's, because a menu item has to mean one website and that is the screen Settings
	points at. Every other display is reached through its own scene. There is deliberately no
	list-wide answer to this any more: one existed, every one of those entry points used it, and on
	two displays it meant they all silently acted on whichever screen happened to hold the mark.
	*/
	var currentWebsite: Website? { primaryScene.website }

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

				// Replayed, because `isBrowsingMode.didSet` drops its write while the app is disabled and
				// nothing else puts it back: `resume()` does not read it, and only an unrelated
				// `rebuildScenes` ever did. Browsing Mode is reachable while disabled from the menu, which
				// gates on there being a website rather than on `isEnabled`, and from the global shortcut
				// and the Shortcuts intent, which gate on nothing — so the menu drew a checkmark over
				// windows still sitting at `.desktop`. `finishCropSelection` already restores it this way.
				scene.window.isInteractive = isBrowsingMode

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
	The overlay the user drags a crop region on.
	*/
	var cropSelectionView: CropSelectionView?

	/**
	The scene being framed and the website it is framing, so finishing acts on the one that started it
	rather than on whichever one happens to be current when the drag ends.

	The scene itself, not its display. Finishing used to look the scene back up by display, with a
	fallback to the primary one — a second way of naming a thing that was already in hand, and the two
	disagreed exactly when it mattered: unplug that display mid-drag and the restore landed on the main
	scene while the framed one kept `.floating` and full opacity, the only way in the app to pin a
	wallpaper above every window with no way back. Weak, so a scene torn down with its display reads as
	gone instead of as some other scene.
	*/
	weak var croppingScene: WallpaperScene?
	var croppingWebsiteID: Website.ID?

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

	Call this whenever the displays change or a website moves to another display. Scenes for displays that went away get torn down — which depends entirely on `displaysInUse` no longer naming them, and it used to name them forever. The rest keep their web views and whatever they had loaded.

	This brings a scene up to date with everything app-wide; it does not load anything. Callers that need a page on screen go through `applyWebsiteChanges`.
	*/
	func rebuildScenes() {
		let wanted = WebsitesController.shared.displaysInUse

		var kept: [WallpaperScene] = []

		for display in wanted {
			if let existing = scenes.first(where: { $0.display == display }) {
				kept.append(existing)
			} else {
				// The website is handed over at birth rather than assigned below, because the scene
				// builds its web view in `init` and the web view is configured from the website: its
				// custom CSS and JavaScript, whether colours are inverted, whether print styles apply.
				// Assigned afterwards, every scene built its first page from some other website's
				// settings.
				kept.append(WallpaperScene(display: display, website: WebsitesController.shared.scheduled(for: display)))
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
			scene.resetTimer()
			scene.resetPlaylistTimer()
		}
	}

	/**
	Ask GitHub what the newest release is and write it down, then say whether it is newer than this one.

	Both the daily check and the button in Settings come through here, so there is one answer to "what
	is the latest version" and one place it is recorded. The fetch and the comparison stay pure and
	tested in `UpdateCheck`; storing what they found is the app's business, which is why it is here.
	*/
	@discardableResult
	func refreshLatestKnownVersion() async -> UpdateCheck.Result {
		guard let latest = await UpdateCheck.latestReleaseVersion() else {
			return .unreachable
		}

		Defaults[.latestKnownVersion] = latest

		return UpdateCheck.isNewer(latest, than: SSApp.version) ? .newer(latest) : .upToDate
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
		// Only the scenes the change actually reached. Every edit republishes the whole list, and with
		// one scene per display that meant one screen's playlist tick throwing away and re-fetching the
		// page on every other screen — pages nothing about the edit had touched.
		let upToDate = scenes.filter { $0.loadedWebsite == WebsitesController.shared.scheduled(for: $0.display) }

		rebuildScenes()

		for scene in scenes where !upToDate.contains(where: { $0 === scene }) {
			scene.reload()
		}
	}

	/**
	Rebuild every page, whatever the website list says.

	For a change that is not in the list at all. A content-blocking rule list is compiled into the web
	view when the web view is created, so a new one only reaches a page that is built again — and
	`applyWebsiteChanges` would correctly decide that no website changed and reload nothing.
	*/
	func reloadEverything() {
		rebuildScenes()
		reloadWebsite()
	}

	/**
	Whether two versions of the website list differ in nothing the page has to be rebuilt for.

	The list is republished for every edit, and most edits change something that is built into the
	page when the page is created. Two do not. Sound is told to the page that is already up. So is the
	framed region: it wraps the view the page is already in, and the page never learns about it.

	Telling those two apart from the rest is what lets them be changed without the page starting over
	— which matters most for the region, because framing one is something you do *after* getting the
	page to show what you want. Reloading at that moment throws away a panned map, a scrolled
	dashboard, or the corner of a canvas somebody spent a minute finding, and then frames whatever the
	page looks like from cold.
	*/
	func differOnlyInLiveSettings(_ old: [Website], _ new: [Website]) -> Bool {
		guard old.count == new.count else {
			return false
		}

		return zip(old, new).allSatisfy { before, after in
			var matched = before
			matched.audio = after.audio
			matched.zoom = after.zoom
			return matched == after
		}
	}

	/**
	Take up a change that the pages already on screen can absorb.
	*/
	func applyLiveSettings() {
		for scene in scenes {
			scene.website = WebsitesController.shared.scheduled(for: scene.display)

			// The page on screen is still the right page and it now carries the new setting, so record
			// that. Left stale, the next ordinary edit would compare against the copy from before this
			// one and reload a page that had already taken the change.
			if scene.loadedWebsiteID == scene.website?.id {
				scene.adoptLoadedWebsite()
			}

			scene.installContentView()
		}

		applyAudioSetting()
	}

	/**
	Tell every page the sound setting its own website asks for.

	Per scene. One answer read off the list-wide current website and sent to all of them muted a live
	stream on the second display because the clock on the first was the marked one.
	*/
	func applyAudioSetting() {
		for scene in scenes {
			scene.webViewController.webView.setAudioMuted(scene.website?.audio != .unmuted)
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
