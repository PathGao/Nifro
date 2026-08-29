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

That leaves three things worth asserting, and they are the three that actually fail. The first is that
the reset is still a whole-domain wipe and has not been turned into an enumeration. The moment
somebody "tidies" it into `Defaults.reset(.opacity, .hideMenuBarIcon, …)`, these tests go red and say
why — which is before the list has had a chance to rot rather than months after.

The second arrived with the exceptions the wipe has. Some keys are lifted out and put back: the
interface language, because it is read as the process starts and no running app can be shown a new
value for it, and the user's websites, because restoring settings stopped meaning deleting them. A
handful of exceptions with a reason each is defensible; a list that grows whenever somebody is unsure
is the very key list the wipe exists to avoid, and it would rot the same way — silently, in whichever
direction the next person guessed. So the exceptions are asserted rather than trusted: an exact set of
hand-written key names in the file, put back after the wipe rather than before it, with a comment
attached to each saying why it is there.

**The third is the one that carries the new cost, and it is the reason the second is safe to have.**
A preserve list fails in the opposite direction to a reset list, and worse: a website key added later
and never added to `websiteKeys` is not a setting that quietly survives, it is data a restore quietly
eats. Nothing about the app's own shape catches that, so the catch is here — the number of keys
`Constants.swift` declares is pinned, and adding any preference at all fails until somebody has opened
`RestoreDefaults` and decided which side of the line it falls on. Half the preserved surface needs no
such help: the per-page records are matched through `PerPageDefaults.allCases`, so a fourth kind is
covered by existing, and that is asserted too rather than left as a thing somebody could spell out
into a fourth literal.

A pinned count is exactly what `RestoreDefaults`'s own prose refuses to keep in a comment, and the
difference is the whole point of putting it here. A count in a comment goes stale in silence. A count
in a test cannot: it is wrong only in front of the person who made it wrong, in the same commit. Its
ceiling is that a key removed and another added in one change nets to the same number and slips
through. That is a narrower hole than the one it closes, and closing it too would mean writing all
thirty names down here.

