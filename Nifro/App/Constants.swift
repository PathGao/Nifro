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

extension Defaults.Keys {
	// The website list as it was before playlists, read exactly once and never written. It is the only
	// input `migrateToPlaylistsIfNeeded` has, and plain `Website` is the whole of what that takes from
	// it — everything lands in one playlist now, including what was pinned, which is argued where the
	// migration is written.
	//
	// A record written before playlists carries the display it was pinned to as a `display` object
	// sitting beside the website's own fields, and this decodes those records without it: a synthesised
	// `Codable` asks for the keys it knows and ignores the rest, so `display` is skipped exactly as
	// `isCurrent` — deleted a release earlier — already is. That is not a change in what happens, only
	// in what is written down. The wrapper that used to be here read the pinning out and handed it to a
	// `.map(\.website)`, which threw it away again.
	//
	// Left on disk rather than removed. Nothing in this build touches the stored value, so a list
	// carried across by the migration is still there in its old shape — which is the only copy of it
	// there will ever be, and the thing to look at if the playlists come out wrong. Nothing puts edits
	// made here back into it, so an older build opened after this one shows the list as it stood when
	// the migration ran, pinning and all.
	static let websites = Key<[Website]>("websites", default: [])

	// The lists a display picks between, and the whole of where a website is stored. Built once by
	// `migrateToPlaylistsIfNeeded` out of the key above.
	static let playlists = Key<[Playlist]>("playlists", default: [])

	// Whether the list above has been built from `websites` yet. A flag of its own, and not "there are
	// no playlists": an empty list is a state the user can reach and stay in, so reading it as "not
	// done yet" would rebuild their playlists out of a website list they stopped editing long ago,
	// every launch, for as long as they left it that way. Same shape and same reason as
	// `hasInstalledFeaturedWebsites` below, and a sharper reason — deleting what that added undoes it,
	// and what this adds is everything.
	static let hasMigratedWebsitesToPlaylists = Key<Bool>("hasMigratedWebsitesToPlaylists", default: false)

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
	// Nothing forgets an entry, which puts this with `rotationModes` and the two beside it rather than
	// with `browsingDisplays`: the user picked that wallpaper for that screen, so a monitor unplugged at
	// night comes back in the morning showing it. An unplug does nothing else at all — a display that
	// is gone has no scene, so there is nothing on that screen to move anywhere.
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
	// fresh install draws "No Website" and waits to be told. It is also why the default playlist
	// refuses a binding: it is the one every picker offers and every display falls back to.
	//
	// Nothing forgets an entry, which puts this with `currentWebsites` above rather than with
	// `browsingDisplays`: the list a user chose for a screen is a choice about that screen, so a
	// monitor unplugged at night comes back in the morning showing it.
	static let currentPlaylists = Key<[String: Playlist.ID]>("currentPlaylists", default: [:])
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

	// What the last check found, so the panel can say it without asking the network. The version rather
	// than a "there is an update" flag: the comparison against the running version is free on every
	// read, while a stored flag survives the update it was about and goes on being wrong.
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
