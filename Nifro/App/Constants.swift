import SwiftUI
import KeyboardShortcuts

enum Constants {
	static let repositoryURL = URL("https://github.com/PathGao/Nifro")
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
	static let isBrowsingMode = Key<Bool>("isBrowsingMode", default: false)

	// Settings
	static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)
	static let opacity = Key<Double>("opacity", default: 1)
	static let reloadInterval = Key<Double?>("reloadInterval")
	static let display = Key<Display?>("display")
	static let deactivateOnBattery = Key<Bool>("deactivateOnBattery", default: false)
	static let showOnAllSpaces = Key<Bool>("showOnAllSpaces", default: false)

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
	static let playlistInterval = Key<Double?>("playlistInterval")
	static let contentRulesURL = Key<String?>("contentRulesURL")
	static let hasInstalledFeaturedWebsites = Key<Bool>("hasInstalledFeaturedWebsites", default: false)
}

extension Notification.Name {
	static let showAddWebsiteDialog = Self("showAddWebsiteDialog")
	static let showEditWebsiteDialog = Self("showEditWebsiteDialog")
}
