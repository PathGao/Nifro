import SwiftUI

enum Constants {
	static let repositoryURL = URL("https://github.com/PathGao/Nifro")
	static let latestReleaseURL = URL("https://github.com/PathGao/Nifro/releases/latest")
	/**
	The candidate list, not the directory the entries are authored in.

	`sites/` holds one YAML file per entry, which is a format for writing an entry and not one for
	reading a list. Sending somebody browsing for a wallpaper there shows them thirty-eight files of
	settings; the candidate list is prose with links, which is what they came for.
	*/
	static let candidateSitesURL = URL("https://github.com/PathGao/Nifro/blob/main/sites/CANDIDATES.md")
	static let siteSubmissionURL = URL("https://github.com/PathGao/Nifro/issues/new?template=site_submission.yml")

	@MainActor
	static func openSiteGalleryWindow() {
		SSApp.forceActivate()
		EnvironmentValues().openWindow(id: "site-gallery")
	}

	@MainActor
	static func openWebsitesWindow() {
		SSApp.forceActivate()
		EnvironmentValues().openWindow(id: "websites")
	}
}

/**
What is stored here, and what is deliberately not.

Everything the app knows sorts into three classes, and the test that sorts it is **"can this be asked
again?"** — asked of the machine, at the moment somebody wants the answer. Getting it wrong compiles,
reviews clean and works on one display; what it produces is a setting the user made and lost, or a
screen that comes back from a night unplugged as something they did not choose.

**1. Askable. Do not store it — there is nothing to store.** The condition lifting restores the answer
by itself. Whether this Mac is on battery is `AppState.isDeactivatedOnBattery`, a computed property
with no storage anywhere behind it. Whether the screen is locked is fed by a system publisher. Whether
a display is plugged in has no flag at all, and that absence is the proof rather than an oversight:
`Display.all` is asked afresh every time, which is why a rebuild needs no record of what was attached
last time.

**2. Not askable, and the user pressed it. Store it, or their intent is lost.** `disabledDisplays`,
`rotationModes`, `rotationIntervals`, and `currentWebsites` and `currentPlaylists` — which website a
display shows and which list it is pointed at. Nothing prunes these when a display goes away: the
choice was made about that screen, so a monitor unplugged at night has to come back in the morning as
it was left. Forgetting one for good is a thing to ask for, and Restore Defaults is where it is asked.
Every plain setting further down this file is class 2 too; the sort is only interesting where the
thing is per display or per moment.

**3. Not askable, and it describes one thing happening now. It must not outlive its host.**
`browsingDisplays`, and `AppState.storedWebViewErrors` beside it in memory. When the display goes, the
thing they describe stops existing, so there is nothing to restore — the entry is erased and made
again on reconnect. `AppState.rebuildScenes` prunes both when a display goes.

A display going is not the only way a host ends, and reading it as though it were is what let a stored
failure outlive the load it described. The host of that entry is the load, not the screen: it also ends
when the page is dropped with the display still attached, which is a display switched off or the app
disabled. `WallpaperScene.releaseWebView` clears it there, next to the `loadedWebsite` it clears for
the same reason. Class 3 is the shortest-lived class in this file and the easiest to mistake for class
2 — ask what the entry describes, then ask every way that thing can stop.

Classes 1 and 2 together are what make unplug and replug behave, and they read as a contradiction only
until they are told apart: the display coming back at all is class 1 restoring itself, and it coming
back still switched off is class 2 never having been withdrawn.

`AppState.isManuallyDisabled` was the one member out of place, and is the worked example of what
getting the sort wrong costs. It is class 2 — the user pressed Disable, and nothing can ask the
machine whether they did — and it was a plain property that died with the process. So the only "off"
that survived a quit was the per-display one, and a Mac switched off as a whole came back on by
itself the next morning. It has a key of its own below now, and `Events` turns a change to it into
`setEnabledStatus()`, which is what carries the wipe in `RestoreDefaults` back into the running app.
*/
extension Defaults.Keys {
	// The lists a display picks between, and the whole of where a website is stored. There is no other
	// copy: the pre-playlist `websites` key and the conversion that read it are both deleted.
	static let playlists = Key<[Playlist]>("playlists", default: [])

