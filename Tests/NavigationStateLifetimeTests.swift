import Foundation
import Testing

/**
The guardrail on "state that belongs to one navigation, or to one download, is not shared with the
next one".

Two properties on `WebViewController` had the same shape: one slot, written by whatever came last,
read by whatever finished first, and never cleared. The controller is the wrong owner for both, and
for two different reasons.

The response's MIME type decides whether the finished page is a bare image that has to be centred and
cropped. One controller is the navigation delegate for every web view a display uses, and a swap
deliberately keeps two of them alive at once — so a replacement loading out of sight answered that
question for the page already on screen. Per web view is not enough on its own either: within one web
view, a local folder and a framed player's host page produce no `HTTPURLResponse` at all, so they
inherited the answer from whatever that view showed before them.

The download destination is not per web view or per navigation; it belongs to a `WKDownload`. Two
downloads in flight meant the second one's path was handed to the first one's completion, and the
Dock bounced at a file that had not arrived.

Shape rather than behaviour, for the reason `SwitchedOffTests` gives at length: the SwiftPM target
next door compiles ten files out of `Sites` and `Support` and none of `Wallpaper`. Neither path here
has a version that runs without WebKit, a window server and a network — one needs a page that answers
with an image and then one that answers with nothing, the other two downloads racing. What is left
that a test can hold is the ownership the argument rests on, anchored on WebKit's own names wherever
there is one to anchor on, so that a rename is a compile error rather than a silently green test.
*/
@Suite("Per-navigation and per-download state is not shared")
struct NavigationStateLifetimeTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The file with its prose taken out. Both files argue for themselves at length and the arguments
	name the very things being looked for.
	*/
	private static func source(_ path: String) throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(contentsOf: root.appending(path: path), encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	/**
	The body of a declaration, from its opening brace to the brace that closes it. Counted rather than
	matched with a regex, for the reason `ScopeTests` gives: every body below has braces of its own.
	*/
	private static func body(of declaration: String, in source: String) throws -> String {
		guard let start = source.range(of: declaration) else {
			Issue.record("`\(declaration)` is no longer written that way, so this test is reading nothing.")
			return ""
		}

		guard let open = source[start.upperBound...].firstIndex(of: "{") else {
			Issue.record("`\(declaration)` has no body.")
			return ""
		}

		var depth = 0

		for index in source.indices[open...] {
			switch source[index] {
			case "{":
				depth += 1
			case "}":
				depth -= 1

				if depth == 0 {
					return String(source[open...index])
				}
			default:
				break
			}
		}

		Issue.record("`\(declaration)`'s body is unbalanced.")
		return ""
	}

	@Test("The page's MIME type is kept on the web view that was told it")
	func theMIMETypeBelongsToOneWebView() throws {
		#expect(
			try Self.source("Nifro/Wallpaper/SSWebView.swift").contains("var responseMIMEType"),
			"The response's MIME type is not stored on the web view any more, so the two views a swap keeps alive share one answer and whichever finishes last decides it for both."
		)

		// The old declaration, exactly. `as? HTTPURLResponse)` in the policy callback does not match
		// it, and neither would a differently named slot — which is the point: what has to stay true
		// is that this controller holds no response of its own, whatever it would be called.
		#expect(
			try !Self.source("Nifro/Wallpaper/WebViewController.swift").contains("HTTPURLResponse?"),
			"`WebViewController` holds a response again. It is one per display and outlives every page it shows, so a slot on it belongs to no navigation in particular."
		)
	}

	@Test("A navigation does not inherit the last one's MIME type")
	func eachNavigationStartsWithNoAnswer() throws {
		let source = try Self.source("Nifro/Wallpaper/WebViewController.swift")

		// Anchored on WebKit's selector rather than on a helper this repository could rename, and on
		// this one rather than on the policy callback: it is the main frame only, and it runs for the
		// loads that never produce an `HTTPURLResponse` — which are the loads that were reading the
		// previous page's.
		#expect(
			try Self.body(of: "didStartProvisionalNavigation navigation: WKNavigation!", in: source)
				.contains("responseMIMEType = nil"),
			"A starting navigation no longer clears the MIME type, so a local folder or a framed player's host page is treated as whatever the page before it was."
		)
	}

	@Test("Every download's destination is filed and taken back under its own download")
	func eachDownloadKeepsItsOwnDestination() throws {
		let source = try Self.source("Nifro/Wallpaper/WebViewController.swift")

		#expect(
			try Self.body(of: "decideDestinationUsing response: URLResponse, suggestedFilename: String", in: source)
				.contains("ObjectIdentifier(download)"),
			"The destination is filed under something other than the download it belongs to, so a second download in flight overwrites the first one's path."
		)

		// Both endings, because one of them clearing is not a fix. `WKDownloadDelegate` has exactly
		// these two terminal callbacks — a cancelled download reaches the second — so an entry that
		// survives either one is an entry nothing will ever take out.
		let endings = [
			"func downloadDidFinish(_ download: WKDownload)",
			"didFailWithError error: Error, resumeData: Data?"
		]

		for declaration in endings {
			let body = try Self.body(of: declaration, in: source)

			#expect(
				body.contains("removeValue(forKey: ObjectIdentifier(download))")
					|| body.contains("[ObjectIdentifier(download)] = nil"),
				"`\(declaration)` leaves its entry behind, so the map grows for the life of the app — the same defect as the single slot it replaced, with a bigger footprint."
			)
		}
	}
}
