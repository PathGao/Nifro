import Foundation
import Testing

/**
The guardrail on the script that carries custom CSS into the page.

The CSS makes a trip through two languages: Swift percent-encodes it so it can sit inside a
JavaScript string literal without escaping quotes, backslashes or newlines, and the page decodes it
again. Nothing in either language forces the two halves to agree, and when they disagreed the app
did not fail — it drew the wrong characters. Percent-encoding writes UTF-8 bytes; `unescape` reads
each `%XX` as one Latin-1 character, because its partner is `escape` and not this encoder. ASCII is
the overlap where the two conventions agree, and everything outside it was corrupted. Both
stylesheets the app itself injects, inverted colours and the standalone image centring, are pure
ASCII, so nothing it ships could show it either.

Shape and Foundation rather than behaviour, for the reason `LoadingIndicatorTests` spells out: the
SwiftPM target next door compiles ten pure files out of `Sites` and `Support`, and `Extensions.swift`
is not one of them — it is `WebKit`, `SwiftUI` and `Defaults` from end to end. The decoding half
happens inside WebKit and needs a web view and a page. So the encoder is exercised for real and the
decoder is asserted by name, which between them is the contract that was broken.
*/
@Suite("Custom CSS survives the trip into the page")
struct CSSInjectionTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func extensions() throws -> String {
		try String(contentsOf: root.appending(path: "Nifro/Support/Extensions.swift"), encoding: .utf8)
	}

	/**
	The JavaScript that is injected, without the Swift around it.

	Both the Swift prose around the script and the script's own comments argue for the very tokens the
	assertions look for, and either would pass a test on the code's behalf. So the search is bounded by
	the string literal, and the JavaScript comments inside it are struck out.
	*/
	private static func injectedScript() throws -> String {
		let source = try extensions()
		let delimiter = "\"\"\""

		guard
			let marker = source.range(of: "nifroInjected"),
			let start = source.range(of: delimiter, options: .backwards, range: source.startIndex..<marker.lowerBound),
			let end = source.range(of: delimiter, range: marker.upperBound..<source.endIndex)
		else {
			Issue.record("The CSS injection script is no longer a string literal containing `nifroInjected`.")
			return ""
		}

		return String(source[start.upperBound..<end.lowerBound])
			.replacing(try Regex("//[^\\n]*"), with: "")
	}

	/**
	What `unescape` made of the encoding: every `%XX` read as one Latin-1 character.

	Here so that the samples below cannot be vacuous. A round trip both decoders agree on says nothing
	about which one is installed, and on ASCII they do agree.
	*/
	private static func asLatin1(_ encoded: String) -> String {
		var result = ""
		var rest = Substring(encoded)

		while let escape = rest.firstIndex(of: "%") {
			let digits = rest.index(escape, offsetBy: 1)
			let next = rest.index(escape, offsetBy: 3)

			guard
				next <= rest.endIndex,
				let byte = UInt8(rest[digits..<next], radix: 16)
			else {
				break
			}

			result += rest[..<escape]
			result.append(Character(UnicodeScalar(byte)))
			rest = rest[next...]
		}

		return result + rest
	}

	/**
	The page decodes what Swift encoded.

	Both halves, because either one moving alone breaks it: percent-encoding read as Latin-1 loses
	every non-ASCII character, and a decoder with no encoder in front of it is handed CSS whose own
	quotes end the JavaScript string literal it is sitting in.
	*/
	@Test("The encoder and the decoder are the same encoding")
	func theTwoHalvesAgree() throws {
		#expect(
			try Self.extensions().contains("addingPercentEncoding(withAllowedCharacters: .letters)"),
			"The CSS is no longer percent-encoded, but the page still decodes it as if it were."
		)

		let script = try Self.injectedScript()

		#expect(
			script.contains("decodeURIComponent("),
			"The injected script no longer decodes the CSS as UTF-8."
		)

		#expect(
			!script.contains("unescape("),
			"""
			`unescape` is the inverse of `escape`, not of percent-encoding: it reads `%XX` as Latin-1, \
			so every non-ASCII character in custom CSS reaches the page as mojibake. Decode with \
			`decodeURIComponent`.
			"""
		)
	}

	/**
	Every width of UTF-8 makes the trip, asserted by width rather than by language.

	`addingPercentEncoding` does not spare non-ASCII letters whatever the allowed set says — Foundation
	encodes every byte outside ASCII — so the old decoder broke `café`, `思源黑体`, `Москва`, `나눔고딕`,
	`ไทย`, `الخط`, `Ελληνικά` and `Tiếng Việt` alike, and naming any of them here would make the fix
	look like it was about one script. A list of languages is arbitrary and never finished. UTF-8 has
	four widths, and each one fails a byte-oriented decoder differently.
	*/
	@Test("Every UTF-8 width survives the encoding")
	func everyByteWidthSurvives() throws {
		let samples = [
			(
				"body { color: red }",
				"one byte: ASCII, the overlap where both decoders agree"
			),
			(
				"a::after { content: \"é\" }",
				"two bytes, from the U+0080–U+00FF range `unescape` exists for, where a Latin-1 read returns plausible characters rather than obviously broken ones"
			),
			(
				"a::after { content: \"。\" }",
				"three bytes: CJK punctuation, and `content:` is where users meet this"
			),
			(
				"h1 { font-family: \"思源黑体\" }",
				"three bytes: an ideograph in a font name"
			),
			(
				"a::after { content: \"🌙\" }",
				"four bytes: the astral plane, a surrogate pair once it is in JavaScript"
			)
		]

		for (css, width) in samples {
			guard let encoded = css.addingPercentEncoding(withAllowedCharacters: .letters) else {
				Issue.record("\(width) cannot be percent-encoded at all.")
				continue
			}

			#expect(
				encoded.allSatisfy { $0.isASCII && !"'\\\n".contains($0) },
				"\(width): the encoding is not safe to put inside a JavaScript string literal."
			)

			#expect(
				encoded.removingPercentEncoding == css,
				"\(width): does not survive being read back as UTF-8, which is what `decodeURIComponent` does."
			)

			// The sample has to be able to tell the two decoders apart, or it is guarding nothing. On
			// ASCII nothing can, which is the point of having one ASCII sample and four others.
			#expect(
				(Self.asLatin1(encoded) == css) == css.allSatisfy(\.isASCII),
				"\(width): a Latin-1 read of this is no longer distinguishable from a UTF-8 one."
			)
		}
	}

	/**
	The observer watches the two parents the style can go missing from, and not the whole page.

	It exists because a framework can replace `documentElement` or clear `head` out from under a style
	element injected before the page had finished building. That is a question about two nodes, and it
	was being asked with `subtree: true` on `document`: every insertion and removal anywhere on the
	page, one observer per stylesheet injected, one set per frame, none of them ever disconnected. The
	comment above the script had described the cheap version the whole time, which is why this is
	asserted rather than written down — prose cannot fail when the code stops matching it.

	The style element only ever goes into `head ?? documentElement`, so there is no deeper subtree for
	it to be moved out of.
	*/
	@Test("The observer watches two nodes, not the whole page")
	func theObserverDoesNotWatchTheWholePage() throws {
		let script = try Self.injectedScript()

		#expect(
			!script.contains("subtree"),
			"""
			The style observer is watching the whole document again, so every node inserted or removed \
			anywhere on the page wakes it, for the lifetime of the wallpaper. The style only ever goes \
			into `head ?? documentElement`.
			"""
		)

		for node in ["observer.observe(document,", "observer.observe(document.documentElement,"] {
			#expect(
				script.contains(node),
				"`\(node)` is gone, so a page that replaces that node takes the user's CSS with it."
			)
		}
	}
}
