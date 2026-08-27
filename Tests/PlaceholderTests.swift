import Foundation
import Testing

/**
The guardrail on "if the app rewrites it, the app has to mention it".

`replacePlaceholders` has swapped `[[screenWidth]]` and `[[screenHeight]]` for the size the wallpaper
actually gets on every load since long before this test, and the only place in the repository that
said so was a field description in the site-submission issue form. So the people told about them were
the ones filing a GitHub issue, and never the ones using the app: somebody who did not know wrote the
resolution of the Mac in front of them into the address instead, which is wrong on the next machine
and looks like the website's fault.

The two answers to "which placeholders are there" are a substitution list in `WallpaperScene` and a
sentence in the string catalogue, and until this test nothing required them to agree — the third
shape of defect in `WORKSPACE_GUIDE.md`, in its purest form, where one of the two places is the
documentation.

Shape rather than behaviour, on the guide's own criterion: the proposition is unrunnable, not merely
unreachable. It is a claim about two files agreeing, one of which is a `.xcstrings` catalogue.
`WallpaperScene` needs AppKit, WebKit and a screen and is not in the SwiftPM target next door, the
help text is a literal inside a SwiftUI view, and even with both in hand there would be no function
to call that answers "is this documented".

Matched on the token itself. `[[screenWidth]]` is what somebody types into an address bar — a public
contract with the outside world, not a name this repository could rename — so this cannot go red for
a refactor that changes nothing a user sees.
*/
@Suite("Every placeholder the app substitutes is one it tells you about")
struct PlaceholderTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	Every `[[token]]` written anywhere in the app's Swift, with the prose taken out.

	Comments are stripped for the reason `ScopeTests` gives: the doc comments name these tokens while
	explaining them, and a mention in an explanation is not the app doing anything.
	*/
	private static func placeholders() throws -> Set<String> {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")
		let token = try Regex("\\[\\[[A-Za-z][A-Za-z0-9]*\\]\\]")

		let sources = FileManager.default
			.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "swift" } ?? []

		var found = Set<String>()

		for url in sources {
			let text = try String(contentsOf: url, encoding: .utf8)
				.replacing(block, with: "")
				.replacing(line, with: "")

			for match in text.matches(of: token) {
				found.insert(String(text[match.range]))
			}
		}

		return found
	}

	@Test("Nothing is substituted in silence")
	func everyPlaceholderIsNamedInTheCatalogue() throws {
		let placeholders = try Self.placeholders()

		// The scan itself, first. A regex that has stopped matching would otherwise pass this suite by
		// finding nothing to check, which is the failure it exists to catch.
		#expect(
			!placeholders.isEmpty,
			"No `[[token]]` is written anywhere in Nifro/, so this test is reading nothing."
		)

		let catalogue = try String(
			contentsOf: Self.root.appending(path: "Nifro/Localizable.xcstrings"),
			encoding: .utf8
		)

		for placeholder in placeholders.sorted() {
			#expect(
				catalogue.contains(placeholder),
				"""
				`\(placeholder)` is substituted into addresses and named nowhere the user of the app can \
				read it. Say it in the help text of the URL field, or nobody outside the issue tracker \
				will ever know it exists.
				"""
			)
		}
	}
}
