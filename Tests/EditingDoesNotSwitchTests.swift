import Foundation
import Testing

/**
Opening a website's settings is reading, not switching.

`AddWebsiteScreen` used to call `makeCurrent()` from a `.task` whenever it opened for editing, so
double-clicking a row in the Websites window to look at its settings moved that display's wallpaper
onto the website you had opened. Neither way out put it back. Escape with nothing edited dismissed and
left the new wallpaper up. Revert and "Don't Keep" went through `revert()`, which restores this
website's own fields — the mark among them — but not the sibling's, which `makeCurrent` had cleared
as part of marking this one; the display was then left with no marked website at all and
`WebsitesController`'s repair marked whichever one sorts first on it. Three different wallpapers for
one act of reading.

The reason it was there is real: custom CSS reaches the page on its next load, so writing it against
a wallpaper you cannot see is guesswork. The answer is that the list already has a control for that —
"Set as Current", in each row's context menu and its leading swipe — and a deliberate control beats a
side effect that four exit paths have to remember to undo.

Shape rather than behaviour, for the reason `SwitchedOffTests` sets out at greater length: the SwiftPM
target next door compiles nine files out of `Sites` and `Support` and none of `Screens`, so there is
no `AddWebsiteScreen` here to present and no `Defaults` to read a mark back out of. What is asserted
is the property that keeps the fix true — that this screen does not make a website current — which is
also the exact line somebody would add back while chasing a live CSS preview.
*/
@Suite("Editing a website does not switch the wallpaper")
struct EditingDoesNotSwitchTests {
	private static let sources = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "Nifro")

	/**
	One of the app's Swift files with its prose taken out.

	The comments argue for the absences below by name, so matching against them would find the
	explanation of why the code is right and report it as the code being wrong.
	*/
	private static func source(named name: String) throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		guard
			let url = FileManager.default
				.enumerator(at: sources, includingPropertiesForKeys: nil)?
				.compactMap({ $0 as? URL })
				.first(where: { $0.lastPathComponent == name })
		else {
			Issue.record("\(name) is gone from Nifro/, so this test is reading nothing.")
			return ""
		}

		return try String(contentsOf: url, encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	@Test("The website editor never makes a website current")
	func editorDoesNotMakeCurrent() throws {
		#expect(!(try Self.source(named: "AddWebsiteScreen.swift").contains("makeCurrent")))
	}

	/**
	The other half of the same story.

	`.showEditWebsiteDialog` was posted by the menu that #21 deleted. Its observer opened
	`AppState.currentWebsite`, which is the main display's website whatever screen asked — so wiring it
	back up to the panel would open the laptop's website in front of somebody looking at the monitor.
	The name and the observer are both gone; this fails if either comes back without the per-display
	route that would make it mean something.
	*/
	@Test("Nothing declares or observes an edit-website notification")
	func noEditWebsiteNotification() throws {
		for name in ["Constants.swift", "WebsitesScreen.swift"] {
			#expect(!(try Self.source(named: name).contains("showEditWebsiteDialog")), "\(name) names it again")
		}
	}
}
