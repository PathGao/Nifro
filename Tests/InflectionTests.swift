import Foundation
import Testing

/**
The guardrail on inflection markup being shown to the user instead of applied.

`^[…](inflect: true)` asks Foundation for automatic grammatical agreement, and the agreement is done
while the string is still attributed. `Text` and `AttributedString(localized:)` go that way and
inflect; `String(localized:)` resolves to a plain `String` and, when the lookup finds no table entry
to inflect, hands back the key with the markup still in it.

That is not a hypothetical. `WebsitesScreen` built a playlist's subtitle with `String(localized:)`,
and the English app — the development language, which has no `.lproj` in the bundle at all, see
`Localization` — drew "^[8 website](inflect: true)" under every playlist name. zh-Hans hid it: its
translation is "%lld 个网站" with no marker left to process, so the one language anybody tested in was
the one language that could not fail. Three keys use the markup and only that one call site was
wrong, which is the second shape in `WORKSPACE_GUIDE.md`: a mechanism with a member that never
joined.

Shape rather than behaviour, on that file's criterion, because the claim is an absence — no call of
this form exists anywhere — and no function can be asked whether something is not written.
*/
@Suite("Inflection markup is never resolved to a plain String")
struct InflectionTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	@Test("No `String(localized:)` carries an inflection marker")
	func inflectionIsNeverResolvedToAString() throws {
		// The argument runs to the closing quote of the literal, escapes included, which is what keeps
		// a `\"` inside the string from ending the match early.
		let call = try Regex("String\\(localized: \"((?:[^\"\\\\]|\\\\.)*)\"")

		let sources = FileManager.default
			.enumerator(at: Self.root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "swift" } ?? []

		#expect(!sources.isEmpty, "Found no Swift files to check, so this test is reading nothing.")

		// Doc comments quote the markup while explaining it — this file's own subject — so a comment
		// left in would fail the test for the explanation of why it exists.
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let ownLine = try Regex("^[\\t ]*//[^\\n]*").anchorsMatchLineEndings()

		for url in sources {
			let source = try String(contentsOf: url, encoding: .utf8)
				.replacing(block, with: "")
				.replacing(ownLine, with: "")

			for match in source.matches(of: call) {
				guard let key = match.output[1].substring.map(String.init) else {
					continue
				}

				guard key.contains("^[") else {
					continue
				}

				Issue.record(
					"""
					\(url.lastPathComponent) resolves an inflected string with `String(localized:)`, \
					which leaves the markup in the text: \(key). Use `Text` or \
					`AttributedString(localized:)`.
					"""
				)
			}
		}
	}
}
