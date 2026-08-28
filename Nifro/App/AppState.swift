import SwiftUI

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	var cancellables = Set<AnyCancellable>()

	let holdToInteract = HoldToInteract()
	let powerSourceWatcher = PowerSourceWatcher()

	let displayPanel = DisplayPanelController()

	private(set) lazy var statusItem = with(NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)) {
		$0.isVisible = true
		$0.behavior = [.removalAllowed, .terminationOnRemoval]

		// A status item with a `menu` opens it on any click and never sends its action, so it has none:
		// the button handles the click itself and shows the panel.
		$0.button!.image = .menuBarIcon
		$0.button!.setAccessibilityTitle(SSApp.name)
		$0.button!.target = self
		$0.button!.action = #selector(handleStatusItemClick)
		$0.button!.sendAction(on: [.leftMouseUp, .rightMouseUp])
	}

	/**
	Either button opens the panel.

	The menu is gone. It could only ever describe one display, and everything it did the panel now does
	per display — including the two items that had no per-display answer at all: Quit and Settings,
	which are in the footer, and "Update Website to Current", which moved into the website's own
	settings because it is a rare, permanent edit and a menu is the wrong place to keep one.
	*/
	@objc
	private func handleStatusItemClick() {
		displayPanel.toggle(relativeTo: statusItemButton)
	}

	private(set) lazy var statusItemButton = statusItem.button!

	/**
	One wallpaper per display in use. Always at least one.

	The observer is here for the same reason the ones on `WallpaperScene`'s loading state are: a
	display unplugged mid-load takes its scene out of this list without any of that scene's own
	properties moving, so the answer below changes without any of them having said so. Without this
	the icon would go on pulsing for a load whose display is gone.
	*/
	private(set) var scenes: [WallpaperScene] = [] {
		didSet {
			refreshLoadingIndicator()
		}
	}

	/**
	Say whether any display has a page on its way, on the menu bar icon.

	Any, not which — the icon is one glyph and cannot name a display, and that is the whole of what it
	claims. The panel is where a per-display answer lives, and it is closed most of the time, which is
	why this exists as well as that rather than instead of it.

	Asked of the scenes rather than tallied as loads begin and end. `WallpaperScene.isLoading` is
	derived from the state each load already keeps, so re-reading all of them is the cheapest correct
	answer available and there is no accumulated count to drift. It is called from `didSet` on each of
	the properties that answer feeds off, which is what keeps a new caller from having to know this
	exists.
	*/
	func refreshLoadingIndicator() {
		statusItemButton.setShowingActivity(scenes.contains(where: \.isLoading))
	}

	/**
	The scene a keyboard shortcut acts on: the one the pointer is over.

	A shortcut is pressed by somebody looking at a screen, and until now every one of them went to the
	main display instead — the one with the menu bar, whichever screen that currently is — so on two displays, pressing Next in front of the monitor
	changed the laptop.

	Falls back to `primaryScene` when the pointer is not over a wallpaper: it is over a window, over a
	screen with nothing on it, or the displays are mid-reconfiguration. Silently, because a shortcut
	that does nothing and says nothing is worse than one that acts somewhere reasonable.

	It returns a *scene*, and callers pass `scene.display` on. Passing `Display.underMouse` straight
	into the rotation would be a different value from the one the scenes are keyed by — and
	`randomIterators` is keyed by exactly that, so a display would get two shuffle sequences and the
	"no repeats until the list is done" promise would quietly stop holding.
	*/
	var actingScene: WallpaperScene {
		guard let pointer = Display.underMouse else {
			return primaryScene
		}

		let match = scenes.first {
			// A scene's `nil` means the main display, so the two have to be compared after that is
			// spelled out rather than as written.
			Display.settingsKey(for: $0.display ?? .main) == Display.settingsKey(for: pointer)
		}

		return match ?? primaryScene
	}

	/**
	The scene an action acts on when nothing says which display it means.

	The main display's — the one with the menu bar. Not a display named in Settings: there is no such
	setting. Automations reach this through `Action.Source.automation`; a keyboard shortcut goes to
	`actingScene` instead, because a shortcut has a pointer behind it.
	*/
	var primaryScene: WallpaperScene {
		if let match = scenes.first(where: { $0.display == .main }) {
			return match
		}

		if scenes.isEmpty {
			rebuildScenes()
		}

		return scenes[0]
	}

	/**
	The website a Shortcuts query means by "the current website".

	The primary scene's — the main display's, the one with the menu bar. Not "the screen Settings
	points at": there is no display setting, and `Display.main` moves when the user rearranges their
	displays or docks. `Intents.swift` is the only reader; every other entry point goes through a
	scene of its own, and a keyboard shortcut goes to `actingScene`. There is deliberately no
	list-wide answer to this any more: one existed, every entry point used it, and on two displays it
	meant they all silently acted on whichever screen happened to hold the mark.
	*/
	var currentWebsite: Website? { primaryScene.website }

	/**
	Whether *any* display is in Browsing Mode.

	Almost nothing should ask this. Browsing Mode is stored per display, `DesktopWindow.isInteractive`
	is per window, and the panel draws a button per column — this is the one leftover from when it was
	a single flag, and every reader that took it was asking about one display and being answered about
	all of them. Measured on two displays: browsing on the built-in stopped the external's rotation and
	its auto-reload, and pushed the external's window to full opacity while it stayed at desktop level.
	`isBrowsingMode(on:)` below is the question those readers meant.

	The doc that used to be here argued the pause was deliberate — "a rotation tick on the other screen
	still steals focus". It does not. Nothing on the rotation path activates the app or takes key: a
	tick makes another website current, the scene loads it out of sight through swap loading, and the
	only `forceActivate` in this file is the one below, which runs when Browsing Mode is *entered*.
	The premise was wrong, so the pause it justified was a bug and not a design.

	Two readers are left and both are app-wide in themselves rather than by oversight: bringing the app
	forward, which has no per-display form, and `report`, which asks whether to interrupt with a modal
	alert — a modal is app-modal, and the question it is really asking is "is the user in front of a
	page of ours right now". `ScopeTests` fails the moment a third joins them.
	*/
	var isBrowsingMode: Bool { !Defaults[.browsingDisplays].isEmpty }

	/**
	Whether `display` is the one being interacted with.
	*/
	func isBrowsingMode(on display: Display?) -> Bool {
		Defaults[.browsingDisplays].contains(Display.settingsKey(for: display))
	}

	/**
	Turn Browsing Mode on or off for one display.
	*/
	func setBrowsingMode(_ isOn: Bool, on display: Display?) {
		let key = Display.settingsKey(for: display)

		if isOn {
			Defaults[.browsingDisplays].insert(key)
		} else {
			Defaults[.browsingDisplays].remove(key)
		}

		applyBrowsingMode()
	}

	/**
	Put every window at the level, the opacity and the timers its display's setting asks for.

	Both timers, which is the half that was missing. Only the reload timer was re-armed here, so
	entering Browsing Mode never disarmed the rotation — measured with the built-in on loop at one
	minute: Browsing Mode on at t+50, and the tick still fired at t+61 and replaced the page eleven
	seconds into it. If you entered Browsing Mode to sign in, the form you were typing into is gone.

	And it never came back. That in-browsing tick writes the website list, which rebuilds the scenes,
	which re-arms the timers — at a moment when the guard says no. Nothing else re-armed them, so
	after Browsing Mode ended the display simply stopped rotating for the rest of the session:
	measured, zero rotations in the 120 seconds after it was switched off, at a one-minute interval.
	Arming and disarming through the same call, on the way in and on the way out, is what closes both.

	Every scene, because the level and the opacity are read off each display's own answer and both are
	idempotent — a window already at the right level, an opacity already at its target. The timers are
	not idempotent, so they are settled only where the answer moved.
	*/
	func applyBrowsingMode() {
		guard isEnabled else {
			return
		}

		for scene in scenes {
			scene.window.isInteractive = isBrowsingMode(on: scene.display)
			scene.applyOpacity()

			// `resetRotationTimer` zeroes the minute count, so running it on a display nothing happened
			// to puts that display back to the start of its rotation interval — the same defect the
			// rebuild had, reached through a different door. Measured: entering Browsing Mode on the
			// built-in pushed the external's rotation from t+61 out to t+111.
			//
			// `rotationTimer` is the record of which side the timers were last armed for, so nothing has
			// to be remembered to compare against: it is non-`nil` exactly when this display is running
			// and not being browsed. The reload timer follows the same guard, so one of them can speak
			// for the pair — and it is the one that cannot be legitimately absent, where a website with
			// no reload interval leaves the other `nil` for a reason that has nothing to do with this.
			//
			// A display switched off answers "not browsing, no timer", so it takes a reset it does not
			// need. Both resets refuse it on `isSwitchedOff` and leave it exactly as it was.
			guard isBrowsingMode(on: scene.display) == (scene.rotationTimer != nil) else {
				continue
			}

			scene.resetTimer()
			scene.resetRotationTimer()
		}

		// Making the window key is not enough when the app is an accessory. The window comes forward, but keystrokes still go to whatever was active before, so nobody can type into the page.
		if isBrowsingMode {
			SSApp.forceActivate()
		}
	}

	/**
	Whether the app is putting wallpapers on screen at all.

	The guard is what keeps this from being taken up twice. `didSet` runs on every assignment, not
	only on a change, and `setEnabledStatus` recomputes the whole answer from four inputs and assigns
	it whether or not it moved — so any one of those inputs merely being *observed* replayed the
	branch below. At launch that is exactly what happens: the `deactivateOnBattery` publisher sends
	its current value on subscribe, which assigned `true` over `true` and handed every scene a
	`loadWebsite()` nobody asked for, a fraction of a second before the load that launch is actually
	built around. Measured on two displays: two full page loads each, of the same website, on every
	launch.

	Here rather than in `setEnabledStatus`, because this is where all four inputs meet and a fifth
	will not have to remember.
	*/
	var isEnabled = true {
		didSet {
			guard isEnabled != oldValue else {
				return
			}

			statusItemButton.appearsDisabled = !isEnabled

			guard isEnabled else {
				for scene in scenes {
					scene.suspend()
				}

				return
			}

			for scene in scenes {
				// A display switched off on its own stays off when the app comes back on. The app-wide
				// switch is above this one, not instead of it — which is exactly what `isSwitchedOff`
				// spells out, and it is asked here rather than re-derived so this loop is not a second
				// opinion about what "off" means.
				guard !scene.isSwitchedOff else {
					scene.suspend()
					continue
				}

				scene.resume()

				// Replayed, because `applyBrowsingMode` returns early while the app is disabled and nothing
				// else puts it back: `resume()` does not read it, and only an unrelated `rebuildScenes`
				// ever did. Browsing Mode is reachable while disabled, so the panel drew a lit button over
				// windows still sitting at `.desktop`.
				scene.window.isInteractive = isBrowsingMode(on: scene.display)

				scene.loadWebsite()
				scene.resetTimer()
				scene.resetRotationTimer()
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

	/**
	What went wrong loading each display's page.

	Per display, because every writer already was. All four sit in `WallpaperScene` and `SwapLoading`,
	which run once per display and know which one they are — and wrote into a single slot anyway, so
	the last one to finish spoke for every screen. The routine end of a load that worked writes `nil`,
	which meant a reload timer firing on the monitor erased the laptop's failure without either page
	having changed. The other order is worse than a lost message: the monitor's page is fine and the
	app is reporting the laptop's error against it.

	Keyed by `Display.settingsKey(for:)`, the key the other per-display facts already use, so a
	display unplugged and plugged back in comes back to its own entry rather than to a stranger's.

	Read only by `refreshStatusItemTooltip`, which is the app's one surface for a failure. Giving the
	panel a per-display reading of it is K26 and wants a column that can say so; this is the store that
	one would read, kept honest in the meantime rather than built out ahead of it.
	*/
	private var storedWebViewErrors: [String: Error] = [:]

	/**
	Record what went wrong on `display`, or that nothing has.

	Cancellations are dropped rather than stored. Superseding a load cancels the one in flight, so a
	cancelled task reports an error that is not one — and it reached the menu reading
	"Swift.CancellationError error 1", which tells the reader nothing except that something is wrong
	with the app.

	Filtered here rather than at each `catch`, because there are four of them and the next one added
	would have to remember.
	*/
	func setWebViewError(_ error: Error?, on display: Display?) {
		let key = Display.settingsKey(for: display)

		guard let error else {
			storedWebViewErrors[key] = nil

			if storedWebViewErrors.isEmpty {
				statusItemButton.contentTintColor = nil
			}

			refreshStatusItemTooltip()
			return
		}

		guard !isCancellation(error) else {
			return
		}

		storedWebViewErrors[key] = error
		refreshStatusItemTooltip()
		report(error)
	}

	/**
	Say what the menu bar icon is about: the failure if there is one, and otherwise the page.

	One writer, for the reason `refreshLoadingIndicator` is one — the icon is a single glyph shared by
	every display, so two per-display paths writing it directly meant whichever ran last spoke for all
	of them. A routine reload finishing on the monitor replaced the laptop's failure with the monitor's
	page title, and until the store below was per display the failure was not kept anywhere else
	either, so it was simply gone.

	A failure outranks a title, because a title is always available and a failure is the thing worth
	saying. Which failure, when two displays have one, is settled by the display key rather than by the
	order the loads happened to finish. Which title, when nothing has failed, is the main display's —
	the display `currentWebsite` means, for the reason given there.

	Deliberately not `primaryScene`: that rebuilds the list when it is empty, and a refresh is called
	from places that are in the middle of building it.
	*/
	func refreshStatusItemTooltip() {
		if let failure = storedWebViewErrors.min(by: { $0.key < $1.key })?.value {
			statusItemButton.toolTip = "Error: \(failure.localizedDescription)"
			return
		}

		let onMain = scenes.first { $0.display == .main } ?? scenes.first
		statusItemButton.toolTip = onMain?.website?.tooltip
	}

	private func report(_ webViewError: Error) {
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
		// After the line above, not before it: on a first launch that line is what puts anything in
		// the list at all, and a migration that ran first would file the shipped websites under
		// nothing.
		WebsitesController.shared.migrateToPlaylistsIfNeeded()
		rebuildScenes()
		setUpEvents()
		showWelcomeScreenIfNeeded()
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
	Create one scene per attached display, reusing the ones that already match.

	The list of displays is where this starts, and that is the inversion. It used to start from
	`WebsitesController.displaysInUse` — the distinct display named by some website — so a screen no
	website had been assigned to got no wallpaper at all, and the workaround for that was to pin the
	Nth shipped website to the Nth display on first launch. That pinning was never curation. It existed
	so the second screen would be named by something, and it only covered the displays attached the
	first time the app ran: plug in a monitor afterwards and it stayed black, with the website editor
	the only place to fix it from and nothing on the screen itself saying so.

	`Display.all` instead. The screen claims the content rather than the content claiming the screen, so
	a display no website names still gets a scene — `scheduled(for:)` hands it no website, and the panel
	draws the "No Website" state it already has for that. An empty column the user can pick from is a
	different thing from a screen that is missing.

	One scene survives the empty case, with no display of its own. `Display.all` is empty while the
	displays are being reconfigured and while every screen is asleep, and a rebuild runs on every
	display change, so this sees those moments. `nil` already means "the main screen" for everything
	below — `DesktopWindow.setFrame` and `WallpaperScene.screen` both resolve it through
	`Display.mainScreen` — so the app is never in a state with no wallpaper at all. That is the one
	thing `displaysInUse` bought with its fallback to the main display, and it is worth keeping.

	Call this whenever the displays change or a website moves to another display. Scenes for displays
	that went away get torn down. The rest keep their web views and whatever they had loaded.

	This brings a scene up to date with everything app-wide; it does not load anything. Callers that need a page on screen go through `applyWebsiteChanges`.
	*/
	func rebuildScenes() {
		// Read once rather than twice. Displays come and go between two reads of `NSScreen.screens`,
		// and this runs on the notification that says they just did.
		let attached = Display.all
		let wanted: [Display?] = attached.isEmpty ? [nil] : attached

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

		let departed = scenes.filter { scene in !kept.contains { $0 === scene } }

		for scene in departed {
			scene.tearDown()
		}

		scenes = kept

		// Browsing Mode is "somebody is interacting with this page *right now*" — the one per-display
		// entry that is a state rather than a preference, and so the one that cannot outlive the
		// display. It lives in `Defaults` and nothing removed it, so a display unplugged while its
		// Browsing Mode was on left the key behind across relaunches. The panel draws one column per
		// scene, so the departed display had no button to switch it off from, and there was no other
		// way out.
		//
		// Stated as "only displays that have a scene" rather than as a removal beside `tearDown`,
		// because that also clears a key stranded by a version that had no pruning at all — and this
		// runs on every display change, so it needs no unplug of its own to find one.
		//
		// The other per-display settings are deliberately left alone. `disabledDisplays`,
		// `rotationModes` and `rotationIntervals` are preferences: a monitor switched off, pinned, or
		// set to rotate hourly before it was unplugged has to come back that way, which is exactly what
		// keeping its key buys. Forgetting one for good is a thing to ask for, and Restore Defaults is
		// where it is asked.
		Defaults[.browsingDisplays].formIntersection(scenes.map { Display.settingsKey(for: $0.display) })

		// Which website each display is showing is on the other side of that line, with the three
		// preferences and not with Browsing Mode, and it is the case the line was drawn for: the user
		// picked that wallpaper for that screen, so a monitor unplugged at night has to come back in the
		// morning showing it. Nothing below forgets an entry.
		//
		// What does happen is the other half of an unplug. A website pinned to a display that is gone
		// moves to the main one when the user has asked for that, and the screen it lands on is told so
		// — once, from the scenes just torn down rather than from "every key with no scene", which would
		// say it again on every rebuild for as long as the cable stayed out.
		//
		// Before the loop below, not after, because that loop is where each scene is handed the website
		// this has just decided it should be showing.
		WebsitesController.shared.handOverCurrentWebsites(from: departed.map(\.display))

		// A failed load is state in the same sense, and is pruned for the same reason rather than kept
		// for the opposite one: it describes a page that was on its way to a display that is gone. It
		// is in memory rather than in `Defaults`, so this is the only place it could be dropped.
		storedWebViewErrors = storedWebViewErrors.filter { key, _ in
			scenes.contains { Display.settingsKey(for: $0.display) == key }
		}

		for scene in scenes {
			// `scheduled` rather than a plain lookup: rebuilding happens on display changes and on any
			// edit to the list, and a lookup that ignores the hours would put a website back on screen
			// after its window closed, until the next rotation tick noticed.
			scene.website = WebsitesController.shared.scheduled(for: scene.display)
			scene.installContentView()
			scene.window.isInteractive = isBrowsingMode(on: scene.display)
			scene.applyOpacity(animated: false)

			// A rebuild happens on every edit to the website list, and it used to hand every scene a
			// page and a timer whether or not its display was switched off. So pressing Next on one
			// display brought back every display that was off, each with a website nobody asked for.
			guard !scene.isSwitchedOff else {
				scene.suspend()
				continue
			}

			scene.resume()

			// Only the scenes the change actually reached — the same test `applyWebsiteChanges` uses to
			// decide which pages to reload, asked here so a display whose page is untouched keeps its
			// clock as well as its page. A rebuild runs on every edit to the website list, on every
			// display change and on every wake, and it used to restart both timers on every scene it
			// kept. `resetRotationTimer` also zeroes the minute count, so the restart was not a
			// rounding error: it put the display back at the start of its interval.
			//
			// Measured on two displays, external on loop at one minute and reloading every twenty
			// seconds. Undisturbed it reloaded at +20 and +40 and rotated at exactly +60. Pressing Next
			// on the *built-in* every fourteen seconds gave the external zero reloads and zero
			// rotations; every twenty-six seconds gave it a reload twenty seconds after each edit and
			// never a rotation of its own. So a monitor set to rotate every thirty minutes never
			// rotates if the laptop rotates every five, and a laptop woken often never rotates at all.
			guard !scene.isUpToDate else {
				continue
			}

			scene.resetTimer()
			scene.resetRotationTimer()
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

	/**
	Switch one display off, or back on, without touching the others.
	*/
	func setDisplayEnabled(_ isEnabledForDisplay: Bool, on display: Display?) {
		guard let scene = scenes.first(where: { $0.display == display }) else {
			return
		}

		scene.isDisabledForDisplay = !isEnabledForDisplay

		guard isEnabled else {
			// The app is off anyway; the setting is recorded and applies when it comes back.
			return
		}

		if isEnabledForDisplay {
			scene.resume()
			scene.loadWebsite()
			scene.resetTimer()
			scene.resetRotationTimer()
		} else {
			scene.suspend()
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
		// one scene per display that meant one screen's rotation tick throwing away and re-fetching the
		// page on every other screen — pages nothing about the edit had touched.
		//
		// Taken before the rebuild, because the rebuild is what moves each scene's `website` on to what
		// the list now says. `isUpToDate` compares against the list rather than against that property,
		// so it gives the same answer on both sides of the call — which is what lets `rebuildScenes`
		// ask it too, and settle the page and the timers on one test instead of two.
		let upToDate = scenes.filter(\.isUpToDate)

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
			scene.webViewController.webView.setAudioMuted(!scene.shouldPlaySound)
		}
	}

	func reloadWebsite() {
		for scene in scenes {
			scene.reload()
		}
	}
}

/**
Whether an error is a load being superseded rather than a load going wrong.

Here rather than in a file of its own because `setWebViewError` is the only caller and always was.
The file it came from was called `Text.swift` and held the menu's word wrapping; the wrapping went
with the menu, and this was left behind under a name that no longer described anything in it.
*/
private func isCancellation(_ error: Error) -> Bool {
	if error is CancellationError {
		return true
	}

	let error = error as NSError

	if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
		return true
	}

	return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
}