	// Which website each display is showing, keyed by `Display.settingsKey(for:)` like every other
	// per-display fact. It was a `Bool` on each website, kept unique by a sweep over the whole list —
	// one slot per website answering a question per display, so a sweep run for one screen could rewrite
	// another screen's answer, and did: one display's rotation tick cleared the other display's mark,
	// that display then read "nothing is current", started counting from the beginning and never moved
	// past the first website in its list. Two marks on one display was the same defect the other way up
	// and silent — a tie broken by list order, so a website sent to a screen never appeared on it.
	//
	// A dictionary has room for exactly one answer per display, so the invariant is the storage rather
	// than something a function has to keep true on every write. That is the whole of the change: there
	// is no repair pass any more because there is no state a repair could find.
	//
	// Class 2 above, so nothing forgets an entry. An unplug does nothing else at all either — a display
	// that is gone has no scene, so there is nothing on that screen to move anywhere.
	//
	// Which is why this is the mark and not the answer: it says what a display was told, and a display
	// that is not there was told something it never carried out. `WebsitesController`'s header names
	// the three and says which questions go to which.
	static let currentWebsites = Key<[String: Website.ID]>("currentWebsites", default: [:])

	// Which playlist each display is pointed at, keyed by `Display.settingsKey(for:)` like every other
	// per-display fact. Written in one place — the picker in the panel — and read in one place,
	// `WebsitesController.playlist(for:in:)`, which is where the rule below lives.
	//
	// **An absent entry is the default playlist, not "nothing".** Every attached display gets a scene
	// now, so a display the user has never picked for still has to show something, and the mechanism
	// that used to answer that — the Nth shipped website pinned to the Nth screen — was deleted by the
	// same change that built the scenes from the displays. Without the fallback a second monitor on a
// fresh install draws "No page selected" and waits to be told. It is also why the default playlist
	// refuses a binding: it is the one every picker offers and every display falls back to.
	//
	// Class 2 above, with `currentWebsites`: the list a user chose for a screen is a choice about that
	// screen, so nothing forgets an entry.
	static let currentPlaylists = Key<[String: Playlist.ID]>("currentPlaylists", default: [:])
	// Which displays are interactive, not whether any is. Browsing Mode was one flag for the whole app,
	// so entering it on the monitor also raised the laptop's wallpaper over its desktop icons — and its
	// button lit in every column at once. `DesktopWindow.isInteractive` was always per window; only this
	// was not.
	static let browsingDisplays = Key<Set<String>>("browsingDisplays", default: [])

