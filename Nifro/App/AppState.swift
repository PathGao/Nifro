import SwiftUI

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	var cancellables = Set<AnyCancellable>()

	let browsingModeShortcut = BrowsingModeShortcut()
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
	into the rotation would be a different value from the one the scenes are keyed by: `nil` means the
	main display to a scene and names no display at all to the pointer, so one screen would answer to
	two names on the way in.

	That used to be a defect waiting under this comment as well as an untidiness. The shuffled order was
	keyed by `Display?` itself, so a display reached under both names got two orders over one list and
	"no repeats until the list is done" quietly stopped holding. It is keyed by `Display.settingsKey(for:)`
	now, like everything else that is one-per-display, and a screen has one name in the store however it
	was reached. What is left here is the reason above it — a shortcut is pressed by somebody looking at
	a screen, and the scene is the thing that knows which screen that is.
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

	**Leaving takes a fresh colour for the menu bar band, and that is deliberately not behind the
	setting that names an interval.** Somebody has just spent Browsing Mode scrolling that wallpaper,
	signing in to it, or clicking through to another view of it, so the top of the page is almost
	certainly not the strip the band was painted from — and unlike the pages the interval exists for,
	this is a moment we know about. It belongs with "sample when a load finishes" rather than with the
	clock: an event, one sample, at a point the user was in front of. A switch named after an interval
	turns a cadence off, and it must not be able to turn off the events beside it, or somebody who
	preferred the old behaviour would get a worse version of it than the app had before the switch
	existed.
	*/
	func setBrowsingMode(_ isOn: Bool, on display: Display?) {
		let key = Display.settingsKey(for: display)

		if isOn {
			Defaults[.browsingDisplays].insert(key)
		} else {
			Defaults[.browsingDisplays].remove(key)
		}

		applyBrowsingMode()

		// After `applyBrowsingMode`, which is what puts the window back to how it is drawn outside
		// Browsing Mode. The sample itself refuses on a display with no band, one switched off and one
		// whose page is not up, so there is nothing to ask here that it does not ask for itself.
		if !isOn {
			scenes.first { $0.display == display }?.refreshMenuBarBandColor()
		}
	}

	/**
	Flip Browsing Mode for one display, and say what it is the first time it comes on.

	The flip is two lines and was written out twice — once in the `Action` table, once in the panel's
	column — and only one of the two copies carried the explanation. That is the whole defect: the
	explanation was moved into `Action` precisely because it had been stranded on the menu item, the
	panel then replaced the menu without going through `Action`, and the most discoverable way into
	Browsing Mode became the one that never says what Browsing Mode is. A verb rather than a
	convention, so the next surface cannot be given the switch without the sentence that comes with it.

	The hold is the one route that does not pass through here, and it says why in its own file: it
	turns Browsing Mode on and off around a key that is still down, and neither half is a toggle.
	*/
	func toggleBrowsingMode(on display: Display?) {
		let isOn = !isBrowsingMode(on: display)
		setBrowsingMode(isOn, on: display)

		// On the way in only. `Action` ran the explanation after the flip whichever way it went, which
		// was harmless while this was the only way in and is not any more: the panel can switch Browsing
		// Mode on without spending the once-ever run, so the first flip that reaches this line can be an
		// *off* — and the first thing the app ever said about Browsing Mode was then a description of
		// the thing it had just taken away.
		if isOn {
			explainBrowsingModeOnce()
		}
	}

	/**
	Say what Browsing Mode is, once per install.

	It reads as a courtesy and is not one. The page being handed over is a wallpaper, so it is behind
	whatever the user is looking at: somebody who switches this on and sees nothing happen has no way
	to learn that nothing is broken, and the sentence about hiding windows is the only place the app
	says so. That is why every route has to reach it — the panel's button, a tap of the shortcut, the
	end of a hold, `nifro://` and the Shortcuts action — and why the routes with nobody at the machine
	matter most.

	`SSApp.runOnce` is a flag in `UserDefaults`, so the once is once for the install rather than once
	per caller. Every route may ask; the first to arrive is the only one that speaks. That is what
	makes a bare call at each entry point safe and why there is no bookkeeping here.

	Off the current run loop turn, deliberately. Two of the callers are inside event handling — the
	Carbon key-up and the local `.flagsChanged` monitor, which has to return its event — and an
	`NSAlert` is app-modal, running a run loop of its own until it is dismissed. Raising one from
	inside a handler that still has work after it is how the hold gets stranded in front of the
	desktop with nothing left to put it back.
	*/
	func explainBrowsingModeOnce() {
		SSApp.runOnce(identifier: "activatedBrowsingMode") {
			DispatchQueue.main.async {
				NSAlert.showModal(
					title: String(localized: "Lets you temporarily interact with the website, to log in or scroll to a particular place."),
					message: String(localized: "If you cannot see the website, hide some windows to reveal the desktop.")
				)
			}
		}
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
	private(set) var isEnabled = true {
		didSet {
			guard isEnabled != oldValue else {
				return
			}

			// The only publish `AppState` makes, and it is inside the guard on purpose. `@Published` on
			// this property would send on every assignment instead of every change, which is the same
			// replay the guard above was written to stop: `setEnabledStatus` recomputes and assigns
			// whether or not the answer moved, and the battery publisher assigns `true` over `true` on
			// every launch. A view redrawn for that is cheaper than a page load and no less wrong.
			//
			// Sent from `didSet` rather than `willSet`, so what a redraw reads is the new answer.
			// `ObservableObject` schedules the redraw for the next turn of the run loop either way; the
			// name is about ordering with SwiftUI, not with this line.
			//
			// Who needs it: the Websites window ticks the website each screen is showing, and a screen
			// showing nothing has no tick. The three inputs folded in here — the menu bar's Disable, the
			// lock screen, the battery rule — are stored properties with no key behind them, so a window
			// left open while any of them fires has nothing else to hear it from. `RowView` is the
			// observer; `disabledDisplays` is the other half and is a `Defaults` key that publishes
			// itself.
			objectWillChange.send()

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
	Why the app is putting nothing on screen, or `nil` when it is putting something on screen.

	`setEnabledStatus` folds three inputs into one `Bool`, which is everything the app needs in order
	to act and less than a person needs in order to understand. Off because the user asked and off
	because the laptop came off its charger are the same value and different sentences, and only one of
	them is something they did.

	Which matters because of what the panel showed before this existed. Every display's `isSwitchedOff`
	is true while the app is off, so every column read "Switched off" — the phrase belonging to the
	power button beside it, on a display nobody had touched. Unplug a laptop with "Deactivate while on
	battery" set and every wallpaper goes, and the panel's account of it was four columns each blaming
	their own screen.

	Two readings rather than three. The screen being locked is the third input and cannot be seen from
	here — there is no panel over a locked screen — so it joins the manual switch under the one word
	that is true of both.
	*/
	var disabledReason: DisabledReason? {
		guard !isEnabled else {
			return nil
		}

		return isDeactivatedOnBattery ? .onBattery : .switchedOff
	}

	/**
	Whether the battery rule in Settings is what is keeping the wallpapers off screen.

	One expression, read by `setEnabledStatus` to decide and by `disabledReason` to explain. Written
	out twice, the explanation would be a second opinion about the decision, and the two would part on
	the day the rule grows a condition — which is the shape of nearly everything else fixed in this
	app.
	*/
	private var isDeactivatedOnBattery: Bool {
		Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true
	}

	enum DisabledReason {
		/// Somebody, or something with no explaining to do, turned the app off.
		case switchedOff

		/// The battery rule in Settings is on and the machine is running off its battery.
		case onBattery
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

	Naming the right scene is all this does. What makes the restore *happen* on an unplug is that
	`tearDown` empties the window, which takes the overlay out of it, which is an ending — see
	`CropSelectionView.viewDidMoveToWindow`. The scene is still alive at that point, held by the
	`departed` list `rebuildScenes` is iterating, so the window it puts back is its own.
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

	Read by `refreshStatusItemTooltip`, which is a tooltip on an icon nobody is pointing at, and by the
	panel through `webViewError(on:)` — the column that K26 said this store was waiting for. Until that
	column existed, a wallpaper URL that started answering with an error was recorded here correctly
	and said nowhere a user would look: the desktop kept the last page that worked, the column named the
	website, and nothing anywhere reported that the website was no longer arriving.
	*/
	private var storedWebViewErrors: [String: Error] = [:]

	/**
	What went wrong loading `display`'s page, if anything.

	A reader rather than the store, because the store is one dictionary shared by every display and the
	panel builds one column at a time. Handing out the whole thing is how the app-wide slot this
	replaced came to be written by four per-display callers.
	*/
	func webViewError(on display: Display?) -> Error? {
		storedWebViewErrors[Display.settingsKey(for: display)]
	}

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

		// First, because everything under it reads the reload setting rather than converting it:
		// `rebuildScenes` arms a reload timer per display and `setUpEvents` subscribes to both halves.
		migrateReloadIntervalToASwitch()

		// Before `rebuildScenes`, because a scene reads the list this writes. The migration and the
		// install inside it run in an order that matters and is argued for where it lives; this used to
		// be that pair spelled out, which is the same order kept in two places at once.
		WebsitesController.shared.prepareWebsiteStorage()
		rebuildScenes()
		setUpEvents()
		showWelcomeScreenIfNeeded()
	}

	/**
	Decide, once, whether the app-wide reload interval was switched on.

	The setting was an optional number where absent meant off, and it is a switch and an always-valid
	number now — see `Constants.swift`, which argues the shape. The number carries itself across
	unchanged; the switch cannot, because its old answer was "is there an entry under this key" and
	the new key has a default, so every user reads a number whether or not they ever set one. Left to
	the `Bool`'s own default, everybody who had a reload interval would come back with reloading off
	and no sign of why.

	So it is read out of the persistent domain, which is the one place that still distinguishes the
	two, and it is read on exactly one launch. `reloadIntervalSwitch` is where the decision lives and
	what `SettingsMigrationTests` runs; this is the `Defaults` around it, and the flag goes down before
	the write in the shape `migrateToPlaylistsIfNeeded` established.

	It is allowed to run again after Restore All Settings, which empties the domain and takes the flag
	with it. That run finds no stored interval and switches reloading off — which is where a restore
	is supposed to leave it, so the flag is deliberately not one of `RestoreDefaults`'s exceptions.
	*/
	private func migrateReloadIntervalToASwitch() {
		guard !Defaults[.hasMigratedReloadIntervalToASwitch] else {
			return
		}

		let isOn = reloadIntervalSwitch(
			storedSettings: UserDefaults.standard.persistentDomain(forName: SSApp.idString) ?? [:],
			intervalKey: Defaults.Keys.reloadInterval.name
		)

		Defaults[.hasMigratedReloadIntervalToASwitch] = true
		Defaults[.reloadOnInterval] = isOn
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
		isEnabled = !isManuallyDisabled && !isScreenLocked && !isDeactivatedOnBattery
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
		//
		// Written only when it takes something away. `Defaults` observes with plain KVO and filters
		// nothing, so storing back an identical set still publishes, and `SSWebView` subscribes to this
		// key once per web view with a sink that evaluates JavaScript in the web content process. A
		// rebuild runs on every rotation tick, every edit and every wake, so the unconditional write was
		// a cross-process call per display to say what the page already knew. Intersecting only ever
		// removes, which is why "already a subset" is the whole test.
		let live = Set(scenes.map { Display.settingsKey(for: $0.display) })

		if !Defaults[.browsingDisplays].isSubset(of: live) {
			Defaults[.browsingDisplays].formIntersection(live)
		}

		// Which website each display is showing, and which playlist it is pointed at, are on the other
		// side of that line, with the three preferences and not with Browsing Mode — and they are the
		// case the line was drawn for: the user picked that wallpaper for that screen, so a monitor
		// unplugged at night has to come back in the morning showing it. Nothing here forgets either
		// entry, and nothing has to move one anywhere: a display that is gone has no scene, so there is
		// no wallpaper on it to be pushed onto a screen the user did not choose it for.
		//
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

		// The second of this object's two publishes, and the loop above is what makes it one: this is
		// where each display's mark becomes its answer — `scene.website` — and nothing else tells a view
		// that it moved. The Websites window's tick reads the answer, so `currentWebsites` changing is
		// the wrong moment to redraw on: it fires before this runs, which would leave the tick a turn
		// behind the screen and then never correct it. `WebsitesController`'s header separates the two.
		objectWillChange.send()
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
	Wake `display` if it is switched off on its own, and do nothing whatever if it is not.

	Every request to *see* something on a display ends here: picking a website, stepping to the next
	one, pointing the display at another playlist. Each of those on a dark screen used to move a mark
	and change a label while the display stayed dark, so it got pressed again — and the display came
	back later on a website nobody had chosen.

	The check is the point, not an optimisation. `setDisplayEnabled(true, on:)` reloads the page and
	restarts both timers, so calling it on a display that is already on is not free and not invisible:
	it would throw away the page and reset the rotation clock every time anybody picked anything.

	It cannot clear a Disable that came from the battery, the lock screen or the Disable shortcut.
	That is one switch above this one — see `WallpaperScene.isSwitchedOff` — and this is the half a
	request to see something is allowed to answer.
	*/
	func wakeDisplay(_ display: Display?) {
		// `if` rather than `guard`, so this reads as the one place that acts on half of "off" rather
		// than as another place that refuses on half of it. `SwitchedOffTests` draws that line.
		if scenes.first(where: { $0.display == display })?.isDisabledForDisplay == true {
			setDisplayEnabled(true, on: display)
		}
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
