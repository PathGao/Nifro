import Foundation
import Testing

/**
The guardrail on "what a page remembers is filed under the website, not under the address".

Every per-page record — the scroll position, the fragment the page moved itself to, the zoom level —
used to be keyed by the page's address, while the storage those pages actually run in is
`WKWebsiteDataStore(forIdentifier:)` on the website's `id`. Two entries with different ids and the
same URL therefore had separate logins and one shared scroll position, each overwriting the other's
on every reload. It took adding the same address twice to reach, which is why it survived so long;
duplicating a list of websites mints exactly that pair on purpose, once per copy.

The compiler already refuses a `URL` where the key builder now wants a `Website.ID`. What it cannot
refuse is the builder being given its old shape back, or a second address-shaped route to a key being
added beside it — and either one is invisible until two entries on one URL are in front of somebody.

Shape rather than behaviour, for the reason `SwitchedOffTests` spells out: the SwiftPM target next
door compiles ten pure files out of `Sites` and `Support`, none of `Wallpaper`, so there is no
`PerPageDefaults` here to call and no `UserDefaults` worth writing into. The property is about which
value reaches the key, which is readable from the source.
*/
@Suite("Per-page records are keyed by website, not by address")
struct PerPageKeyTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The app's Swift files with their prose taken out.

	Every one of these files argues for itself at length, and the argument for this key quotes the
	address-shaped one it replaced. Matching against the comments would fail on the explanation of why
	the code is right.
	*/
	private static func sources() throws -> [(name: String, text: String)] {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try FileManager.default
			.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "swift" }
			.sorted { $0.path < $1.path }
			.map {
				(
					$0.lastPathComponent,
					try String(contentsOf: $0, encoding: .utf8)
						.replacing(block, with: "")
						.replacing(line, with: "")
				)
			} ?? []
	}

	@Test("The one thing that builds a key asks for a website id")
	func theBuilderTakesAnIdentifier() throws {
		let builder = try Regex("func key\\(for [^)]*\\)")
		var declarations: [String] = []

		for (name, text) in try Self.sources() {
			for match in text.matches(of: builder) {
				declarations.append(String(match.0))
			}

			#expect(
				!text.contains("perPageDefaultsKeySuffix"),
				"""
				\(name) turns an address into a per-page key. That is the defect: the store the page \
				runs in is keyed by `website.id`, so a key built from the address gives two entries on \
				one URL separate storage and one shared record.
				"""
			)
		}

		#expect(
			declarations == ["func key(for websiteID: Website.ID)"],
			"""
			`PerPageDefaults.key` is what every per-page record's key goes through, and it has to take \
			the website's `id` — the same value `WKWebsiteDataStore(forIdentifier:)` is given. Found: \
			\(declarations).
			"""
		)
	}

	@Test("Every caller hands it one")
	func everyCallSitePassesAnIdentifier() throws {
		let call = try Regex("PerPageDefaults\\.\\w+\\.key\\(for: ([^)]+)\\)")
		let identifier = try Regex("(?i)id$")

		for (name, text) in try Self.sources() {
			for match in text.matches(of: call) {
				let argument = String(match[1].substring ?? "")

				#expect(
					argument.contains(identifier),
					"""
					\(name) asks for a per-page key with `\(argument)`, which is not a website id. \
					Anything address-shaped puts two entries carrying the same URL back on one record.
					"""
				)
			}
		}
	}
}
