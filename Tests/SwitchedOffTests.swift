import Foundation
import Testing

/**
The guardrail on "a display that is switched off does nothing".

There are two switches that mean off — the app-wide Disable and one display's own power button — and
what shipped was three places each asking a different subset of them. Loading asked neither, so
`reloadWebsite` loaded the page `rebuildScenes` had suspended a line earlier. The two timers and the
menu bar band asked only the app-wide one, so a display switched off on its own kept its reload timer
running and kept tinting the menu bar with the colour of a page nobody could see. The panel's picture
asked only whether something had loaded, which the unwanted load had just made true — and that is
what the user saw and reported: a live thumbnail of a website they had switched off.

The fix is one predicate, `WallpaperScene.isSwitchedOff`, asked at each of those places. What these
tests protect is not the fix but the property that makes it hold tomorrow: nowhere may re-derive "off"
for itself. A third thing that means off — a schedule window that has closed, a display asleep, a
per-website pause — joins that one expression and every site inherits it by existing. Written out at a
guard instead, it would be a fourth subset, and the failure would look exactly like this one did:
compiles, passes review, works every way except the one nobody looks at.

Shape rather than behaviour, and it is worth being plain about why behaviour is not on offer. The
SwiftPM target next door compiles nine files out of `Sites` and `Support`; none of `Wallpaper`, none
of `Visibility`, none of `App`. `WallpaperScene` needs AppKit windows, WebKit and `Defaults`, so there
is nothing here to instantiate and nothing to switch off. The behaviour was observed instead, on a
running unsigned build: with a display switched off, no page load was started for it, `snapshot()`
returned nothing, no band window existed and both timers were unarmed; switching it back on loaded a
page and brought the picture back. That is a thing a person does, not a thing `swift test` does.
*/
@Suite("A switched-off display cannot be forgotten")
struct SwitchedOffTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The app's Swift files with their prose taken out.

	Every one of these files argues for itself at length, and the arguments name the very things the
	assertions look for — the switch that is no longer read directly, the guard that used to be here.
	Matching against the comments would fail on the explanation of why the code is right.
	*/
	private static func sources() throws -> [(name: String, text: String)] {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try FileManager.default
			.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "swift" }
			.sorted { $0.path < $1.path }
			.map {
				(
					$0.lastPathComponent,
					try String(contentsOf: $0, encoding: .utf8)
						.replacing(block, with: "")
						.replacing(line, with: "")
				)
			} ?? []
	}

	private static func source(named name: String) throws -> String {
		guard let match = try sources().first(where: { $0.name == name }) else {
			Issue.record("\(name) is gone from Nifro/.")
			return ""
		}

		return match.text
	}

	/**
	The body of a declaration, from its opening brace to the brace that closes it.

	Counted rather than matched with a regex, because every body below contains braces of its own —
	a `guard … else { … }`, a closure, a string interpolation. A regex that stops at the first `}`
	would read a guard clause as the whole function and quietly pass whatever came after it.
	*/
	private static func body(of declaration: String, in source: String) throws -> String {
		guard let start = source.range(of: declaration) else {
			Issue.record("`\(declaration)` is no longer written that way, so this test is reading nothing.")
			return ""
		}

		guard let open = source[start.upperBound...].firstIndex(of: "{") else {
			Issue.record("`\(declaration)` has no body.")
			return ""
		}

		var depth = 0

		for index in source.indices[open...] {
			switch source[index] {
			case "{":
				depth += 1
			case "}":
				depth -= 1

				if depth == 0 {
					return String(source[open...index])
				}
			default:
				break
			}
		}

		Issue.record("`\(declaration)`'s body is unbalanced.")
		return ""
	}

	/**
	Both switches are named in the predicate, so both are answered wherever it is asked.

	Parsed out of the expression rather than compared to a copy of it kept here, so the day a third
	switch joins it, the test below is testing the new answer without anybody editing this file.
	*/
	@Test("Off means both switches, in one expression")
	func thePredicateNamesBothSwitches() throws {
		let predicate = try Self.body(of: "var isSwitchedOff: Bool", in: Self.source(named: "Playlist.swift"))

		#expect(
			predicate.contains("isEnabled"),
			"`isSwitchedOff` no longer reads the app-wide switch, so disabling the app would stop meaning off."
		)

		#expect(
			predicate.contains("isDisabledForDisplay"),
			"`isSwitchedOff` no longer reads the per-display switch, which is the one that was missing in the first place."
		)
	}

	/**
	Everything a switched-off display must not do asks the predicate.

	The list is here rather than in the app, which is the point: the app has one question and this has
	the sites that ask it. A new site added tomorrow is not covered by this test, and does not need to
	be — what it needs is to ask `isSwitchedOff` rather than a switch, and that is what the test after
	this one enforces on every file at once.
	*/
	@Test("Loading, the timers, the band and the picture all ask it")
	func everyGuardAsksThePredicate() throws {
		let sites = [
			("WallpaperScene.swift", "func load(_ url: URL?)", "load a page"),
			("WallpaperScene.swift", "func resetTimer()", "arm the reload timer"),
			("WallpaperScene.swift", "func snapshot() async -> NSImage?", "hand the panel a picture"),
			("SwapLoading.swift", "func loadBySwapping(_ url: URL?)", "fetch a replacement page"),
			("Playlist.swift", "func resetPlaylistTimer()", "arm the playlist timer"),
			("MenuBarBand.swift", "func installMenuBarBandIfNeeded()", "paint the menu bar band")
		]

		for (file, declaration, what) in sites {
			let body = try Self.body(of: declaration, in: Self.source(named: file))

			#expect(
				body.contains("isSwitchedOff"),
				"`\(declaration)` in \(file) can still \(what) for a display that is switched off."
			)
		}
	}

	/**
	Nothing re-derives "off" for itself.

	A `guard` is what refusing to do something looks like here, so a guard that names a switch instead
	of the predicate is the failure this suite exists for: it is a second opinion about what off means,
	and the next switch will be added to one of them and not the other. That is exactly how the
	per-display switch came to be in none of the six guards above.

	`AppState` is where `isEnabled` lives and is allowed to guard on its own stored property, which it
	does unqualified — it is the qualified `AppState.shared.isEnabled`, the form a scene reaches for,
	that has no business in a guard outside the predicate.
	*/
	@Test("No guard asks a switch directly")
	func nothingAsksASwitchDirectly() throws {
		// Up to the `else`, so a guard's body — which may legitimately call `suspend()` on a scene it
		// found off — is not mistaken for the condition.
		let guardClause = try Regex("guard\\b((?:[^{]|\\n)*?)else\\s*\\{", as: AnyRegexOutput.self).dotMatchesNewlines()

		for (name, text) in try Self.sources() {
			for match in text.matches(of: guardClause) {
				guard let condition = match.output[1].substring else {
					continue
				}

				#expect(
					!condition.contains("AppState.shared.isEnabled"),
					"A guard in \(name) asks the app-wide switch directly. Ask `isSwitchedOff`, which also answers the per-display one:\nguard\(condition)"
				)

				#expect(
					!condition.contains("isDisabledForDisplay"),
					"A guard in \(name) asks the per-display switch directly. Ask `isSwitchedOff`, which also answers the app-wide one:\nguard\(condition)"
				)
			}
		}
	}

	/**
	The panel says which of the four things it is drawing.

	A switched-off display and one still taking its first photograph both have no picture, and until
	this state existed they drew the same empty rectangle — so the honest fix to the live thumbnail
	would have replaced a wrong picture with one that said nothing. The wording is the power button's
	own, which is the other half of it: two readings of one fact in one column should not be two
	phrases.
	*/
	@Test("A switched-off display has a reading of its own")
	func thePanelSaysSwitchedOff() throws {
		let panel = try Self.source(named: "DisplayPanel.swift")

		#expect(panel.contains("!column.isShowing"))
		#expect(panel.contains("Text(\"Switched off\")"))

		// The same two words the power button already uses for the same fact.
		#expect(panel.contains("String(localized: \"Switched off\")"))
	}
}
