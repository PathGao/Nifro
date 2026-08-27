import Foundation
import Testing

/**
The guardrail on "a string translated and never shown".

The counterpart to `UnreadSettingsTests`, and the same debris from the same event. That one catches a
setting written and read by nothing; this catches text carried and displayed by nothing. #21 deleted
the status bar menu, and eight of its strings stayed behind in `Localizable.xcstrings` — with their
Simplified Chinese kept in step by every translation pass since, for text no user could ever reach.
"Deactivated While on Battery", "Not showing", "Choose Region…" and "Update to %@…" were menu items
and menu status lines. The cost is not the bytes. It is that every future translation pass, and every
new language, pays for them.

Nothing gated it. `ci.yml` checks the two directions that produce a *missing* string — every key has a
zh-Hans value, every literal in the source is in the catalogue — and neither notices a key with no
literal behind it. That asymmetry is the whole hole: the catalogue only ever grows.

Shape rather than behaviour, and unrunnable rather than unreachable, on `WORKSPACE_GUIDE.md`'s
criterion — the same one `PlaceholderTests` next door meets. It is a claim about a `.xcstrings` file
and every Swift file agreeing, and no function anywhere can answer it.

**The ceiling, stated rather than discovered later.** This matches text, so a key whose every literal
fragment also occurs inside a *live* string is invisible to it. `Quit %@` was exactly that: dead since
#21, while `DisplayPanel` writes `Quit Nifro` out in full, so the fragment "Quit " was present and this
test would have passed. It was found by reading, and deleted by hand. A check that could tell those
apart would have to resolve `String(localized:)` interpolations against their arguments, which means
compiling the app. Not worth it for the one case in eight.
*/
@Suite("Nothing is translated that nothing shows")
struct OrphanStringsTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	Every file a string could be displayed from, run together.

	Prose is taken out, as in the other shape tests here, and for a sharper reason: nearly every view in
	this app has a doc comment quoting its own strings, so a comment left in would keep a string looking
	alive for as long as the explanation of it survived — which is exactly the state the deleted menu's
	strings were in. Only comments on a line of their own are cut, never a trailing one, so that a `//`
	inside an address in a string literal cannot swallow the rest of its line and orphan something live.

	The escapes are undone so that a `"\n"` written in Swift matches a real newline in the catalogue.
	*/
	private static func everythingThatCanShowText() throws -> String {
		let readable: Set<String> = ["swift", "plist", "strings", "json"]

		let sources = FileManager.default
			.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL } ?? []

		let extensionSources = FileManager.default
			.enumerator(at: root.appending(path: "ShareExtension"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL } ?? []

		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let ownLine = try Regex("^[\\t ]*//[^\\n]*").anchorsMatchLineEndings()

		return try (sources + extensionSources)
			.filter { readable.contains($0.pathExtension) && $0.lastPathComponent != "Localizable.xcstrings" }
			.map { url in
				let text = try String(contentsOf: url, encoding: .utf8)

				guard url.pathExtension == "swift" else {
					return text
				}

				return text.replacing(block, with: "").replacing(ownLine, with: "")
			}
			.joined()
			.replacing("\\n", with: "\n")
			.replacing("\\\"", with: "\"")
	}

	private static func catalogueKeys() throws -> [String] {
		let data = try Data(contentsOf: root.appending(path: "Nifro/Localizable.xcstrings"))

		// Only the keys are wanted; the values are three levels of nesting this test has no use for.
		let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]

		guard let strings = raw?["strings"] as? [String: Any] else {
			Issue.record("`Localizable.xcstrings` has no `strings` object, so this test is reading nothing.")
			return []
		}

		return strings.keys.sorted()
	}

	/**
	The parts of a key that a source file would have to contain verbatim.

	A key is not searched for whole: `Get %@…` is written `Get \(version)…` in Swift, and an App
	Intents phrase carries `${parameter}`. So it is cut at every format specifier, placeholder,
	inflection marker and newline, and what is left are the runs of plain text. Runs under four
	characters are dropped — "and", "on", "%@" — because a fragment that short matches something
	somewhere in a repository this size whatever its state, which would make the test pass by
	coincidence.
	*/
	private static func literalFragments(of key: String) throws -> [String] {
		let specifier = try Regex("%(?:\\d+\\$)?[@a-zA-Z.0-9]*[@dfs]|%lld|\\$\\{\\w+\\}|\\^\\[|\\]\\(inflect:[^)]*\\)|\\n")

		return key
			.replacing(specifier, with: "\n")
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { $0.count >= 4 }
	}

	/**
	Every string in the catalogue is one something can put on screen.

	Absolute, with no allowlist. A key that no source carries is not a judgement call — either
	something shows it, in which case this finds the text, or nothing does and it is being translated
	into every language the app ever ships for nobody. The fix is never an entry here; it is to delete
	the key, or to notice that the surface which showed it was deleted and the feature went with it.
	*/
	@Test("Every translated string is one the app can still show")
	func noKeyOutlivesItsSurface() throws {
		let sources = try Self.everythingThatCanShowText()
		let keys = try Self.catalogueKeys()

		#expect(keys.count > 200, "Read \(keys.count) keys out of the catalogue, which is too few to be the real one.")
		#expect(sources.contains("String(localized:"), "The source scan found no localized strings at all, so this test is reading nothing.")

		for key in keys {
			let fragments = try Self.literalFragments(of: key)

			// A key made only of specifiers and short words has nothing this test can look for. `%@` is
			// the one in the catalogue today, and `ci.yml` exempts it by name for the same reason.
			guard !fragments.isEmpty else {
				continue
			}

			#expect(
				fragments.contains(where: sources.contains),
				"""
				\"\(key.prefix(60))\" is in the catalogue and written in no source file, so it is \
				translated into every language this app ships and shown in none of them. Delete it — and \
				check what deleted the surface that used to show it, because the feature may have gone \
				with the screen rather than on purpose.
				"""
			)
		}
	}
}
