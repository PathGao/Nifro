import Foundation

struct Website: Hashable, Codable, Identifiable, Sendable, Defaults.Serializable {
	let id: UUID
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
	Which display to show this website on. `nil` follows the display chosen in Settings.

	The most-asked-for thing upstream was a different page on each screen, a calendar on one and a dashboard on the other (Plash#2, 47 reactions). That needs the display to be a property of the website rather than one app-wide setting.
	*/
	var display: Display?

	/**
	The hours of the day this website is allowed to be showing, if it should not always be.

	Stored as two hours rather than a range so it survives round-tripping through JSON without a custom coder, and so a range that wraps midnight (22 to 6) is expressible.
	*/
	var startHour: Int?
	var endHour: Int?

	/**
	Whether to keep a browser running behind this website or to photograph it periodically.
	*/
	@DecodableDefault.Custom<Rendering> var rendering

	/**
	Whether this website is allowed to make noise.

	Per website because the answer is a property of the page. A clock should never make a sound; a
	live stream is pointless without one. A single app-wide switch forces the same answer on both.
	*/
	@DecodableDefault.Custom<Audio> var audio

	/**
	Whether this website can be clicked without turning on Browsing Mode.

	Asked for repeatedly upstream (Plash#50 over ten comments, Plash#16). Off by default and per website, because it costs something. A window that accepts clicks puts your desktop icons behind it, and it keeps the page awake. A page tracking the pointer cannot be frozen or drawn from stills.
	*/
	@DecodableDefault.False var allowsInteraction

	/**
	The display this website actually appears on.
	*/
	@MainActor
	var effectiveDisplay: Display? { display ?? Defaults[.display] }

	var subtitle: String { url.humanString }

	var menuTitle: String { title.isEmpty ? subtitle : title }

	// The space is there to force `NSMenu` to display an empty line.
	var tooltip: String { "\(title)\n \n\(subtitle)".trimmed }

	var thumbnailCacheKey: String { url.isFileURL ? url.tildePath : (url.host ?? "") }

	@MainActor
	func makeCurrent() {
		WebsitesController.shared.current = self
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

extension Website.Rendering: DecodableDefault.Source {
	// Watching first is the right default because the answer is a property of the page, and asking
	// the person who pasted a URL to know it in advance is asking them to guess. The watcher starts
	// a page live and only moves it to stills after a minute of seeing nothing move, so a wrong
	// answer costs a minute rather than a broken wallpaper.
	static let defaultValue = automatic
}
