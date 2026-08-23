import SwiftUI
import KeyboardShortcuts

enum Constants {
	static let repositoryURL = URL("https://github.com/PathGao/nifro")
	static let siteGalleryURL = URL("https://github.com/PathGao/nifro/tree/main/sites")
	static let siteSubmissionURL = URL("https://github.com/PathGao/nifro/issues/new?template=site_submission.yml")

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
	static let bringBrowsingModeToFront = Key<Bool>("bringBrowsingModeToFront", default: false)
	static let openExternalLinksInBrowser = Key<Bool>("openExternalLinksInBrowser", default: false)

	static let extendBelowMenuBar = Key<Bool>("extendBelowMenuBar", default: false)
	static let freezeWhenCovered = Key<Bool>("freezeWhenCovered", default: true)
	static let solidColorUnderMenuBar = Key<Bool>("solidColorUnderMenuBar", default: false)
	static let restoreScrollPosition = Key<Bool>("restoreScrollPosition", default: true)
	static let reloadOnWake = Key<Bool>("reloadOnWake", default: true)
	static let dimWhenUnfocused = Key<Bool>("dimWhenUnfocused", default: false)
	static let dimmedOpacityFactor = Key<Double>("dimmedOpacityFactor", default: 0.5)
	static let playlistInterval = Key<Double?>("playlistInterval")
	static let contentRulesURL = Key<String?>("contentRulesURL")
	static let hasInstalledFeaturedWebsites = Key<Bool>("hasInstalledFeaturedWebsites", default: false)
}

extension KeyboardShortcuts.Name {
	/**
	Every shortcut the app registers.

	Listed so the menu can turn them all off while it is open. `NSMenu` puts the thread in tracking
	mode, which stops the global hotkeys from being delivered and buffers the key events instead.
	They then all fire at once when the menu closes, which reads as the app doing something nobody
	asked for.
	*/
	static let all: [Self] = [
		.toggleBrowsingMode,
		.holdToInteract,
		.toggleEnabled,
		.reload,
		.nextWebsite,
		.previousWebsite,
		.randomWebsite
	]

	/**
	The modifier every default uses.

	These are global hotkeys: they fire whatever app is in front, so a default is a claim on a key
	combination in every app the user owns. Control-Option-Command is the one region macOS itself
	barely uses and almost no app defaults into, which makes it the only place a default can be set
	without taking something away. A shortcut that shipped as nothing is a shortcut nobody discovers,
	because the menu has nothing to show next to the command.
	*/
	private static let defaultModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

	static let toggleBrowsingMode = Self("toggleBrowsingMode", default: .init(.b, modifiers: defaultModifiers))
	static let holdToInteract = Self("holdToInteract", default: .init(.h, modifiers: defaultModifiers))
	static let toggleEnabled = Self("toggleEnabled", default: .init(.w, modifiers: defaultModifiers))
	static let reload = Self("reload", default: .init(.r, modifiers: defaultModifiers))
	static let nextWebsite = Self("nextWebsite", default: .init(.rightBracket, modifiers: defaultModifiers))
	static let previousWebsite = Self("previousWebsite", default: .init(.leftBracket, modifiers: defaultModifiers))
	static let randomWebsite = Self("randomWebsite", default: .init(.k, modifiers: defaultModifiers))
}

extension Notification.Name {
	static let showAddWebsiteDialog = Self("showAddWebsiteDialog")
	static let showEditWebsiteDialog = Self("showEditWebsiteDialog")
}
