import Foundation
import Testing

/**
The guardrail on "clearing left something pointing at a website that is gone".

Clearing used to keep the websites, so there was nothing to dangle. It deletes them now, and that
turns a one-line change into the one shape of defect this codebase keeps finding: a per-display key
whose value names a website or a playlist out of a list that no longer has either. Nothing throws,
nothing logs, and the app in front of the person who pressed the button looks exactly right — the
display they are sitting at falls back to the default playlist and shows nothing wrong. The symptom
arrives when a second monitor is plugged in, or when the same Mac is opened at a desk it was last
used at weeks ago, because those are the entries nothing has overwritten since.

**Which keys, taken from `Constants.swift` rather than written out here.** The list of things that
name a website or a playlist is exactly the list of keys declared with one in their value type, and
copying it into this file would make the check as stale as the code it is checking — a key of that
shape added next year would be missed by both, together, silently. Parsed instead, so it is in this
test by existing.

Shape rather than behaviour, on the criterion the suites next door state at length: the SwiftPM
target compiles eleven pure files out of `Sites` and `Support`, none of `Screens`, none of `App`, and
it does not depend on the `Defaults` package at all. There is no `UserDefaults` here to clear and no
settings pane to press. What can be said from here is that the one function which clears is still the
one the button calls, and that it still empties every key of that shape.
*/
@Suite("Clearing leaves nothing pointing at a website that is gone")
struct ClearWebsiteDataTests {
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
	The body of a declaration, from its opening brace to the brace that closes it.

	Counted rather than matched with a regex, for the reason `PlaylistMigrationTests` gives: a pattern
	stopping at the first `}` reads a guard clause as the whole function.
	*/
	private static func body(of declaration: String, in source: String) throws -> String {
		guard
			let start = source.range(of: declaration),
			let open = source[start.upperBound...].firstIndex(of: "{")
		else {
			Issue.record("`\(declaration)` is gone, so this test is reading nothing.")
			return ""
		}

		var depth = 0

		for index in source.indices[open...] {
			if source[index] == "{" {
				depth += 1
			} else if source[index] == "}" {
				depth -= 1

				if depth == 0 {
					return String(source[open...index])
				}
			}
		}

		Issue.record("`\(declaration)` has no closing brace, so this test is reading nothing.")
		return ""
	}

	/**
	Every preference whose stored value names a website or a playlist.

	Matched on the value type and not on the key's name, because the name is what a person chooses and
	the type is what makes it dangle. `currentWebsites` and `currentPlaylists` are the two today; a
	third of the same shape is caught by being declared, which is the only way this check can outlive
	the person who wrote it.
	*/
	private static func keysNamingContent() throws -> [String] {
		let pattern = try Regex("Key<\\[String: (?:Website|Playlist)\\.ID\\]>\\(\"(\\w+)\"")

		return try source("Nifro/App/Constants.swift")
			.matches(of: pattern)
			.map { String($0[1].substring ?? "") }
	}

	@Test("The keys that name a website or a playlist are found, so the check below is not comparing against nothing")
	func theKeysAreFound() throws {
		let names = try Self.keysNamingContent()

		#expect(
			names.count >= 2,
			"Only found \(names.count) keys naming a website or a playlist in Constants.swift; the parser has probably stopped matching"
		)
		#expect(names.contains("currentWebsites"))
		#expect(names.contains("currentPlaylists"))
	}

	/**
	Emptying the list and emptying what points into it happen in one function, and it is the one the
	button calls.

	Two assertions because there are two ways to break this and they look nothing alike. The list can
	be emptied somewhere the keys are not — a `Defaults[.playlists] = []` written into the settings
	pane, which compiles and clears and leaves both dictionaries full. Or the function can stay
	correct and stop being reached, which is the same outcome by a quieter route.
	*/
	@Test("Clearing empties every key that names a website or a playlist, in the function the button calls")
	func clearingEmptiesEveryKeyNamingContent() throws {
		let controller = try Self.source("Nifro/Sites/WebsitesController.swift")
		let clearing = try Self.body(of: "func removeEverything()", in: controller)

		#expect(
			clearing.contains("Defaults[.playlists] = []"),
			"`removeEverything` no longer empties the playlists, which is the whole of where a website is stored."
		)

		for name in try Self.keysNamingContent() {
			#expect(
				clearing.contains("Defaults[.\(name)] = [:]"),
				"""
				`removeEverything` drops the websites without emptying “\(name)”, so a display is left \
				pointing at something that no longer exists. It looks right on the display in front of \
				whoever pressed the button and wrong on the next one plugged in.
				"""
			)
		}

		let pane = try Self.source("Nifro/Screens/SettingsScreen.swift")

		#expect(
			try Self.body(of: "private func clear()", in: pane).contains("removeEverything()"),
			"Clearing no longer goes through `removeEverything`, so whatever it empties, it is not that."
		)
	}
}
