import Foundation
import Testing

/**
The guardrail on adding a field to `Website`.

`Website` is `Codable` and the whole list is persisted through `Defaults` as one JSON array. A field
added to it without a fallback makes `init(from:)` throw on every payload written by an older build,
and `Defaults` answers a failed decode with the key's default — an empty array. The user opens the app
after updating and every website they ever added is gone, with the file on disk still holding them and
nothing in the interface able to reach it. There is no undo for that and no error message; it looks
like the app forgot.

It is also the easiest mistake to make here, because it compiles, and because the new build writes the
new shape immediately — so the first launch on the developer's own machine, where the payload was
written by the same build, passes.

**`Website` cannot be exercised from here, and that is worth saying plainly rather than working
around.** `Package.swift` compiles ten pure files out of `Sites` and `Support`; `Website.swift` is not
one of them and cannot be, since it reaches `Defaults`, `Display`, `WebsitesController` and the
`DecodableDefault` wrappers in `Extensions.swift`. That is unreachable rather than unrunnable —
`WORKSPACE_GUIDE.md`'s word for a missing seam — and the seam is not one this change is entitled to
cut: it means moving the model out from under `Defaults`, which is a rewrite of how the app stores
everything.

So the proposition is split in two, and both halves are here:

- `everyStoredPropertyDecodesWithoutItsKey` is the claim about `Website`, asserted on the shape of its
  source. It is a claim about every property at once, including ones nobody has written yet, which is
  the part a decode test of the current struct could not make.
- `optionalMeansTheKeyMayBeAbsent` is the language rule one branch of that claim rests on — that a
  synthesised `init(from:)` calls `decodeIfPresent` for an `Optional` and `decode` for everything
  else. It runs, and it is checked in both directions, because the direction that matters is the
  failing one: a required key absent from stored data is the empty list.

The `@DecodableDefault` branch has no equivalent here for the same reason `Website` does not — the
wrapper lives in `Extensions.swift`, which the package target does not compile. Four shipped fields
already depend on it, so it is not new ground this change is breaking.
*/
@Suite("A website written by an older build still decodes")
struct WebsiteMigrationTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func source(_ path: String) throws -> String {
		let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return text.replacing(block, with: "").replacing(line, with: "")
	}

	/**
	The fields that were in the first release.

	Every payload ever written by this app has them, so a decoder that requires them cannot fail on
	stored data — which is the only reason they are allowed to be non-optional with no default. They
	are named rather than counted so that a fifth has to be argued for here before it can be added:
	the argument for any new one is "no stored payload can lack it", and for a field added after
	release that argument is never available.
	*/
	private static let fieldsFromTheFirstRelease = ["id", "isCurrent", "url", "usePrintStyles"]

	/**
	The stored properties of `Website`, in declaration order.

	Computed properties are skipped by the brace on their own line, which is what makes them computed.
	*/
	private static func storedProperties() throws -> [(name: String, declaration: String)] {
		let text = try source("Nifro/Sites/Website.swift")

		guard
			let start = text.range(of: "struct Website"),
			let open = text[start.upperBound...].firstIndex(of: "{")
		else {
			Issue.record("`struct Website` is no longer written that way, so this test is reading nothing.")
			return []
		}

		var depth = 0
		var end = text.endIndex

		for index in text.indices[open...] {
			switch text[index] {
			case "{":
				depth += 1
			case "}":
				depth -= 1

				if depth == 0 {
					end = index
				}
			default:
				break
			}

			if depth == 0 {
				break
			}
		}

		let declaration = try Regex("^\\s*(@[\\w.<>]+\\s+)?var\\s+(\\w+)")

		return text[open..<end]
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map(String.init)
			.filter { !$0.contains("{") }
			.compactMap { line in
				guard let match = line.firstMatch(of: declaration) else {
					return nil
				}

				return (String(match.output[2].substring!), line)
			}
	}

	/**
	Every stored property survives a payload that does not mention it.

	Three ways to do that and the property has to use one: be `Optional`, carry a `= default`, or wear
	a `@DecodableDefault` wrapper. Anything else is a field the decoder requires, and requiring a
	field a stored payload cannot have is the whole failure.
	*/
	@Test("No field can be added to a website that old data would fail to decode")
	func everyStoredPropertyDecodesWithoutItsKey() throws {
		let properties = try Self.storedProperties()

		#expect(properties.count > 10, "Parsed \(properties.count) stored properties out of `Website`, which is too few to be the real struct.")

		for (name, declaration) in properties {
			guard !Self.fieldsFromTheFirstRelease.contains(name) else {
				continue
			}

			let isOptional = declaration.contains("?")
			let hasDefault = declaration.contains("=")
			let isWrapped = declaration.contains("@DecodableDefault")

			#expect(
				isOptional || hasDefault || isWrapped,
				"""
				`Website.\(name)` is required by the decoder, so every website stored by a build before \
				it existed fails to decode — and `Defaults` answers a failed decode with an empty list, \
				which is the user's whole collection gone with no way back. Make it optional, give it a \
				default, or wrap it in `@DecodableDefault`.
				"""
			)
		}
	}

	/**
	`Optional` is what makes a key allowed to be absent, and nothing else is.

	The premise the test above rests on, run rather than believed. The failing half matters as much as
	the passing one: a non-optional property with no default throws `keyNotFound`, which is exactly
	what would reach the user as an empty website list.
	*/
	@Test("A synthesised decoder fills in a missing optional and refuses a missing requirement")
	func optionalMeansTheKeyMayBeAbsent() throws {
		struct WithOptional: Codable {
			var url: String
			var addedLater: Double?
		}

		struct WithRequirement: Codable {
			var url: String
			var addedLater: Double
		}

		// A payload written before either field existed.
		let stored = Data(#"{"url":"https://example.com"}"#.utf8)

		let decoded = try JSONDecoder().decode(WithOptional.self, from: stored)

		#expect(decoded.addedLater == nil)
		#expect(decoded.url == "https://example.com")

		#expect(throws: DecodingError.self) {
			try JSONDecoder().decode(WithRequirement.self, from: stored)
		}
	}

	/**
	The per-website answer falls back to the app-wide switch rather than replacing it.

	The migration is not only the decode. The state a website decodes into has to keep meaning what
	every existing website already means — "whatever Settings says" — or a shipped setting people have
	already turned on stops applying to every website that has not been edited since.
	*/
	@Test("A website with no answer of its own follows Settings")
	func theGlobalSwitchIsStillTheDefault() throws {
		let website = try Self.source("Nifro/Sites/Website.swift")

		#expect(
			website.contains("static let defaultValue = followSettings"),
			"`ExternalLinks` no longer defaults to following Settings, so every website stored before this setting existed changes what it does on upgrade."
		)

		#expect(
			website.contains("Defaults[.openExternalLinksInBrowser]"),
			"Nothing falls back to the app-wide switch any more, so everybody who set it loses it."
		)

		let webView = try Self.source("Nifro/Wallpaper/WebViewController.swift")

		#expect(
			webView.contains("opensExternalLinksInBrowser"),
			"The navigation guard reads the app-wide switch directly again, so a website's own answer is never asked for."
		)
	}
}
