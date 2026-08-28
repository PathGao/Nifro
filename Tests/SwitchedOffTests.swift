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
		let predicate = try Self.body(of: "var isSwitchedOff: Bool", in: Self.source(named: "RotationBehaviour.swift"))

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
			("RotationBehaviour.swift", "func resetRotationTimer()", "arm the rotation timer"),
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

		// The same two words the power button already uses for the same fact. One literal now where
		// there were two: the picture area draws every one of its readings through `reading(_:)`, so
		// the button's phrase and the picture's are the same string and not two spellings of it.
		#expect(panel.contains("reading(String(localized: \"Switched off\"))"))
	}

	/**
	The app being off is a reading of its own, and it is read before the display's.

	The same defect one level up. `isShowing` is both switches at once, so with the app off every
	column drew the phrase belonging to the power button beside it — on a display nobody had switched
	off, with a button that could not undo what had actually happened. On battery there is nothing to
	press at all: the rule in Settings takes every wallpaper away and the panel's whole account of it
	was every column blaming its own screen.

	Asserted as the order rather than as the words, because the words are in the catalogue and the
	order is the fix: `disabledReading` is `nil` while the app is running, so reading it first costs
	nothing and reading it second would never be reached.
	*/
	@Test("The app being off outranks the display being off")
	func theAppsOwnStateIsReadFirst() throws {
		let panel = try Self.source(named: "DisplayPanel.swift")

		guard
			let app = panel.range(of: "column.disabledReading"),
			let display = panel.range(of: "!column.isShowing")
		else {
			Issue.record("The picture area no longer reads both, so this test is reading nothing.")
			return
		}

		#expect(
			app.lowerBound < display.lowerBound,
			"The picture area asks whether this display is switched off before it asks whether the app is, so an app disabled by the battery rule still reads as four screens each switched off on their own."
		)

		// And the sentence has to come from the app's own answer, not be re-derived beside the column.
		let model = try Self.source(named: "DisplayPanelModel.swift")

		#expect(
			model.contains("AppState.shared.disabledReason"),
			"The panel works out why the app is off for itself. Ask `disabledReason`, which is derived from the same expression `setEnabledStatus` decides with."
		)
	}

	/**
	Nothing outside `RotationBehaviour` reads the per-display switch except the two places argued for here.

	The test above catches a `guard`, which is what refusing to do something looks like — and the panel
	was not refusing anything. It was *drawing*: `isShowing: !scene.isDisabledForDisplay`, an argument
	rather than a condition, so it walked past that check for as long as it existed. With the app
	disabled — on battery, on a locked screen, from the Disable shortcut — every wallpaper was gone and
	every column still read "on", and the power button under it acted on that reading and switched the
	display off for real. Turning the app back on then brought back a screen nobody had switched off.

	So the rule is the read and not the guard, and the two left have to argue for themselves here. Both
	name the per-display switch because it is the only one they can change: `setDisplayEnabled` writes
	it, and `wakeDisplay` clears it on a display somebody has just asked to see something on, which it
	can do — while a Disable that came from the battery it cannot touch.

	It was three. The two callers that woke a display before acting on it each asked the switch for
	themselves, and that is exactly how the panel's own column came to hold two opinions: the arrows
	woke the display in `step` and inherited the same answer from `makeCurrent` underneath, while the
	chooser beside them was believed to do neither. One reader, two callers, and the third way of
	pointing a display at something — picking a playlist, which writes a different key and reaches no
	`makeCurrent` at all — could be given the answer by calling it.
	*/
	@Test("Only the writer and the wake-up read the switch on its own")
	func onlyTheArguedSitesReadThePerDisplaySwitch() throws {
		let allowed = [
			"AppState.swift": [
				"func setDisplayEnabled(_ isEnabledForDisplay: Bool, on display: Display?)",
				"func wakeDisplay(_ display: Display?)"
			],
			// The declaration and the predicate that reads it. `isSwitchedOff` is the whole point: it is
			// the one place allowed to turn the two switches into one answer.
			"RotationBehaviour.swift": ["var isDisabledForDisplay: Bool", "var isSwitchedOff: Bool"]
		]

		for (name, text) in try Self.sources() {
			// Declaring the switch is not reading it, and `body(of:)` returns only what is inside the
			// braces. Struck by name, the way `ScopeTests` strikes the reader it is counting.
			var remaining = text.replacing("var isDisabledForDisplay", with: "")

			for declaration in allowed[name] ?? [] {
				remaining = remaining.replacing(try Self.body(of: declaration, in: text), with: "")
			}

			#expect(
				!remaining.contains("isDisabledForDisplay"),
				"""
				\(name) reads the per-display switch outside the places argued for in this test. Ask \
				`isSwitchedOff`, which also answers the app-wide one — or add this site here with the \
				reason it is allowed to see only half of "off".
				"""
			)
		}
	}

	/**
	Every way of asking to see something on a display wakes that display.

	One reader with two callers, which is the shape the rest of this suite argues for applied to the
	other direction: not "who may refuse", but "who must wake". A mark that moves under a dark screen
	is the defect — nothing is fetched, nothing appears, so it gets pressed again, and the display
	comes back later on something nobody chose.

	The panel's own column had both halves of this wrong at once. Its arrows woke the display in
	`step` *and* inherited the same answer from `makeCurrent` underneath, so the wake looked like the
	arrows' own business — and the website chooser beside them, which is a bare `makeCurrent`, was read
	as not doing it. Picking a playlist genuinely did not: it writes a different key and reaches no
	`makeCurrent` at all, so it is the one caller that has to say `wakeDisplay` in its own body.

	`step` is asserted the other way round, as the absence: the day it grows its own copy back is the
	day the column has two opinions again.
	*/
	@Test("Picking a website, stepping and picking a playlist all wake the display")
	func everyRequestToSeeSomethingWakesTheDisplay() throws {
		// That `makeCurrent` is the one place the answer lives is `ScopeTests`'s to assert, and it does.
		// What is left for here is the three controls in one column that have to reach it, or say the
		// answer themselves where they cannot.
		let model = try Self.source(named: "DisplayPanelModel.swift")

		#expect(
			try Self.body(of: "func selectWebsite(", in: model).contains("makeCurrent("),
			"The panel's website chooser sets the mark some other way, so it no longer inherits the wake in `makeCurrent`."
		)

		#expect(
			try Self.body(of: "func selectPlaylist(", in: model).contains("wakeDisplay"),
			"Picking a playlist for a switched-off display changes the label and leaves the screen dark. It writes `currentPlaylists` directly, so it is the one caller that cannot inherit the answer."
		)

		#expect(
			try !Self.body(of: "func step(", in: model).contains("setDisplayEnabled"),
			"`step` wakes the display itself as well as through `makeCurrent`, which is two answers to what pointing a display at a website means."
		)
	}

	/**
	Nothing puts a switched-off display's window back on screen by ordering it.

	`suspend()` takes that window off screen, and `orderBack` is not only "put this behind the others":
	on a window that is not on screen it is also "show it". `applyBrowsingMode` assigns `isInteractive`
	to every scene and `didSet` fires whether or not the value moved, so browsing one display ran the
	unraised branch on the other display's window and put back the wallpaper the user had switched off.
	Measured on two displays, external switched off: the window went from off screen to on screen on
	the toggle, and stays off screen now.

	The assertion is on the guard rather than on the assignment because the assignment is not the only
	door — `rebuildScenes` writes the same property on every window, and the `bringBrowsingModeToFront`
	subscriber assigns it to itself on purpose so that this branch runs again. `isVisible` and
	`orderBack` are AppKit's own names, so a rename in this app cannot make this pass by accident.
	*/
	@Test("Ordering does not show a window that was taken off screen")
	func orderingDoesNotRevealASuspendedWindow() throws {
		let body = try Self.body(of: "private func applyRaisedState()", in: Self.source(named: "DesktopWindow.swift"))

		guard let unraised = body.range(of: "return") else {
			Issue.record("`applyRaisedState` no longer has an early return, so this is reading nothing.")
			return
		}

		let branch = String(body[body.startIndex..<unraised.lowerBound])

		guard let ordering = branch.range(of: "orderBack") else {
			Issue.record("`applyRaisedState` no longer orders the window at all; check what replaced it.")
			return
		}

		#expect(
			branch[branch.startIndex..<ordering.lowerBound].contains("isVisible"),
			"`applyRaisedState` orders a window back without asking whether it is on screen, which is how a display that is switched off gets its wallpaper put back."
		)
	}
}
