import SwiftUI
import KeyboardShortcuts

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

extension Defaults.Keys {
	static let websites = Key<[Website]>("websites", default: [])
	// Which displays are interactive, not whether any is. Browsing Mode was one flag for the whole app,
	// so entering it on the monitor also raised the laptop's wallpaper over its desktop icons — and its
	// button lit in every column at once. `DesktopWindow.isInteractive` was always per window; only this
	// was not.
	static let browsingDisplays = Key<Set<String>>("browsingDisplays", default: [])

	// Settings
	static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)
	static let opacity = Key<Double>("opacity", default: 1)
	static let reloadInterval = Key<Double?>("reloadInterval")
	static let deactivateOnBattery = Key<Bool>("deactivateOnBattery", default: false)

	// Defaults to what the app already did, so nobody's wallpaper changes on upgrade. There is no
	// convention to follow here: macOS's own wallpaper stays with its display and goes away with it,
	// AppKit moves a window off a departed screen rather than losing it, and this wallpaper is a
	// window. Upstream has no answer either — Plash has no per-display websites at all.
	static let keepWallpaperWhenDisplayUnplugged = Key<Bool>("keepWallpaperWhenDisplayUnplugged", default: true)
	static let bringBrowsingModeToFront = Key<Bool>("bringBrowsingModeToFront", default: false)
	static let openExternalLinksInBrowser = Key<Bool>("openExternalLinksInBrowser", default: false)

	static let restoreScrollPosition = Key<Bool>("restoreScrollPosition", default: true)
	static let reloadOnWake = Key<Bool>("reloadOnWake", default: true)
	static let dimWhenUnfocused = Key<Bool>("dimWhenUnfocused", default: false)
	static let dimmedOpacityFactor = Key<Double>("dimmedOpacityFactor", default: 0.5)

	// Read, never written. Up to 0.1.3 this was the rotation interval in seconds for the whole machine,
	// and a display with no interval of its own still inherits it so that nobody's setting disappears
	// on upgrade. `rotationInterval(stored:legacySeconds:)` is the only reader; delete both in 1.0.
	static let playlistInterval = Key<Double?>("playlistInterval")

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

	// Website id -> where the server sent it instead. Only written when WebKit reports an actual
	// redirect, never inferred by comparing addresses: a page that rewrites its own address as you
	// drag a map is not a redirect, and telling the user their website is wrong because they moved a
	// map would be worse than saying nothing.
	static let redirectedAddresses = Key<[String: String]>("redirectedAddresses", default: [:])
	static let contentRulesURL = Key<String?>("contentRulesURL")
	static let hasInstalledFeaturedWebsites = Key<Bool>("hasInstalledFeaturedWebsites", default: false)

	// What the last check found, so the menu can say it without asking the network. The menu is rebuilt
	// from scratch every time it opens, so anything it triggers, it triggers on every open.
	static let latestKnownVersion = Key<String?>("latestKnownVersion")

	// On by default, off in one click. An app that checks on its own has to be an app that can be told
	// not to.
	static let checksForUpdatesAutomatically = Key<Bool>("checksForUpdatesAutomatically", default: true)
}

extension Notification.Name {
	// One name, not a pair. `showEditWebsiteDialog` went with the menu that posted it: its observer
	// opened `AppState.currentWebsite`, which is the main display's website whatever screen the
	// request came from, so re-wiring it to the panel would have opened the laptop's website while
	// somebody was looking at the monitor. The panel's name row wants a per-display route instead —
	// roadmap W6.
	static let showAddWebsiteDialog = Self("showAddWebsiteDialog")
}
