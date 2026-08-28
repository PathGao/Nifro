import Foundation
import Testing

/**
The guardrail on "Restore Everything".

What it is guarding against is a change that compiles, passes review and breaks nothing until
somebody counts. A restore that resets a written-out list of preferences works perfectly on the day
it is written; it starts lying the first time a preference is added by somebody who never saw the
list. Nothing goes red, the app keeps working, and the only symptom is that one setting quietly
survives a restore.

So the check is on the shape of `RestoreDefaults.swift`, not on its behaviour. That is deliberate,
and it is worth being plain about why a behavioural test is not on offer here: the SwiftPM target
next door compiles seven files out of `Support`, none of the `Defaults` machinery and none of
`App/Constants.swift`, and it does not depend on the `Defaults` package at all. There is no way from
here to ask the real reset which keys it covers. There is also nothing to ask — `Defaults.removeAll()`
covers the domain, so it has no coverage set that could disagree with the declared keys.

That leaves two things worth asserting, and they are the two that actually fail. The first is that
the reset is still a whole-domain wipe and has not been turned into an enumeration. The moment
somebody "tidies" it into `Defaults.reset(.opacity, .websites, …)`, these tests go red and say why —
which is before the list has had a chance to rot rather than months after.

The second arrived with the one exception the wipe now has. `RestoreDefaults` lifts `AppleLanguages`
out and puts it back, because that key is read as the process starts and no running app can be shown
a new value for it. One exception is defensible; a growing list of them is the very key list the wipe
exists to avoid, and it would rot the same way — silently, in whichever direction the next person
guessed. So the exception is asserted rather than trusted: exactly one hand-written key name in the
file, put back after the wipe rather than before it, with a comment attached saying why it is there.

The key list is parsed out of `Constants.swift` on every run rather than copied here, so it is the
declaration itself that is compared against, and a key added tomorrow is in this check by existing.
*/
@Suite("Restore Everything cannot miss a preference")
struct RestoreDefaultsTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func source(_ path: String) throws -> String {
		try String(contentsOf: root.appending(path: path), encoding: .utf8)
	}

	/**
	The same file with its prose taken out.

	Every one of these files argues for itself at length, and the arguments name the very things the
	assertions look for — "a list of keys", "`Defaults.reset`". Matching against the comments would
	fail on the explanation of why the code is right.
	*/
	private static func stripComments(_ source: String) throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")
		return source.replacing(block, with: "").replacing(line, with: "")
	}

	private static func declaredKeyNames() throws -> [String] {
		let pattern = try Regex("\\bKey<.+\\(\"(\\w+)\"")

		return try source("Nifro/App/Constants.swift")
			.matches(of: pattern)
			.map { String($0[1].substring ?? "") }
	}

	@Test("Every declared preference exists, so the checks below are not comparing against nothing")
	func theKeysAreFound() throws {
		let names = try Self.declaredKeyNames()

		// Twenty-three at the time of writing. The floor is here so a broken parser — a rename, a
		// reformat, a move to another file — fails loudly instead of finding no keys and passing every
		// "no key is named" assertion for free.
		#expect(names.count >= 20, "Only found \(names.count) Defaults keys in Constants.swift; the parser has probably stopped matching")
		#expect(names.contains("websites"))
		#expect(names.contains("hasInstalledFeaturedWebsites"))
	}

	@Test("The reset wipes the whole domain rather than a list of keys")
	func theResetIsAWipe() throws {
		let code = try Self.stripComments(Self.source("Nifro/App/RestoreDefaults.swift"))

		#expect(code.contains("Defaults.removeAll()"), "Restore no longer wipes the domain")
		#expect(!code.contains("Defaults.reset"), "Restore now resets named keys, which is a list that will rot")
		#expect(!code.contains("Defaults["), "Restore now reaches for individual keys")
	}

	@Test("No preference is singled out, so none can be left out")
	func noKeyIsNamed() throws {
		let code = try Self.stripComments(Self.source("Nifro/App/RestoreDefaults.swift"))

		for name in try Self.declaredKeyNames() {
			#expect(!code.contains(".\(name)"), "Restore names the “\(name)” preference. Naming one means naming all of them, and the next one added will be missed.")
		}
	}

	@Test("Every keyboard shortcut is reset through the table rather than one at a time")
	func shortcutsResetThroughTheTable() throws {
		let code = try Self.stripComments(Self.source("Nifro/App/RestoreDefaults.swift"))

		#expect(code.contains("KeyboardShortcuts.reset(Shortcut.allNames)"), "Shortcuts are no longer reset through the CaseIterable table")

		let cases = try Self.stripComments(Self.source("Nifro/App/Shortcuts.swift"))
			// The optional tail is an explicit raw value. `browsingMode` carries one — its stored key is
			// the older `toggleBrowsingMode` — and without this the parser silently skipped it, which is
			// the shortcut this test would then let Restore name one at a time.
			.matches(of: Regex("^\\tcase (\\w+)(?: = \"\\w+\")?$", as: AnyRegexOutput.self).anchorsMatchLineEndings())
			.map { String($0[1].substring ?? "") }

		#expect(cases.count >= 8, "Only found \(cases.count) shortcuts in Shortcuts.swift; the parser has probably stopped matching")

		for name in cases {
			#expect(!code.contains(".\(name)"), "Restore names the “\(name)” shortcut instead of resetting the whole table")
		}
	}

	/**
	The exception, and the three ways it could stop being defensible.

	It could multiply — one preserved key is an exception, three are a keep-list, and a keep-list is
	what `Defaults.removeAll()` was chosen to avoid. It could be put back in the wrong place, before
	the wipe rather than after, which deletes it again and leaves nothing to see until somebody who
	reads the other language restores their settings. Or it could lose the comment that says why it
	is allowed at all, which is what turns "this one key cannot be reset live" into "somebody once
	kept a key here", and the next person keeps another.

	The literal check is the load of this test: every string in `RestoreDefaults.swift` that is not
	shown to the user has to be that one key name.
	*/
	@Test("The wipe has exactly one exception, put back after it and argued for")
	func onlyTheLanguageSurvivesTheWipe() throws {
		let source = try Self.source("Nifro/App/RestoreDefaults.swift")
		let code = try Self.stripComments(source)

		#expect(
			code.contains("private static let preservedKey = \"AppleLanguages\""),
			"The exception is no longer one named constant holding one key"
		)

		// Everything the file says to the user, taken out, so what is left is what it says to
		// `UserDefaults`. Both spellings: the dialog's message is a multi-line literal.
		let shown = try Regex(#"String\(localized: (?:""".*?"""|"(?:[^"\\]|\\.)*")\)"#, as: AnyRegexOutput.self)
			.dotMatchesNewlines()

		let names = code.replacing(shown, with: "")
			.matches(of: try Regex(#""(?:[^"\\]|\\.)*""#, as: AnyRegexOutput.self))
			.map { String($0[0].substring ?? "") }

		#expect(
			names == ["\"AppleLanguages\""],
			"Restore names \(names.count) preferences by hand (\(names.joined(separator: ", "))). One is an exception with a reason; two is the key list this file exists not to have."
		)

		let wipe = try #require(code.range(of: "Defaults.removeAll()"), "Restore no longer wipes the domain")
		let putBack = try #require(code.range(of: "UserDefaults.standard.set("), "Restore no longer puts the preserved key back")

		#expect(putBack.lowerBound > wipe.upperBound, "The preserved key is written back before the wipe, which then deletes it")

		// The reason has to travel with the constant. A key kept for no stated reason is a key the next
		// person copies, and the argument for this one is entirely about when it is read.
		let declaration = try #require(source.range(of: "private static let preservedKey"))
		let above = source[..<declaration.lowerBound]
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.dropLast()
			.last

		#expect(
			above?.hasSuffix("*/") == true || above?.hasPrefix("//") == true,
			"The preserved key has no comment above it saying why this one key cannot be reset"
		)
	}

	/**
	The promise the dialog makes about staying signed in is a promise about what this file does *not*
	do. Nothing enforces it but this.
	*/
	@Test("Restoring never touches website data")
	func websiteDataIsLeftAlone() throws {
		let code = try Self.stripComments(Self.source("Nifro/App/RestoreDefaults.swift"))

		#expect(!code.contains("WKWebsiteDataStore"))
		#expect(!code.contains("DiskBudget"))
		#expect(!code.contains("thumbnailCache"))
	}
}
