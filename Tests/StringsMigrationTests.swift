import Foundation
import Testing
@testable import NifroLogic

/**
The guardrail on "the strings still say what the catalogue says".

`Strings.generated.swift` is 269 sentences in two languages, written by a script out of
`Localizable.xcstrings`. Moving them into Swift buys a compile error for a *missing* field — which is
what it replaces the CI completeness gate with — and buys nothing at all against the failure that
actually matters here: a field carrying the wrong sentence. That compiles, it ships, and the only
sign is somebody reading the wrong words on screen.

So this holds the generated values against the catalogue rather than against the generator. The
catalogue is the input, committed and unchanged by this work, so a script that mangles a value on the
way out has nothing to agree with. The `%%` in `"%@× at %lld%%, %lld%%"` is the case that proves it
is worth having: printf writes an escaped per cent that way and Swift interpolation does not, and the
first version of the generator copied it through, which would have shipped "40%%" on a settings row.

`catalogueKeys` comes from the generator rather than being rebuilt here on purpose. Deriving the
names again in Swift would be a second implementation of the same rules, agreeing with the first by
construction and proving nothing about the text.
*/
@Suite("Generated strings still say what the catalogue says")
struct StringsMigrationTests {
	/**
	The catalogue, flattened to key → language → text.

	Parsed on each call rather than held in a `static let`: `[String: Any]` is not `Sendable`, and the
	honest fix is a shape that is rather than an annotation promising it. 269 entries twice is nothing.

	English is the development language, so a key with no `en` unit *is* its English. A key that has
	one is not always its key, because Xcode writes positional forms (`%1$@`) into the unit while the
	key keeps the plain ones — reading the key would compare the wrong two things.
	*/
	private static func catalogue() throws -> [String: [String: String]] {
		let url = URL(filePath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Nifro/Localizable.xcstrings")

		let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
		let entries = json?["strings"] as? [String: Any] ?? [:]

		var flattened: [String: [String: String]] = [:]

		for (key, entry) in entries {
			guard let entry = entry as? [String: Any] else {
				continue
			}

			// An entry with nothing in it at all is residue Xcode left behind, and the generator skips
			// it for the same reason. Kept as an empty dictionary so `nothingWasDropped` can tell the
			// difference between "not a string" and "a string with no field".
			guard !entry.isEmpty else {
				continue
			}

			var byLanguage: [String: String] = ["en": key]

			for (language, localization) in (entry["localizations"] as? [String: Any] ?? [:]) {
				if let value = ((localization as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String {
					byLanguage[language] = value
				}
			}

			flattened[key] = byLanguage
		}

		return flattened
	}

	/**
	Every field, in both languages, against the catalogue entry it was made from.

	Compared as data. The obvious way was `Mirror` over `Strings.english`, and it segfaults: thirteen
	of these fields are closures, and casting a closure back out of an `Any` is not something the
	runtime does reliably. So the generator writes the same text a second time as a plain dictionary,
	with each argument as a marker, and that is what is checked here.

	The catalogue is the input to the generator and is untouched by this work, so a script that mangles
	a value on the way out has nothing to agree with. That is the failure this exists for: the first
	version copied printf's `%%` straight through, and Swift interpolation has no such escape, so a
	settings row would have shipped reading "40%%".

	**What it does not cover**, stated rather than left to be discovered: the dictionary and the closure
	bodies are two outputs of one script, so a disagreement *between them* would pass here. That is
	what `theHardestFormatStringIsCalledForReal` is for.
	*/
	@Test("Every generated field carries its catalogue text", arguments: ["en", "zh-Hans"])
	func fieldsMatchTheCatalogue(language: String) throws {
		let entries = try Self.catalogue()
		let rendered = language == "en" ? Strings.renderedEnglish : Strings.renderedSimplifiedchinese

		#expect(rendered.count == Strings.catalogueKeys.count)
		#expect(rendered.count > 250, "Only \(rendered.count) fields; the generator is writing almost nothing")

		for (field, text) in rendered {
			let key = try #require(Strings.catalogueKeys[field], "`\(field)` has no catalogue key")

			// A string the catalogue has not translated falls back to the English, which is what the
			// generator wrote and what the app used to show.
			let source = entries[key]?[language] ?? entries[key]?["en"] ?? key

			#expect(text == Self.markered(source), "`\(field)` in \(language)")
		}
	}

	/**
	The printf spelling, as the generator should have rendered it.

	Two rules, written out again in a second language on purpose: an escaped per cent becomes one, and
	a specifier becomes the marker for its argument — the position it names, or the next one. The
	generator and this are two statements of one rule and they only agree if both are right.
	*/
	private static func markered(_ value: String) -> String {
		let markers = ["‹0›", "‹1›", "‹2›", "‹3›"]
		var out = ""
		var index = 0
		var rest = Substring(value)

		while let hit = rest.firstIndex(of: "%") {
			out += rest[..<hit]
			var tail = rest[rest.index(after: hit)...]

			guard tail.first != "%" else {
				out += "%"
				rest = tail.dropFirst()
				continue
			}

			let digits = tail.prefix { $0.isNumber }
			var position: Int?

			if !digits.isEmpty, tail.dropFirst(digits.count).first == "$" {
				position = Int(digits).map { $0 - 1 }
				tail = tail.dropFirst(digits.count + 1)
			}

			if tail.hasPrefix("ll") {
				tail = tail.dropFirst(2)
			}

			out += markers[position ?? index]
			index += 1
			rest = tail.dropFirst()
		}

		return out + rest
	}

	/**
	One format string called for real, chosen because it is the worst of them.

	`"%1$@× at %2$lld%%, %3$lld%%"` is the only key that has positional specifiers, a `%%`, a width
	modifier and three arguments at once, and its Chinese reorders nothing but reads differently around
	them. If the closure bodies and the dictionary above ever disagree, this is where it shows.

	One by hand rather than all thirteen: the list would be the hand-maintained mapping this whole
	scheme exists to avoid, and the other twelve take one `%@` each.
	*/
	@Test("The hardest format string is called for real, not read out of a table")
	func theHardestFormatStringIsCalledForReal() {
		#expect(Strings.english.zoomSummary("3", "40", "60") == "3× at 40%, 60%")
		#expect(Strings.simplifiedChinese.zoomSummary("3", "40", "60") == "3× 位于 40%, 60%")

		// And that the table says the same thing the closure just did.
		#expect(Strings.renderedEnglish["zoomSummary"] == "‹0›× at ‹1›%, ‹2›%")
	}

	@Test("Every catalogue entry that has anything in it became a field")
	func nothingWasDropped() throws {
		let mapped = Set(Strings.catalogueKeys.values)

		for key in try Self.catalogue().keys {
			// The membership is computed before the expectation rather than inside it. Written as
			// `mapped.contains(key)` the failure message inlines all 269 keys, and a failure nobody can
			// read is most of the way to a failure nobody acts on.
			let found = mapped.contains(key)
			#expect(found, "no field for “\(key.prefix(60))”")
		}

		#expect(mapped.count == Strings.catalogueKeys.count, "two fields share one catalogue key")
	}

	private static func specifierCount(in key: String) -> Int {
		var count = 0
		var rest = Substring(key)

		while let range = rest.range(of: "%") {
			var tail = rest[range.upperBound...]

			if tail.first == "%" {
				rest = tail.dropFirst()
				continue
			}

			let digits = tail.prefix { $0.isNumber }
			if !digits.isEmpty, tail.dropFirst(digits.count).first == "$" {
				tail = tail.dropFirst(digits.count + 1)
			}

			count += 1
			rest = tail.dropFirst()
		}

		return count
	}

	private static func call(_ closure: Any, with arguments: [String]) -> String? {
		switch arguments.count {
		case 1: return (closure as? @Sendable (String) -> String)?(arguments[0])
		case 2: return (closure as? @Sendable (String, String) -> String)?(arguments[0], arguments[1])
		case 3: return (closure as? @Sendable (String, String, String) -> String)?(arguments[0], arguments[1], arguments[2])
		default: return nil
		}
	}
}