	// Settings
	static let fullscreenCompatibilityMode = Key<Bool>("fullscreenCompatibilityMode", default: false)
	static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)
	static let opacity = Key<Double>("opacity", default: 1)
	// **A switch and a number, not a number that goes missing.** This was `Key<Double?>` with `nil`
	// meaning off, and the switch in Settings wrote `nil` on the way off and a constant on the way back
	// on — so somebody who set thirty minutes, switched the reload off and switched it on again got an
	// hour. The setting throws away the only thing the user typed into it. `dimWhenUnfocused` and
	// `dimmedOpacityFactor` are the shape this now copies: the switch says whether, the number says how
	// long, and turning one off cannot reach the other.
	//
	// The pair is the shape from here on. It was converted into once, from an optional interval where
	// absent meant off, and the conversion that read the raw store to tell "absent" from "the default"
	// is deleted along with every other migration in this app.
	static let reloadInterval = Key<Double>("reloadInterval", default: 60 * 60)

	// Whether the number above is used at all. Off is what this app ships with.
	static let reloadOnInterval = Key<Bool>("reloadOnInterval", default: false)

	// How often the menu bar band takes a fresh colour off the top of the page, in seconds, and
	// whether it does. The pair above's shape, built that way from the start rather than converted into
	// it: the switch is the on/off and the number is always valid, so switching off and on again
	// returns the interval the user typed rather than the one the switch happens to write.
	//
	// Off is what ships, so the colour moves when the website does and at no other time — which is what
	// the app did before these keys existed.
	//
	// Five minutes when it is switched on, where the reload interval above fills in an hour, and the
	// gap is measured rather than a matter of taste. That one refetches a page over the network; this
	// one photographs a strip of a view already on screen and averages it, at 0.52ms end to end in
	// `NSImage.averageColor` — cheaper than one refresh of the panel. What it buys is the case this app
	// is for: a webcam at dusk, a fluid simulation, a picture of the day. None of those navigates, so
	// none of them fired the load events the band is otherwise sampled on, and the menu bar kept a
	// colour taken hours ago from the wallpaper directly behind it.
	//
	// Both are the app's settings and not the user's websites, which is the question
	// `RestoreDefaultsTests` makes every new key answer. They describe how the app draws a display, like
	// `opacity` and `dimWhenUnfocused`; nothing the user wrote is stored in them. So
	// `Defaults.removeAll()` takes them with the rest and `RestoreDefaults.websiteKeys` must not name
	// them — a restore puts the menu bar colour back to moving only when the website does.
	static let menuBarColorInterval = Key<Double>("menuBarColorInterval", default: 5 * 60)
	static let updateMenuBarColorOnInterval = Key<Bool>("updateMenuBarColorOnInterval", default: false)

	static let deactivateOnBattery = Key<Bool>("deactivateOnBattery", default: false)
	static let bringBrowsingModeToFront = Key<Bool>("bringBrowsingModeToFront", default: false)
	static let openExternalLinksInBrowser = Key<Bool>("openExternalLinksInBrowser", default: false)

	static let restoreScrollPosition = Key<Bool>("restoreScrollPosition", default: true)
	static let reloadOnWake = Key<Bool>("reloadOnWake", default: true)
	static let dimWhenUnfocused = Key<Bool>("dimWhenUnfocused", default: false)
	static let dimmedOpacityFactor = Key<Double>("dimmedOpacityFactor", default: 0.5)

	// Keyed by display. A dictionary rather than a key per screen, because screens come and go and a
	// key that named one would outlive it.
	static let rotationModes = Key<[String: RotationMode]>("rotationModes", default: [:])

	// Minutes, keyed by display, same shape and same reason as `rotationModes` — the two are one
	// setting split in half, and keeping them in one dictionary would mean rewriting the mode every
	// time the number changed. Absent means "whatever `rotationInterval` decides", so a display nobody
	// has typed a number for stores nothing.
	static let rotationIntervals = Key<[String: Double]>("rotationIntervals", default: [:])

	// The displays switched off one at a time, as opposed to `isManuallyDisabled`, which is the whole
	// app. Stored as the exceptions rather than as a flag per display, so a screen nobody has touched
	// needs no entry and an unplugged one leaves nothing behind.
	static let disabledDisplays = Key<Set<String>>("disabledDisplays", default: [])

	// The whole app switched off, as opposed to `disabledDisplays` above, which is one screen at a
	// time. Nothing can ask the machine whether the user pressed Disable, so the answer has to be
	// written down or their intent lasts until the next quit — see the classes at the top of this file,
	// where this used to be named as the one member out of place.
	//
	// `AppState.isManuallyDisabled` reads and writes it, and `Events` turns a change here into
	// `setEnabledStatus()`. That is also what makes Restore Defaults switch the app back on: the wipe
	// removes this key one key at a time, so the change reaches the running app the same way a press
	// of Disable does.
	static let isManuallyDisabled = Key<Bool>("isManuallyDisabled", default: false)

	static let contentRulesURL = Key<String?>("contentRulesURL")
	static let hasInstalledFeaturedWebsites = Key<Bool>("hasInstalledFeaturedWebsites", default: false)

	// What the last check found, so the panel can say it without asking the network. The version rather
	// than a "there is an update" flag: the comparison against the running version is free on every
	// read, while a stored flag survives the update it was about and goes on being wrong.
	static let latestKnownVersion = Key<String?>("latestKnownVersion")

	// On by default, off in one click. An app that checks on its own has to be an app that can be told
	// not to.
	static let checksForUpdatesAutomatically = Key<Bool>("checksForUpdatesAutomatically", default: true)
}

extension Defaults {
	static var fullscreenCompatibility: FullscreenCompatibility {
		FullscreenCompatibility(isEnabled: Defaults[.fullscreenCompatibilityMode])
	}
}

extension Notification.Name {
	// One name, not a pair. `showEditWebsiteDialog` went with the menu that posted it: its observer
	// opened `AppState.currentWebsite`, which is the main display's website whatever screen the
	// request came from, so re-wiring it to the panel would have opened the laptop's website while
	// somebody was looking at the monitor. The panel's name row wants a per-display route instead —
	// roadmap W6.
	static let showAddWebsiteDialog = Self("showAddWebsiteDialog")
}
