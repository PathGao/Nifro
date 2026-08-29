import Foundation
import Testing

/**
Disable is a press, so it is written down.

`Constants.swift` sorts everything the app knows by one question — can this be asked again? — and
the app-wide Disable cannot be: the lock screen and the battery rule answer themselves the moment
anybody wants to know, and this one happened in somebody's hand. It was a plain property all the
same, so it died with the process. A Mac switched off as a whole came back on by itself the next
morning, while a single display switched off from the panel stayed off, because `disabledDisplays`
was on disk. The two halves of "off" disagreed about whether they were worth keeping.

Three assertions, one per piece of the path: the key exists, the property is that key rather than a
value beside it, and a change to the key is what recomputes `isEnabled`. The third is what makes
Restore Defaults switch the app back on — the wipe removes keys one at a time, so it arrives the
same way a press does — and it is the piece a `didSet` on the property would have missed.

Shape rather than behaviour, for the reason `CropLifetimeTests` gives: the SwiftPM target compiles
nothing from `App`, and this needs the real defaults suite. What was checked by hand is in the pull
request.
*/
@Suite("The app-wide Disable survives a quit")
struct DisableSurvivesAQuitTests {
	private static func source(named name: String) throws -> String {
		let file = URL(filePath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Nifro/App/\(name)")

		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(contentsOf: file, encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	@Test("The press has a key of its own")
	func thePressHasAKey() throws {
		#expect(
			try Self.source(named: "Constants.swift")
				.contains(try Regex("static let isManuallyDisabled = Key<Bool>")),
			"The app-wide Disable has no storage again, so it lasts until the next quit while the per-display one does not."
		)
	}

	@Test("The property is the key, not a copy of it")
	func thePropertyIsTheKey() throws {
		let state = try Self.source(named: "AppState.swift")
		let declaration = try #require(state.components(separatedBy: "var isManuallyDisabled").last)
		let property = String(declaration.prefix(200))

		#expect(
			property.contains("Defaults[.isManuallyDisabled]"),
			"`isManuallyDisabled` holds a value of its own beside the stored one, which is two answers to one question and only one of them survives a quit."
		)
	}

	@Test("A change to the key is what recomputes the switch")
	func theKeyRecomputesTheSwitch() throws {
		let events = try Self.source(named: "Events.swift")

		#expect(
			events.contains("Defaults.publisher(.isManuallyDisabled)"),
			"Nothing watches the stored Disable, so Restore Defaults empties the key and leaves the running app switched off with nothing on disk saying so."
		)

		let subscription = try #require(events.components(separatedBy: "Defaults.publisher(.isManuallyDisabled)").last)

		#expect(
			String(subscription.prefix(200)).contains("setEnabledStatus()"),
			"The stored Disable is watched but does not reach `isEnabled`, so pressing it changes nothing until something else recomputes."
		)
	}
}