`isManuallyDisabled` is the most recent key to be sorted here, and it is one of the app's settings:
the wipe takes it, so a restore switches the app back on. That is what the dialog promises, and it is
also the only state a user could be left in with no way to read it — an app switched off by a setting
that has just been reset.

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

	@Test("Every declared preference exists, and there are still exactly the ones Restore was written against")
	func theKeysAreFound() throws {
		let names = try Self.declaredKeyNames()

		// Exact rather than a floor, and it does two jobs. A broken parser — a rename, a reformat, a
		// move to another file — fails loudly here instead of finding no keys and passing every "no key
		// is named" assertion for free. And a preference added anywhere in `Constants.swift` fails here
		// too, which is the only thing standing between `RestoreDefaults.websiteKeys` and the silent
		// rot a preserve list is otherwise heir to: the wipe covers a new key by default, so a new key
		// that turns out to be the user's data is deleted by a restore and nobody finds out from the
		// app. Whoever adds the key is the one person who can say which it is.
		#expect(
			names.count == 30,
			"Constants.swift declares \(names.count) preferences and this test was written against 30. If the parser still works, a key has been added or removed — open `RestoreDefaults` and say whether it is one of the app's settings, which the wipe takes, or one of the user's websites, which `websiteKeys` has to name. Then correct this number."
		)

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

	/**
	No preference is reached through its `Defaults.Keys` declaration, so none can be left out of the
	wipe.

	`.opacity` and not `"opacity"`, which is the distinction that survived the file gaining a preserve
	list. Reaching a key by its declaration is how the wipe turns into an enumeration — the failure at
	the top of this file. Naming one by raw string is the preserve list, which is a different mechanism
	with a different guard: the census below pins exactly which strings are allowed to be there, and
	`theKeysAreFound` fails whenever a new preference could have wanted to join them.
	*/
	@Test("No preference is reached through its declaration, so none can be left out")
	func noKeyIsNamed() throws {
		let code = try Self.stripComments(Self.source("Nifro/App/RestoreDefaults.swift"))

		for name in try Self.declaredKeyNames() {
			#expect(!code.contains(".\(name)"), "Restore reaches the “\(name)” preference through `Defaults.Keys`. Reaching one that way means reaching all of them, and the next one added will be missed.")
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
	The exceptions, and the three ways they could stop being defensible.

	They could multiply. The list was one key long and it is six, which is the change that made this
	test worth reading again rather than a loosening of it: six named keys with an argument each is
	not the same object as a keep-list somebody appends to when they are unsure, and the only thing
	holding those two apart is that appending has to fail here first. So the check is an exact set and
	not a ceiling — a seventh is as red as a hundredth, and the way past it is to write the reason down.

	They could be put back in the wrong place, before the wipe rather than after, which deletes them
	again and leaves nothing to see until somebody restores their settings and comes back to an empty
	Websites window. Or they could lose the comment that says why they are allowed at all, which is
	what turns "this cannot be reset" into "somebody once kept a key here", and the next person keeps
	another.

	**And they could be spelled out where a table already exists**, which is the fourth and is new.
	The per-page records have one key per website per kind, so they are matched by prefix through
	`PerPageDefaults.allCases` — the same table `forgetWherePagesWere` sweeps with, which is what keeps
	the button that deletes them and the wipe that skips them from disagreeing. Written out as literals
	instead, the two lists rot apart and the symptom is a page zoom that survives Clear All Website Data
	or dies in a settings restore. The exact set above catches the literals; this catches the table
	going missing under them.

	The literal check is the load of this test: every string in `RestoreDefaults.swift` that is not
	shown to the user has to be one of those five key names.
	*/
	@Test("The wipe has exactly six exceptions, put back after it and argued for")
	func onlyTheseSurviveTheWipe() throws {
		let source = try Self.source("Nifro/App/RestoreDefaults.swift")
		let code = try Self.stripComments(source)

		#expect(
			code.contains("private static let preservedKey = \"AppleLanguages\""),
			"The language exception is no longer one named constant holding one key"
		)

		#expect(
			code.contains("PerPageDefaults.allCases"),
			"The per-page records are no longer matched through the `CaseIterable` table `forgetWherePagesWere` uses, so the kinds this skips and the kinds Clear All Website Data deletes are now two lists that can disagree."
		)

		// Everything the file says to the user, taken out, so what is left is what it says to
		// `UserDefaults`. Both spellings: the dialog's message is a multi-line literal.
		let shown = try Regex(#"String\(localized: (?:""".*?"""|"(?:[^"\\]|\\.)*")\)"#, as: AnyRegexOutput.self)
			.dotMatchesNewlines()

		let names = code.replacing(shown, with: "")
			.matches(of: try Regex(#""(?:[^"\\]|\\.)*""#, as: AnyRegexOutput.self))
			.map { String($0[0].substring ?? "") }

		#expect(
			names == [
				"\"AppleLanguages\"",
				"\"playlists\"",
				"\"websites\"",
				"\"hasMigratedWebsitesToPlaylists\"",
				"\"hasMigratedWebsiteReloadOverrides\"",
				"\"hasInstalledFeaturedWebsites\""
			],
			"Restore names \(names.count) keys by hand (\(names.joined(separator: ", "))). Six have an argument each in the file: the interface language, because the running app cannot be shown a new value for it, and the websites and the three flags describing them, because restoring settings does not delete what the user made and must not re-run a conversion over it. A seventh needs one too, written down, before this list is the key list this file exists not to have."
		)

		let wipe = try #require(code.range(of: "Defaults.removeAll()"), "Restore no longer wipes the domain")
		let putBack = try #require(code.range(of: "UserDefaults.standard.set("), "Restore no longer puts the preserved keys back")

		#expect(putBack.lowerBound > wipe.upperBound, "A preserved key is written back before the wipe, which then deletes it")

		// The reason has to travel with the constant. A key kept for no stated reason is a key the next
		// person copies, and each of these has an argument that is only about itself.
		for declared in ["private static let preservedKey", "private static let websiteKeys"] {
			let declaration = try #require(source.range(of: declared), "`\(declared)` is gone, so this test is checking nothing")

			let above = source[..<declaration.lowerBound]
				.split(separator: "\n", omittingEmptySubsequences: false)
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.dropLast()
				.last

			#expect(
				above?.hasSuffix("*/") == true || above?.hasPrefix("//") == true,
				"`\(declared)` has no comment above it saying why these keys are not reset"
			)
		}
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
