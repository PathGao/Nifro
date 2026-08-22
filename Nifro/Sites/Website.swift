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
	The region of the page to show, in page coordinates with the origin at the top-left. `nil` shows the whole page.

	Used to cut away a site's navigation, borders and surrounding furniture and keep only the part worth looking at.
	*/
	var crop: CGRect?

	/**
	Which display to show this website on. `nil` follows the display chosen in Settings.

	The single most-asked-for thing upstream was not "show the same page on every screen" but "show a different page on each" — a calendar on one, a dashboard on the other (Plash#2, 47 reactions). That needs the display to be a property of the website rather than a single app-wide setting.
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
	Whether this website can be clicked without turning on Browsing Mode.

	Asked for repeatedly upstream (Plash#50 over ten comments, Plash#16). It is off by default and per website because it takes something away: a window that accepts clicks is a window your desktop icons are behind. It also keeps the page awake — a page tracking the pointer cannot be frozen or drawn from stills.
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

	Every line is a comment, so it changes nothing until someone edits it — but it puts the two things people always end up asking for, and the hooks this app provides, in front of them at the moment they need them. The alternative is a tips page somewhere else, which is a worse version of the same information.
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
				"Never"
			case .always:
				"Always"
			case .darkMode:
				"When in dark mode"
			}
		}
	}
}

extension Website.InvertColors: DecodableDefault.Source {
	static let defaultValue = never
}

extension Website.Rendering: DecodableDefault.Source {
	// Existing websites and anything typed in by hand keep rendering live. Switching a page to
	// stills without being asked would stop animations people put there on purpose.
	static let defaultValue = live
}
