import Foundation

struct Website: Hashable, Codable, Identifiable, Sendable, Defaults.Serializable {
	// `var` only because the whole struct is decoded and re-encoded as one; nothing assigns this after
	// the entry is made. The id is what a website's data store, its thumbnail and its remembered
	// scroll position are all filed under, so changing one would orphan all three.
	var id: UUID

	var url: URL
	@DecodableDefault.EmptyString var title: String
	@DecodableDefault.Custom<InvertColors> var invertColors2
	var usePrintStyles: Bool
	@DecodableDefault.EmptyString var css: String
	@DecodableDefault.EmptyString var javaScript: String
	@DecodableDefault.False var allowSelfSignedCertificate

	/**
	Which part of the page fills the wallpaper. `nil` shows the whole page.

	Used to cut away a site's navigation and borders and keep only the part the user wants, enlarged
	to fill the screen rather than left as a small rectangle with desktop around it.
	*/
	var zoom: Zoom?

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
	How often to reload this website, in seconds. `nil` follows the interval in Settings.

	Per website because how fast a page goes stale is a property of the page: a calendar is wrong
	after fifteen minutes, a poster is never wrong. It used to be one app-wide number, so a catalogue
	entry that wanted a daily reload set that for every website at once — which is how a wallpaper
	nobody had touched came to be reloading every 1440 minutes.
	*/
	var reloadInterval: Double?

	/**
	Where a link off this website opens.

	Per website because the answer is a property of the site, and the app-wide switch could only ever
	give one answer to a question that has two: a dashboard's links should leave the wallpaper, and a
	site you sign in to must not, because signing in *is* a navigation off the site's own host. The
	app-wide help text used to say exactly that and then ask the user to turn the switch off and
	remember to turn it back on afterwards, which is the manual workaround a setting exists to remove.

	Three states rather than two, because "whatever Settings says" is a real answer and the one every
	website already gives. Named rather than left as `Bool?`, following `audio` above: the same
	information, and it is a state the interface has to draw and the report has to print, so it is
	worth a word each. `@DecodableDefault` is what makes a website stored before this existed decode
	into the state it was already in.
	*/
	@DecodableDefault.Custom<ExternalLinks> var externalLinks

	/**
	How often this website actually reloads: its own interval, or the app-wide one from Settings when
	it names none.

	`if let` and not `??`, and it has to stay that way. `Defaults[.reloadInterval]` is a `Double?`
	reached through the package's generic subscript, and that drives `??` to the `T ?? T` overload with
	`T == Double?` — a left side that is no longer optional, so the right side is dead code and the
	compiler says so. Every website that named no interval of its own therefore answered `nil`,
	`WallpaperScene.resetTimer` returned at its own `let`, and no timer was ever armed: the number in
	Settings was drawn, saved, and reached nothing but the value a per-website override starts at.

	`DefaultsFallbackTests` holds the same shape away from every optional key, not just this one.
	*/
	var effectiveReloadInterval: Double? {
		if let reloadInterval {
			reloadInterval
		} else {
			Defaults[.reloadInterval]
		}
	}

	/**
	Whether a link off this website actually opens in the browser.

	A switch rather than a `??`, so a fourth state added to `ExternalLinks` has no answer here until
	somebody writes one.
	*/
	var opensExternalLinksInBrowser: Bool {
		switch externalLinks {
		case .followSettings:
			Defaults[.openExternalLinksInBrowser]
		case .browser:
			true
		case .inPlace:
			false
		}
	}

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

		if externalLinks != .followSettings {
			symbols.append("arrow.up.forward.app")
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

	/**
	Show this website on the display with the menu bar.

	The flat list in the Websites window is the one caller with no display in hand, because it is not
	about a screen — and a website has no display of its own to fall back to any more, so the fallback
	is written out here rather than hidden inside `makeCurrent`, which every other caller tells which
	display it means. A website reachable from two columns has no better answer than this one, which
	is what the picker in the panel can see and this cannot.
	*/
	@MainActor
	func makeCurrent() {
		WebsitesController.shared.makeCurrent(self, on: Display.main)
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

extension Website {
	enum ExternalLinks: String, CaseIterable, Codable, Sendable {
		case followSettings
		case browser
		case inPlace

		var title: String {
			switch self {
			case .followSettings:
				String(localized: "Follow Settings")
			case .browser:
				String(localized: "In the default browser")
			case .inPlace:
				String(localized: "In Nifro")
			}
		}
	}
}

extension Website.ExternalLinks: DecodableDefault.Source {
	// Every website that existed before this setting followed the app-wide switch, and it has to go on
	// following it — anything else silently changes what a wallpaper does on upgrade.
	static let defaultValue = followSettings
}

extension Website.Audio: DecodableDefault.Source {
	// Every website that existed before this setting was silent, and a wallpaper that starts talking
	// after an update is a bad surprise.
	static let defaultValue = muted
}
