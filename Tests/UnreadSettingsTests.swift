import Foundation
import Testing

/**
The guardrail on "a setting that is written and never read".

`latestKnownVersion` was that for six releases. U1 shipped the daily update check in #18 with the
surface that read the answer in `Menus.swift`; #21 deleted that file and re-homed everything in it
except this, so the app asked GitHub what the newest release was once every twenty-four hours and had
nowhere to put the answer. Nothing failed. The switch worked, the request went out, the key was
written, and the whole feature was missing.

No symbol-graph tool models this, which is why it survived two dead-code passes: the property is
declared, referenced and assigned, so it is reachable by every definition those tools have. What is
absent is a *read*, and absence is not a symbol.

Shape rather than behaviour, and unrunnable rather than unreachable — the distinction
`WORKSPACE_GUIDE.md` draws. "No key is only ever assigned" is a claim about every file in `Nifro/` at
once; there is no function anywhere that could answer it, and the SwiftPM target next door compiles
ten pure files out of `Sites` and `Support`, none of `App` or `Screens`. Running the app cannot answer
it either: a write-only key behaves exactly like a working one.

Matched on the `Defaults` package's own four spellings rather than on identifiers this repository
chose, and the list of keys is parsed from their declarations rather than typed here — so renaming a
key renames both sides of the comparison at once and cannot turn this red on its own.
*/
@Suite("Every setting is read by something")
struct UnreadSettingsTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The app's Swift files with their prose taken out.

	The doc comments name keys while explaining them — this file's own subject is one of them — and a
	mention in a comment is not a reader.
	*/
	private static func sources() throws -> [String] {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try FileManager.default
			.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "swift" }
			.map {
				try String(contentsOf: $0, encoding: .utf8)
					.replacing(block, with: "")
					.replacing(line, with: "")
			} ?? []
	}

	/**
	Every key declared in `Constants.swift`, read off the declarations themselves.

	Parsed rather than listed, so a key added tomorrow is in this test by existing. A list of names
	typed into this file would be the same kind of list that lost the update check its surface.
	*/
	private static func declaredKeys() throws -> [String] {
		let text = try String(contentsOf: root.appending(path: "Nifro/App/Constants.swift"), encoding: .utf8)
		let declaration = try Regex("static let (\\w+) = Key<")

		return text.matches(of: declaration).map { String($0.output[1].substring!) }
	}

	/**
	How often a key is read, and how often it is assigned.

	Four spellings, which is every way this app reaches a stored setting: the subscript, the property
	wrapper, the publisher and `Defaults.Toggle`. All four are the package's public API, so none of
	them moves when something in this repository is renamed. A subscript followed by `=` — with or
	without an index in between, since two of these keys are dictionaries — is the write; every other
	appearance is somebody wanting the value.
	*/
	private static func uses(of key: String, in sources: [String]) throws -> (reads: Int, writes: Int) {
		let subscripted = try Regex("Defaults\\[\\.\(key)\\]")
		let assigned = try Regex("^\\s*(\\[[^\\]]*\\])?\\s*=[^=]")
		let otherReaders = [
			try Regex("@Default\\(\\.\(key)\\)"),
			try Regex("Defaults\\.publisher\\([^)]*\\.\(key)\\b"),
			try Regex("Defaults\\.Toggle\\([^)]*key:\\s*\\.\(key)\\b")
		]

		var reads = 0
		var writes = 0

		for text in sources {
			for match in text.matches(of: subscripted) {
				if text[match.range.upperBound...].firstMatch(of: assigned) != nil {
					writes += 1
				} else {
					reads += 1
				}
			}

			for reader in otherReaders {
				reads += text.matches(of: reader).count
			}
		}

		return (reads, writes)
	}

	/**
	No key is assigned by the app and read by nothing.

	Absolute, with no allowlist: there is no reason to spend a network request, a background task or a
	line of storage on an answer nobody asks for, and every one of the app's keys satisfies this
	today. A key that genuinely has no reader has a different fix — delete it, and the work that
	writes it.

	Only keys the app writes are asked. A key that is read but never written is the opposite shape and
	deliberately allowed: `playlistInterval` is a setting from an older version, kept so that nobody's
	rotation interval disappears on upgrade.
	*/
	@Test("No setting is written and never read")
	func everyWrittenKeyHasAReader() throws {
		let sources = try Self.sources()
		let keys = try Self.declaredKeys()

		#expect(keys.count > 15, "Parsed \(keys.count) keys out of `Constants.swift`, which is too few to be the real list.")

		for key in keys {
			let uses = try Self.uses(of: key, in: sources)

			guard uses.writes > 0 else {
				continue
			}

			#expect(
				uses.reads > 0,
				"""
				`\(key)` is written \(uses.writes) time(s) and read by nothing, so whatever fills it is \
				work the user pays for and never sees. Give it a surface, or delete it along with what \
				writes it.
				"""
			)
		}
	}

	/**
	The update check's answer reaches a screen.

	The test above is the class; this is the instance, named because the class is satisfied by any
	read at all and the point of U1 is *which* read. The panel's footer is where the menu's item went,
	and the comparison against the running version has to happen at the point of drawing — a stored
	"there is an update" boolean would keep saying yes after the update it was about was installed.
	*/
	@Test("The panel's footer is what reads the update check's answer")
	func theUpdateAnswerIsDrawn() throws {
		let panel = try String(contentsOf: Self.root.appending(path: "Nifro/Screens/DisplayPanel.swift"), encoding: .utf8)

		#expect(
			panel.contains("@Default(.latestKnownVersion)"),
			"The panel no longer reads `latestKnownVersion`, so the daily check has nowhere to report again."
		)

		#expect(
			panel.contains("UpdateCheck.isNewer("),
			"The panel takes the stored version at face value. It has to be compared against the running one on every draw."
		)
	}
}
