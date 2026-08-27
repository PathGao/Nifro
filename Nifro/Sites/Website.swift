import Foundation

struct Website: Hashable, Codable, Identifiable, Sendable, Defaults.Serializable {
	// `var` only because the whole struct is decoded and re-encoded as one; nothing assigns this after
	// the entry is made. The id is what a website's data store, its thumbnail and its remembered
	// scroll position are all filed under, so changing one would orphan all three.
	var id: UUID
	var isCurrent: Bool
	var url: URL
	@DecodableDefault.EmptyString var title: String
	@DecodableDefault.Custom<InvertColors> var invertColors2
	var usePrintStyles: Bool
	var css = ""
	var javaScript = ""
	@DecodableDefault.False var allowSelfSignedCertificate

	/**
	Which part of the page fills the wallpaper. `nil` shows the whole page.

	Used to cut away a site's navigation and borders and keep only the part the user wants, enlarged
	to fill the screen rather than left as a small rectangle with desktop around it.
	*/
	var zoom: Zoom?

	/**
	Which display to show this website on. `nil` means the main display — the one with the menu bar.

	`nil` is not "the display Settings names": there is no such setting, and there never has been. It
	resolves through `Display.main` on every read, so it follows the menu bar when displays are
	rearranged or the laptop is docked, rather than naming a screen once.

	The most-asked-for thing has always been a different page on each screen, a calendar on one and a dashboard on the other. That needs the display to be a property of the website rather than one app-wide setting.
	*/
	var display: Display?

	/**
	The hours of the day this website is allowed to be showing, if it should not always be.

	Stored as two hours rather than a range so it survives round-tripping through JSON without a custom coder, and so a range that wraps midnight (22 to 6) is expressible.
	*/
	var startHour: Int?
	var endHour: Int?

	/**
	Whether this website is allowed to make noise.

	Per website because the answer is a property of the page. A clock should never make a sound; a
	live stream is pointless without one. A single app-wide switch forces the same answer on both.
	*/
	@DecodableDefault.Custom<Audio> var audio

	/**
	Whether this website can be clicked without turning on Browsing Mode.

	Asked for repeatedly. Off by default and per website, because it costs something. A window that accepts clicks puts your desktop icons behind it, and it keeps the page awake. A page tracking the pointer cannot be frozen or drawn from stills.
	*/
	@DecodableDefault.False var allowsInteraction

	/**
	How often to reload this website, in seconds. `nil` follows the interval in Settings.

	Per website because how fast a page goes stale is a property of the page: a calendar is wrong
	after fifteen minutes, a poster is never wrong. It used to be one app-wide number, so a catalogue
	entry that wanted a daily reload set that for every website at once — which is how a wallpaper
	nobody had touched came to be reloading every 1440 minutes.
	*/
	var reloadInterval: Double?

	/**
	The display this website actually appears on.

	Falls back to the main display when the chosen one is not attached, because otherwise this answers
	with a display that is not there and every caller believes it. `displaysInUse` kept building a
	scene for an unplugged display, and both `DesktopWindow.setFrame` and `WallpaperScene.screen` then
	fall back to `.main` on their own — so an undocked laptop ended up with two full-screen wallpaper
	windows stacked on the built-in screen, each with its own timers and its own menu-bar band
	competing for one menu bar.

	`display` itself is left alone, so plugging the display back in puts the website back on it.
	*/
	@MainActor
	var effectiveDisplay: Display? {
		guard let chosen = display ?? .main else {
			return nil
		}

		return Defaults[.keepWallpaperWhenDisplayUnplugged] ? chosen.withFallbackToMain : chosen
	}

	/**
	Whether this website should be on screen at all right now.

	False only for a website pinned to a display that is not attached, and only when the user has said
	such a wallpaper should go away with its display rather than move. Kept apart from
	`effectiveDisplay` because that answers *where*, and `nil` there already means "the main display" —
	there is no value it could return that means nowhere.
	*/
	@MainActor
	var isShowable: Bool {
		Defaults[.keepWallpaperWhenDisplayUnplugged] || (display ?? .main)?.isConnected != false
	}

	/**
	Whether this website is on a display it was sent to rather than the one it was given.

	True only for a website pinned to a display that is not attached, and only while such a wallpaper
	is set to move rather than go away — which is the same pair of conditions `isShowable` reads, from
	the other side. `display` is left alone either way, so this goes back to false the moment that
	screen is plugged in again.

	What it is for is the tie it settles once the website has landed: two wallpapers now claim one
	desktop, and `showingIndex` gives it to this one.
	*/
	@MainActor
	var isEvicted: Bool { isShowable && display?.isConnected == false }

