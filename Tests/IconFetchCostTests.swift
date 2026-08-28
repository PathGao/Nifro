import Foundation
import Testing

/**
What a row's missing icon costs, and how often it is paid.

Two halves of one story. `WebsiteIconFetcher` used to load the whole page in a `WKWebView`, with its
JavaScript, before it asked `LPMetadataProvider` anything — and `LPMetadataProvider` fetches the page
itself and answers for most ordinary sites, so the common case paid for a navigation whose result was
then dropped. And `IconView` remembered nothing about a lookup that found nothing, while its `.task`
is tied to a row that `List` rebuilds every time it scrolls back into view, so that price was paid
again on every reappearance.

Shape rather than behaviour, for the reason `SwitchedOffTests` sets out at length: the SwiftPM target
next door compiles neither `Sites/WebsiteIconFetcher.swift` nor anything in `Screens`, and neither
half runs without a live `WKWebView`, a window server and a network. What is left that a test can
hold is the shape each argument rests on — which strategy is asked first, and where the record of a
miss lives.
*/
@Suite("A missing icon is looked for cheaply, and once")
struct IconFetchCostTests {
	private static let sources = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "Nifro")

	/**
	One of the app's Swift files with its prose taken out.

	Both files argue for themselves at length and the arguments name the very things being looked for,
	so matching against them would find the explanation and report it as the code.
	*/
	private static func source(_ path: String) throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(contentsOf: sources.appending(path: path), encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	/// The same source with every run of whitespace flattened, so a statement can be matched across the lines it is written on.
	private static func collapsed(_ path: String) throws -> String {
		try source(path).replacing(try Regex("\\s+"), with: " ")
	}

	@Test("The strategy that needs no page is asked before the page is loaded")
	func metadataBeforeNavigation() throws {
		let source = try Self.source("Sites/WebsiteIconFetcher.swift")

		// The calls and not the declarations, which are written in the order they were added and say
		// nothing about the order they are asked in.
		let metadata = try #require(source.range(of: "await getFromLPMetadataProvider(url: url)"))
		let load = try #require(source.range(of: "await loadAndWait(request)"))

		#expect(
			metadata.lowerBound < load.lowerBound,
			"The web view loads the page before `LPMetadataProvider` is asked, so a site it answers for pays for a navigation that is then thrown away"
		)
	}

	@Test("The favicon stays the last resort")
	func faviconIsLast() throws {
		let source = try Self.source("Sites/WebsiteIconFetcher.swift")

		// The guessed address, and the only one of the six that is a guess: everything above it was
		// named by the page itself. It answers for almost any site, correctly or not, so anything moved
		// below it is a strategy that will never be reached.
		let linkIcon = try #require(source.range(of: "await getFromLinkIcon()"))
		let favicon = try #require(source.range(of: "await getFavicon()"))

		#expect(linkIcon.lowerBound < favicon.lowerBound)
	}

	@Test("A miss is remembered for one opening of the window and no longer")
	func missIsRememberedForTheWindow() throws {
		let source = try Self.collapsed("Screens/WebsitesScreen.swift")

		// File-private and held by the screen. Those two together are the whole scope: nothing outside
		// this file can hold one, and the one the rows are handed belongs to the window they are in.
		// A `static`, a singleton or a `Defaults` key would each have to change one of these lines.
		#expect(source.contains("private final class IconFetchFailures"))
		#expect(source.contains("@State private var iconFailures = IconFetchFailures()"))

		// And emptied when the window opens, because whether closing a `Window` scene tears its view
		// down or merely puts it away is SwiftUI's to decide. A miss that outlived the closing would be
		// a minute of no network blanking an icon for the rest of the session.
		#expect(
			source.contains(".onAppear { iconFailures.urls.removeAll() }"),
			"Nothing empties the record when the window opens, so it lasts as long as SwiftUI happens to keep the view"
		)
	}

	@Test("A lookup that was cancelled is not a miss")
	func cancellationIsNotAMiss() throws {
		let source = try Self.collapsed("Screens/WebsitesScreen.swift")

		// The row that scrolls away cancels its own task, which is most of what stops a lookup early.
		// Written down as a miss, that would mean hurrying down a long list left a grey square behind
		// every row that went past mid-fetch.
		#expect(
			source.contains("if !Task.isCancelled { iconFailures.urls.insert(website.url) }"),
			"A cancelled lookup is recorded as a failure, so scrolling fast is what blanks the icons"
		)
	}
}
