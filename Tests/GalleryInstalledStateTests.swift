import Foundation
import Testing

/**
"Added" is a reading of the website list, not a memory of this window.

The gallery drew that word from a `@State` set of entry ids, and `@State` is made afresh every time
the window opens. So the set was a record of what had been pressed in *this* sitting: close the
gallery, open it again, and a site already in the list was offered as "Add". Pressing it installed a
second copy, because `WebsitesController.add` appends and nothing under it looks for a website that
is already there — the same page twice, with the same settings, and nothing on either row saying why.

The fix is not a duplicate check in `add`. Adding one website twice is something a user may mean —
two records of the same page, framed differently, on two displays — and the button is what claims the
site is already installed, so the claim is what has to be true. It is derived from the stored
websites, which is the only place that answer lives.

Shape rather than behaviour, for the reason `CropLifetimeTests` gives: the SwiftPM target compiles
nothing from `Screens`, and this needs SwiftUI and the stored defaults. What was checked by hand is
in the pull request.
*/
@Suite("The gallery asks the list what is installed")
struct GalleryInstalledStateTests {
	private static let screen = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "Nifro/Screens/SiteGalleryScreen.swift")

	/**
	The file with its prose taken out, which here argues for the very thing being looked for.
	*/
	private static func source() throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(contentsOf: screen, encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	@Test("Nothing in the gallery remembers what was pressed")
	func nothingRemembersPresses() throws {
		let source = try Self.source()

		// Any per-window memory of what has been added is the defect, whatever it is called. The three
		// `@State` properties that remain are about the query, the tag and the fetched catalogue —
		// none of them is a claim about the user's list.
		#expect(
			!source.contains(try Regex("@State[^\\n]*added")),
			"The gallery is keeping its own record of what was added again, which is empty on the next opening and offers an installed site as \"Add\"."
		)
	}

	@Test("The button's word comes from the stored websites")
	func theWordComesFromStorage() throws {
		let source = try Self.source()

		#expect(
			source.contains("@Default(.playlists)"),
			"The gallery no longer watches the website list, so the row it just added keeps saying \"Add\" until the window is reopened."
		)

		let installed = try #require(source.components(separatedBy: "private var installedAddresses").last)

		#expect(
			installed.contains("playlists"),
			"`installedAddresses` works the answer out from something other than the stored list."
		)

		// The button and the disabled state read one answer. Two readings is how the word and the
		// press came apart in the first place.
		#expect(
			source.contains("Button(isInstalled ? \"Added\" : \"Add\")"),
			"The row's label is decided by something other than `isInstalled`."
		)
		#expect(
			source.contains(".disabled(isInstalled)"),
			"The row can be pressed on a state its own label calls \"Added\"."
		)
	}
}