	/**
	How often this website actually reloads.
	*/
	var effectiveReloadInterval: Double? { reloadInterval ?? Defaults[.reloadInterval] }

	/**
	The CSS this website actually applies, `nil` when it applies none.

	A hand-added website starts with `starterCSS` in the field and every line of it is a comment, so an
	untouched template is fourteen lines that change nothing. Anything asking whether this website has
	custom code has to treat that as none, or it answers yes for every website nobody has edited — which
	is what the bug report text did, and CONTRIBUTING names that field as one of the two answers that
	settle most reports.
	*/
	var customCSS: String? {
		css.trimmed.isEmpty || css == Self.starterCSS ? nil : css
	}

	/**
	The JavaScript this website actually runs, `nil` when it runs none. Same reasoning as `customCSS`.
	*/
	var customJavaScript: String? {
		javaScript.trimmed.isEmpty || javaScript == Self.starterJavaScript ? nil : javaScript
	}

	var subtitle: String { url.humanString }

	var menuTitle: String { title.isEmpty ? subtitle : title }

	// The space is there to force `NSMenu` to display an empty line.
	var tooltip: String { "\(title)\n \n\(subtitle)".trimmed }

	/**
	Symbols for the settings this website has that are not the default, in a fixed order.

	Everything here is invisible until you open the website for editing, which is fine for one website
	and useless for a list of twenty. Shown rather than spelled out because a row has space for
	symbols and not for sentences; the tooltip still spells them out.
	*/
	var badges: [String] {
		var symbols = [String]()

		if audio == .unmuted {
			symbols.append("speaker.wave.2.fill")
		}

		if zoom != nil {
			symbols.append("viewfinder")
		}

		if startHour != nil, endHour != nil {
			symbols.append("clock")
		}

		if display != nil {
			symbols.append("display")
		}

		if allowsInteraction {
			symbols.append("hand.tap")
		}

		return symbols
	}

	/**
	The key this website's preview image is cached under.

	The whole address, not its host. Keyed by host, every page on a site shared one image — so a list
	with several YouTube videos in it showed the same picture on all of them, which is the case where
	a preview would have been most use.
	*/
	var thumbnailCacheKey: String { url.isFileURL ? url.tildePath : url.absoluteString }

	@MainActor
	func makeCurrent() {
		WebsitesController.shared.makeCurrent(self)
	}

	@MainActor
	func remove() {
		WebsitesController.shared.remove(self)
	}
}

extension Website {
	/**
	What a new website's CSS field starts out as.

	Every line is a comment, so it changes nothing until someone edits it. What it does is put the two things people always ask for, plus the classes this app adds, in front of them while they are editing. A tips page elsewhere carries the same information further from where it is used.
	*/
	static let starterCSS = """
		/* Anything you write here is applied to the page.

		   Hide a site's own furniture:
		     header, nav, footer, .cookie-banner { display: none !important; }

		   Make the page's background transparent so your wallpaper shows through:
		     :root, body { background: transparent !important; }

		   Nifro puts these classes on <html> for you:
		     .is-nifro-app             always
		     .nifro-is-browsing-mode   only while Browsing Mode is on
		   so you can show something only when you can actually click it:
		     .nifro-is-browsing-mode nav { display: block !important; }
		*/
		"""

	/**
	What a new website's JavaScript field starts out as. Comments only, same reasoning as `starterCSS`.
	*/
	static let starterJavaScript = """
		// Runs once the page has loaded. Top-level await is allowed.
		//
		// Scroll to a fixed position:
		//   window.scrollTo(0, 500);
		//
		// Click something the page needs clicked every time:
		//   document.querySelector('.dismiss')?.click();
		"""

	enum InvertColors: String, CaseIterable, Codable {
		case never
		case always
		case darkMode

		var title: String {
			switch self {
			case .never:
				String(localized: "Never")
			case .always:
				String(localized: "Always")
			case .darkMode:
				String(localized: "When in dark mode")
			}
		}
	}
}

extension Website.InvertColors: DecodableDefault.Source {
	static let defaultValue = never
}

extension Website {
	enum Audio: String, CaseIterable, Codable, Sendable {
		case muted
		case unmuted

		var title: String {
			switch self {
			case .muted:
				String(localized: "Muted")
			case .unmuted:
				String(localized: "Plays sound")
			}
		}
	}
}

extension Website.Audio: DecodableDefault.Source {
	// Every website that existed before this setting was silent, and a wallpaper that starts talking
	// after an update is a bad surprise.
	static let defaultValue = muted
}
