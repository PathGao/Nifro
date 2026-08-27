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

- `decodableDefaultToleratesAnAbsentKey` is the other branch, and it is here because the first
  version of this suite left it out. It reasoned that four shipped fields already used
  `@DecodableDefault`, so the wrapper must handle an absent key. It does not, and those four never
  proved it did: a field only meets an absent key in records written *before* it existed, and every
  record on disk was written after all four. `externalLinks` was the first field added since, and it
  emptied the list of every user who had one.

  What makes the wrapper tolerate an absent key is not the wrapper. It is one overload of
  `KeyedDecodingContainer.decode(_:forKey:)` in `Extensions.swift` that routes it to
  `decodeIfPresent`; without that, the synthesised `init(from:)` throws `keyNotFound` and the wrapper
  never runs at all. An earlier cleanup deleted that extension while it happened to have no members.
  So "the property is wrapped" and "an absent key is survivable" are two facts that must agree and
  nothing required them to — this asserts the second one, because the suite already asserted the
  first and that was not enough.
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

		// One tab, not any leading whitespace. A `var` further in is a local inside a computed property,
		// and `var symbols = [String]()` in `badges` was being read as a stored property of `Website` —
		// a field that decodes from nothing, reported as if it were one that does not.
		let declaration = try Regex("^\\t(@[\\w.<>]+\\s+)?(?:(?:private|fileprivate|internal|public)\\s+)?var\\s+(\\w+)")

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

	Two ways to do that and the property has to use one: be `Optional`, or wear a `@DecodableDefault`
	wrapper. Anything else is a field the decoder requires, and requiring a field a stored payload
	cannot have is the whole failure.

	It used to accept a third, `= default` on the declaration, and that was wrong: a synthesised
	`init(from:)` never consults a property's default value, so `var css = ""` throws `keyNotFound`
	exactly like a bare `var css: String`. `defaultValueIsNotADefaultForTheDecoder` below runs that,
	rather than leaving it to be believed. Two shipped fields were relying on it and are converted in
	the same change; they had not failed only because every stored record was written when they
	already existed, which is the same reason the four `@DecodableDefault` fields never proved the
	wrapper worked.
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
			let isWrapped = declaration.contains("@DecodableDefault")

			#expect(
				isOptional || isWrapped,
				"""
				`Website.\(name)` is required by the decoder, so every website stored by a build before \
				it existed fails to decode — and `Defaults` answers a failed decode with an empty list, \
				which is the user's whole collection gone with no way back. Make it optional or wrap it in \
				`@DecodableDefault`; a `= default` on the declaration does not do it.
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

	/**
	The overload that makes `@DecodableDefault` mean what it reads as.

	A shape assertion because the wrapper is in `Extensions.swift`, which the package target does not
	compile, for the same reason `Website` is not compiled here. It is anchored on `decodeIfPresent`
	and on `DecodableDefault.Wrapper` — the standard library's name and the wrapper's own — rather
	than on a helper this repository could rename.
	*/
	@Test("A @DecodableDefault field survives a payload written before it existed")
	func decodableDefaultToleratesAnAbsentKey() throws {
		let source = try String(contentsOf: Self.root.appending(path: "Nifro/Support/Extensions.swift"), encoding: .utf8)

		#expect(
			source.contains("DecodableDefault.Wrapper<T>.Type"),
			"""
			`Extensions.swift` no longer overloads `KeyedDecodingContainer.decode(_:forKey:)` for \
			`DecodableDefault.Wrapper`. Without it every `@DecodableDefault` field throws `keyNotFound` \
			on a payload written before that field existed, and one such record empties the whole \
			website list.
			"""
		)

		#expect(
			source.contains("try decodeIfPresent(type, forKey: key) ?? .init()"),
			"""
			The overload is there but no longer routes to `decodeIfPresent`, which is the whole of what \
			makes an absent key survivable.
			"""
		)
	}

	/**
	The premise the rule above dropped, run rather than argued.

	A property's default value belongs to the memberwise initialiser and nothing else: the synthesised
	`init(from:)` calls `decode(_:forKey:)` for it, exactly as it would for a property with no default
	at all. This is checked here because the rule above used to accept `= default` as a way of
	surviving an absent key, and a rule that accepts an unsafe shape is worse than one that is merely
	incomplete — it reads as though the shape had been considered.
	*/
	@Test("A property's default value is not a default for the decoder")
	func defaultValueIsNotADefaultForTheDecoder() throws {
		struct WithDefault: Decodable {
			var url: String
			var addedLater = "unset"
		}

		#expect(throws: DecodingError.self) {
			try JSONDecoder().decode(WithDefault.self, from: Data(#"{"url":"https://example.com"}"#.utf8))
		}

		// And the same declaration decodes fine when the key is there, so the throw above is about
		// absence and not about the shape being unreadable.
		let present = try JSONDecoder().decode(WithDefault.self, from: Data(#"{"url":"https://example.com","addedLater":"set"}"#.utf8))
		#expect(present.addedLater == "set")
	}
}
