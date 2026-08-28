import Foundation
import Testing

/**
The guardrail on "ask about the display, not about the app".

Browsing Mode is stored per display and has been since the flag became a set, but the reader most
callers reached for was `AppState.isBrowsingMode`, which is "that set is non-empty". One question in
the wrong scope produced five separate reports on two displays: browsing the built-in stopped the
external rotating and auto-reloading, raised the external's window to full opacity while leaving it
behind every window, let the external's page open dialogs nobody had clicked, never disarmed the
rotation it was supposed to be pausing, and never rearmed it afterwards. A display unplugged while its
Browsing Mode was on left the key behind and wedged all of that permanently, with no column in the
panel to switch it off from.

Rotation had the mirror problem in the other direction: `rebuildScenes` restarted *every* kept scene's
timers, including the ones `applyWebsiteChanges` had just decided nothing had changed for, so editing
the list on one display reset the other display's rotation clock — and a rebuild runs on every edit,
every display change and every wake.

What these tests protect is the property, not the fix: no reader may ask the app-wide question where
the per-display one exists, and no caller may act on the whole list where it has resolved one scene.
Both defects compile, pass review and work perfectly on one display, which is what makes them worth a
test rather than a comment.

Shape rather than behaviour, for the reason `SwitchedOffTests` spells out at length: the SwiftPM
target next door compiles ten pure files out of `Sites` and `Support`, none of `App`, `Wallpaper` or
`Visibility`. There is no `AppState` here to browse and no window to raise. The behaviour was measured
instead, on a running unsigned build under its own bundle identifier with two displays attached —
timings in the doc comments of the code these tests cover.
*/
@Suite("Browsing Mode and the timers are per display")
struct ScopeTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The app's Swift files with their prose taken out.

	Every one of these files argues for itself at length, and the arguments quote the very readers the
	assertions look for — "asked of the app, browsing one screen let every other screen…". Matching
	against the comments would fail on the explanation of why the code is right.
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

	Counted rather than matched with a regex, for the reason `SwitchedOffTests` gives: every body below
	contains braces of its own, and a regex stopping at the first `}` would read a guard clause as the
	whole function.
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
	Any mention of Browsing Mode that is not asking about one named display.

	`(on` rather than `(on:` so the declaration of the per-display reader — `isBrowsingMode(on display:`
	— is not counted as a reader of the app-wide one. The two declarations themselves are struck out by
	name before this runs.
	*/
	private static let appWideReader = "isBrowsingMode"

	/**
	Nothing outside `AppState` asks whether *any* display is being browsed.

	Absolute, with no allowlist, because outside `AppState` there is always a scene in hand: a scene
	knows its display, and a web view knows its scene. Every one of these was a real symptom —
	`WallpaperScene.resetTimer`, `resetRotationTimer` and four dialog guards in `WebViewController`,
	each of them acting on one display using an answer about all of them.
	*/
	@Test("No display asks the app whether anybody is browsing")
	func nothingOutsideAppStateAsksTheAppWideQuestion() throws {
		let qualified = try Regex("AppState\\.shared\\.isBrowsingMode(?!\\s*\\(on)")

		for (name, text) in try Self.sources() {
			for match in text.matches(of: qualified) {
				Issue.record(
					"""
					\(name) asks `AppState.shared.isBrowsingMode`, which is true when *any* display is \
					being browsed. Ask `isBrowsingMode(on:)` with the display this code is acting for. \
					Around: \(Self.context(around: match.range, in: text))
					"""
				)
			}
		}
	}

	/**
	Inside `AppState` and its extensions, only the two app-wide readers are left.

	Both are app-wide in themselves rather than by oversight, and the argument for each is in
	`AppState.isBrowsingMode`: activating the app has no per-display form, and a modal alert is
	app-modal, so "is the user in front of a page of ours at all" is the question it means. The list is
	here rather than in the app because the app has one question and this has the two places allowed to
	ask the coarse version of it — a third arriving is exactly the failure this suite exists for, and
	it should have to be argued for here.
	*/
	@Test("Only two readers are allowed the coarse answer")
	func onlyTheTwoAppWideReadersRemain() throws {
		let allowed = [
			"AppState.swift": [
				"func applyBrowsingMode()",
				"private func report(_ webViewError: Error)"
			]
		]

		let reader = try Regex("\(Self.appWideReader)(?!\\s*\\(on)")

		for (name, text) in try Self.sources() {
			// The declarations are not readers. Struck by name so the regex above does not have to
			// know the difference between defining the question and asking it.
			var remaining = text
				.replacing("var \(Self.appWideReader)", with: "")
				.replacing("func \(Self.appWideReader)", with: "")

			for declaration in allowed[name] ?? [] {
				remaining = remaining.replacing(try Self.body(of: declaration, in: text), with: "")
			}

			for match in remaining.matches(of: reader) {
				Issue.record(
					"""
					\(name) reads `\(Self.appWideReader)` app-wide outside the two places allowed to. \
					Ask `\(Self.appWideReader)(on:)`, or argue for a third in `ScopeTests`. \
					Around: \(Self.context(around: match.range, in: remaining))
					"""
				)
			}
		}
	}

	/**
	Everything Browsing Mode pauses, dims or permits names the display it is doing it for.

	The other half of the test above: that one says nobody asks the coarse question, this says the
	places that have to ask *something* are asking the sharp one. A guard that stopped asking at all
	would pass the first and fail this.
	*/
	@Test("The four things Browsing Mode changes each ask about their own display")
	func everySiteAsksAboutItsOwnDisplay() throws {
		let sites = [
			("WallpaperScene.swift", "func resetTimer()", "pause every display's auto-reload"),
			("RotationBehaviour.swift", "func resetRotationTimer()", "pause every display's rotation and schedule"),
			("DimWhenUnfocused.swift", "func targetOpacity(on display: Display?) -> Double", "raise every display to full opacity"),
			("HoldToInteract.swift", "private func begin()", "refuse the hold because another display is browsing")
		]

		for (file, declaration, what) in sites {
			let body = try Self.body(of: declaration, in: Self.source(named: file))

			#expect(
				body.contains("\(Self.appWideReader)(on:"),
				"`\(declaration)` in \(file) no longer asks about one display, so it can \(what)."
			)
		}
	}


	/**
	A download needs somebody to have asked for it.

	The one guard in this file that is not about a dialog. The four `WKUIDelegate` panels were put
	behind Browsing Mode and the two download paths were left where they were, which left the app in
	the state this test exists to prevent: the explicit download items are struck from the page's
	context menu, so every download it could still perform was one nobody requested. The response path
	is the one that matters — it needs no click, only a page that navigates itself to a response WebKit
	cannot show, on a screen nobody is looking at.

	Asserted through the named guard rather than by matching `.download` in place, because the action
	path already reads Browsing Mode for an unrelated reason and would satisfy a looser test without
	guarding anything.
	*/
	@Test("A download needs somebody to have asked for it")
	func downloadsAreNotStartedBehindTheUsersBack() throws {
		let source = try Self.source(named: "WebViewController.swift")

		#expect(
			try Self.body(of: "private var isDownloadWanted: Bool", in: source)
				.contains("\(Self.appWideReader)(on:"),
			"`isDownloadWanted` no longer asks about one display, so browsing one screen lets every screen write files."
		)

		let paths = [
			"decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy",
			"decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy"
		]

		for declaration in paths {
			let body = try Self.body(of: declaration, in: source)

			guard body.contains(".download") else {
				continue
			}

			#expect(
				body.contains("isDownloadWanted"),
				"`\(declaration)` can return `.download` without asking whether anybody asked for it."
			)
		}
	}

	/**
	Switching Browsing Mode settles both clocks, in the one place that runs on the way in and the way
	out.

	The guards are only half of a pause: they decide what a timer does when it is next armed, and
	something has to arm it. Only the reload timer was settled here, so entering Browsing Mode never
	stopped the rotation — measured at a one-minute interval, the tick fired eleven seconds in and
	replaced the page being typed into — and then the write that tick made rebuilt the scenes, which
	killed the rotation timer at a moment when the guard said no, and nothing ever armed it again.
	Zero rotations for the rest of the session.

	So the two failures are one missing line, and it is missing from here rather than from a guard.
	*/
	@Test("Browsing Mode arms and disarms both clocks")
	func browsingModeSettlesBothTimers() throws {
		let body = try Self.body(of: "func applyBrowsingMode()", in: Self.source(named: "AppState.swift"))

		for timer in ["resetTimer()", "resetRotationTimer()"] {
			#expect(
				body.contains(timer),
				"""
				Switching Browsing Mode does not settle `\(timer)`, so the pause is never armed on the \
				way in or lifted on the way out.
				"""
			)
		}
	}

	/**
	Letting go of the hold acts on the display the hold started on.

	Both ends resolved the display for themselves, from the pointer, at their own moment — and the hold
	*is* the time between those moments. Releasing over the other screen turned Browsing Mode on for one
	display and off for another, leaving the first raised over its desktop icons with only the panel's
	button to clear it. The same defect `croppingScene` was introduced to fix, and the same shape of
	fix: hold the thing, do not look it up again.
	*/
	@Test("The hold remembers what it started")
	func lettingGoActsOnWhatBeganIt() throws {
		let source = try Self.source(named: "HoldToInteract.swift")
		let end = try Self.body(of: "private func end()", in: source)

		#expect(
			!end.contains("actingScene"),
			"`end()` resolves the display from the pointer again. It has to act on what `begin()` acted on."
		)

		#expect(
			end.contains("holdingScene"),
			"`end()` no longer acts on the scene the hold started on."
		)
	}

	/**
	An action acts on the scene it resolved.

	`run` works out one scene from the source of the request and then every case is supposed to use it.
	Two did not: Reload looped every display, and Choose Region threw the scene away and re-resolved
	through `actingScene`. Named rather than matched by shape, because "loops every scene" is what
	`reloadWebsite` and `reloadEverything` are *for* — they are correct where the change really is
	app-wide, and wrong here.
	*/
	@Test("No action reaches past the scene it resolved")
	func actionsActOnOneScene() throws {
		let run = try Self.body(
			of: "func run(from source: Source = .automation)",
			in: Self.source(named: "Actions.swift")
		)

		for reach in ["AppState.shared.reloadWebsite()", "AppState.shared.beginCropSelection()"] {
			#expect(
				!run.contains(reach),
				"`Action.run` calls `\(reach)`, which ignores the scene it just resolved and acts on every display."
			)
		}

		#expect(
			run.contains("scene.reload()"),
			"Reload no longer acts on the resolved scene."
		)
	}

	/**
	A rebuild leaves the clocks of the displays nothing changed for alone.

	`rebuildScenes` runs on every edit to the website list, every display change and every wake, and it
	restarted both timers on every scene it kept — and `resetRotationTimer` zeroes the minute count, so
	that is not a rounding error but a display put back to the start of its interval. Both callers ask
	`isUpToDate`, which is the point: one test, so the timers cannot disagree with the pages.
	*/
	@Test("A rebuild and a reload agree about which displays the change reached")
	func rebuildingKeepsAnUntouchedDisplaysClock() throws {
		let state = try Self.source(named: "AppState.swift")

		for declaration in ["func rebuildScenes()", "func applyWebsiteChanges()"] {
			let body = try Self.body(of: declaration, in: state)

			#expect(
				body.contains("isUpToDate"),
				"`\(declaration)` no longer asks whether the change reached this display."
			)
		}

		// The hammer itself, rather than the one caller that swung it. `AppState.resetTimer()` reset
		// both timers on every scene, `Defaults.publisher(.websites)` called it on every edit, and a
		// rotation tick is an edit — so one display rotating restarted the other display's clock.
		#expect(
			!state.contains("func resetTimer()"),
			"`AppState` has an app-wide timer reset again. A scene's clock belongs to that scene."
		)
	}

	/**
	Which displays get a wallpaper is asked of the displays, not of the website list.

	The same wrong scope as the rest of this suite, in its largest form. `displaysInUse` was the
	distinct `effectiveDisplay` over the websites, and `rebuildScenes` built one scene per entry, so a
	list-wide fact — "some website names this screen" — decided whether a screen existed at all. A
	second display plugged in after the first launch was named by nothing and stayed black, and there
	was no column for it in the panel to fix it from, because the panel draws one column per scene. The
	shipped websites were pinned one per display to paper over exactly this, which is why that pinning
	went with it.

	Both halves are asserted, because each fails on its own. Building from the displays without the
	fallback leaves no wallpaper at all in the moments `Display.all` is empty — reconfiguration, every
	screen asleep — and those are the moments a display change puts this on the stack.
	*/
	@Test("Every attached display gets a scene, and there is always one")
	func scenesAreBuiltFromTheDisplays() throws {
		let rebuild = try Self.body(of: "func rebuildScenes()", in: Self.source(named: "AppState.swift"))
		let controller = try Self.source(named: "WebsitesController.swift")

		#expect(
			rebuild.contains("Display.all"),
			"`rebuildScenes` no longer starts from the attached displays. A display no website names gets no scene, and there is nothing on that screen to say so."
		)

		#expect(
			!rebuild.contains("WebsitesController.shared.displays"),
			"`rebuildScenes` asks the website list which displays exist again. That is the direction this refactor inverted."
		)

		#expect(
			!controller.contains("displaysInUse"),
			"`WebsitesController` derives a display list from the websites again. Which screens exist is not a fact about the list."
		)

		#expect(
			rebuild.contains("[nil]"),
			"Nothing keeps one scene when `Display.all` is empty, so a reconfiguration or a sleeping screen leaves no wallpaper at all."
		)
	}

	/**
	A display that goes away takes its Browsing Mode and nothing else.

	The one per-display entry that is a state rather than a preference, and the only one with teeth: it
	survived in `Defaults` across relaunches, and every reader went on answering yes for a display with
	no column in the panel to switch it off from.

	The other keys are asserted *absent* on purpose. "Prune what the display left behind" is the change
	that looks obviously right and takes the good half with it: a monitor switched off, pinned, or set
	to rotate hourly before it was unplugged has to come back that way. Forgetting one for good is
	Restore Defaults, which is a thing the user asks for.
	*/
	@Test("Unplugging clears Browsing Mode and leaves the preferences alone")
	func onlyTheStateIsPruned() throws {
		let rebuild = try Self.body(of: "func rebuildScenes()", in: Self.source(named: "AppState.swift"))

		#expect(
			rebuild.contains("browsingDisplays"),
			"Nothing clears Browsing Mode for a display whose scene is torn down, so an unplugged display keeps it for good."
		)

		for preference in ["disabledDisplays", "rotationModes", "rotationIntervals"] {
			#expect(
				!rebuild.contains(preference),
				"`rebuildScenes` touches `\(preference)`. A display switched off or pinned before it went away has to come back that way."
			)
		}
	}

	/**
	Nothing reads a website's own "is current" flag.

	The third per-display fact to be found living in a slot with room for one answer, after Browsing
	Mode and the load error above. `Website.isCurrent` is a `Bool` on each website, and one website
	belongs to one screen, so it looks per display and is not: keeping it unique needed a sweep over the
	whole list, the sweep grouped the list by display, and every writer that did not go through it broke
	the rule. Both halves were seen. A rotation tick on one display cleared the other display's mark, so
	that display read "nothing is current", counted from the beginning and sat on its first website for
	good. "Show on" wrote the list directly and carried a website's mark to a screen that already had
	one, so the display the person had just named did not change and the list drew two ticks.

	The answer is `Defaults[.currentWebsites]` now, one entry per display, so neither is expressible.
	The field is still stored — a website encoded without it will not decode on the build before this
	one — and the whole of what makes that safe is that nothing asks it anything.

	Reads only. An assignment is not a second home: the two that remain keep the stored field decodable,
	and the Shortcuts entity has a property of its own by the same name that it fills from the app.
	*/
	@Test("Nothing asks a website whether it is the current one")
	func nothingReadsTheFlagOnTheWebsite() throws {
		let read = try Regex("\\.isCurrent(?!\\s*=[^=])")

		for (name, text) in try Self.sources() {
			for match in text.matches(of: read) {
				Issue.record(
					"""
					\(name) reads `isCurrent` off a website, which is one slot per website answering a \
					question per display. Ask `WebsitesController.currentWebsiteID(on:)` with the display \
					this code is acting for, or `isShowing(_:)` where there is no display to name. \
					Around: \(Self.context(around: match.range, in: text))
					"""
				)
			}
		}
	}

	/**
	One place decides what a display is showing.

	The other half of I1, and the half a dictionary does not give for free. Storage with one entry per
	display makes two answers *for one screen* impossible; it does nothing about two places deciding
	what that entry says, which is how the flag it replaced went wrong — `makeCurrent` moved the mark
	and a `Binding` into the stored list moved it too, and only one of them knew the rule.

	Absolute, with no allowlist. `WebsitesController` is where the verb lives and where every route to it
	already meets — Next, Previous and Random are three verbs with three entry points each and all nine
	end in `makeCurrent`, which is the argument that file makes at length. A second writer elsewhere is
	the defect this whole change was made to remove.
	*/
	@Test("Only one file writes what a display is showing")
	func theCursorHasOneWriter() throws {
		let assignment = try Regex("Defaults\\[\\.currentWebsites\\](\\[[^\\]]*\\])?\\s*=[^=]")

		for (name, text) in try Self.sources() where name != "WebsitesController.swift" {
			for match in text.matches(of: assignment) {
				Issue.record(
					"""
					\(name) writes `currentWebsites`. Moving what a display shows goes through \
					`WebsitesController.makeCurrent(_:switchingDisplayOn:)`, which is where every route to \
					it already meets. Around: \(Self.context(around: match.range, in: text))
					"""
				)
			}
		}
	}

	/**
	And it is keyed by the display, which is the part that can be wrong while everything is green.

	A dictionary makes "at most one website is current per display" a property of the storage instead of
	something a sweep has to keep true — but only if the key is the display. Keyed by anything else it
	holds a different invariant perfectly and says nothing about screens, and there is no symptom until
	somebody attaches a second one.

	`Display.settingsKey(for:)` by name, because that is the key `disabledDisplays`, `rotationModes`,
	`rotationIntervals` and `browsingDisplays` are already stored under: a display unplugged and plugged
	back in has to come back to its own entry, and that function is where "the main display is a display
	like any other" is settled.
	*/
	@Test("What a display is showing is one entry per display")
	func theCursorIsKeyedByTheDisplay() throws {
		#expect(
			try Self.source(named: "Constants.swift").contains("Key<[String: Website.ID]>(\"currentWebsites\""),
			"`currentWebsites` no longer holds one website id per display key, so uniqueness per display is not the storage any more."
		)

		let controller = try Self.source(named: "WebsitesController.swift")

		for declaration in ["func currentWebsiteID(on display: Display?)", "func makeCurrent("] {
			#expect(
				try Self.body(of: declaration, in: controller).contains("Display.settingsKey(for:"),
				"`\(declaration)` no longer keys on the display, so what it reads or writes is not a per-display answer."
			)
		}
	}

	/**
	A display that goes away keeps what it was showing, and is told when something lands on it.

	The other side of the line `onlyTheStateIsPruned` draws above, and the case that line was drawn
	for. Which website is up on a screen is the user's choice about that screen, exactly as switched
	off, pinned and "every thirty minutes" are: unplug the monitor at night, plug it in in the morning,
	and it has to come back showing what it was showing. Browsing Mode is the only per-display entry
	that cannot survive its display, because it means "somebody is typing on this screen right now" and
	that stops being true when the screen is gone. Which website is up does not stop being true, it
	stops being visible — and forgetting it costs the user a wallpaper they chose, which is the shape of
	thing Restore Defaults exists to be asked for.

	So the one function that is handed the departed displays must not remove anything, and `filter`,
	`removeValue` and an assignment of `nil` are the three ways it could. What it is for is the other
	half of an unplug: a website that moves to the main display takes that screen, and this is where it
	says so.
	*/
	@Test("A display that goes away keeps what it was showing")
	func aDepartedDisplayKeepsItsWebsite() throws {
		let body = try Self.body(
			of: "func handOverCurrentWebsites(",
			in: Self.source(named: "WebsitesController.swift")
		)

		for removal in ["filter", "removeValue", "= nil"] {
			#expect(
				!body.contains(removal),
				"""
				`handOverCurrentWebsites` drops an entry (`\(removal)`). A display's wallpaper is a \
				choice the user made about that display and has to survive the cable, like the three \
				settings `rebuildScenes` keeps for it.
				"""
			)
		}

		#expect(
			try Self.body(of: "func rebuildScenes()", in: Self.source(named: "AppState.swift"))
				.contains("handOverCurrentWebsites"),
			"Nothing tells a screen that a website has landed on it, so unplugging a display leaves its wallpaper nowhere."
		)
	}

	/**
	Stepping is one answer, in the one place every route to it passes through.

	Pressing Next over a display that is switched off moved that display's mark under a dark screen and
	asked for nothing, so pressing it a few times looking for a reaction left the display to come back
	later on a website nobody chose. The panel's own two buttons had always handled it — stepping a
	switched-off display is how you wake it — and the keyboard shortcut, the `nifro://` commands and the
	Shortcuts action reached the same verb by another door and skipped it. One verb, one display, two
	answers depending on which control was pressed.

	Shape rather than behaviour, for the reason this suite gives at the top: there is no `AppState` here
	to switch a display off on and no scene to ask. What can be checked is the property that makes the
	fix hold tomorrow — that the answer is not written at a call site, where the next route added will
	not inherit it. The behaviour was observed instead, on a running unsigned build.
	*/
	@Test("Every route to Next and Previous meets the switch in one place")
	func steppingWakesADisplayWhereverItIsAskedFrom() throws {
		#expect(
			try Self.body(of: "func makeCurrent(", in: Self.source(named: "WebsitesController.swift"))
				.contains("setDisplayEnabled"),
			"`makeCurrent` no longer switches a display back on, so a display that is off takes the mark and stays dark."
		)

		// Next, Previous and Random are three verbs and three entry points each. What makes one answer
		// enough is that all nine end here.
		let rotation = try Self.source(named: "RotationBehaviour.swift")

		for verb in ["func makeNextCurrent(", "func makePreviousCurrent(", "func makeRandomCurrent("] {
			#expect(
				try Self.body(of: verb, in: rotation).contains("makeCurrent("),
				"`\(verb)` sets the mark some other way, so it no longer inherits the answer in `makeCurrent`."
			)
		}
	}

	/**
	Whether a display can rotate is the question it rotates by.

	I2, and the last of this suite's shape: one question with two derivations. `canRotate` lit the
	panel's arrows off the count of the websites naming that display, and pressing one stepped through
	`eligible(for:)` — that set narrowed by the schedule and by whether a website can be shown at all. A
	display with two websites and one of them unshowable therefore lit both arrows and did nothing when
	either was pressed, which is K24. Nothing was wrong with either expression. What was wrong is that
	there were two, so every narrowing added to one of them is a new way for the arrows to lie.

	Asserted as "the value names `eligible`" rather than as a copy of the expression, so the day a third
	narrowing joins it this test is testing the new answer without anybody editing this file — the same
	shape `SwitchedOffTests` uses for `isSwitchedOff`.

	**The ceiling.** This reads the line `canRotate:` is written on, so a derivation spread over several
	lines with `eligible` on none of them would pass. That is a thing somebody would have to do on
	purpose; what it catches is the thing that happens by accident, which is a count of a list that is
	already in the function.
	*/
	@Test("Whether a display can rotate is the question it rotates by")
	func canRotateIsDerivedFromEligible() throws {
		let column = try Self.body(
			of: "private func column(for scene: WallpaperScene",
			in: Self.source(named: "DisplayPanelModel.swift")
		)

		guard let assignment = column.range(of: "canRotate:") else {
			Issue.record("`column(for:)` no longer fills `canRotate` in, so this test is reading nothing.")
			return
		}

		let value = column[assignment.upperBound...].prefix { $0 != "\n" }

		#expect(
			value.contains("eligible("),
			"""
			`canRotate` is worked out without asking `eligible`, which is what the arrows it lights step \
			through. Two derivations of one question is how an arrow comes to be lit and inert. \
			Around: \(value.trimmingCharacters(in: .whitespaces))
			"""
		)

		// And the expression it names has to be the one the arrows actually use, or the two have parted
		// again with this test still passing.
		let rotation = try Self.source(named: "RotationBehaviour.swift")

		for verb in ["func makeNextCurrent(", "func makePreviousCurrent("] {
			#expect(
				try Self.body(of: verb, in: rotation).contains("eligible("),
				"`\(verb)` steps through something other than `eligible`, so the arrows and what they do are two answers again."
			)
		}
	}

	/**
	Sixty characters either side of a match, so a failure says where to look without printing the file.
	*/
	private static func context(around range: Range<String.Index>, in text: String) -> String {
		let start = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
		let end = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
		return String(text[start..<end]).replacing("\n", with: " ").trimmingCharacters(in: .whitespaces)
	}

	/**
	A failed load belongs to the display it failed on.

	There were four writers and one slot. All four sit in `WallpaperScene` and `SwapLoading`, which run
	once per display and know which one they are, and every one of them wrote `AppState.webViewError`
	— so the last load to finish spoke for every screen. The clearing half is what made it a defect
	rather than a wrong word: the routine end of a load that worked writes `nil`, so a reload timer
	firing on the monitor erased the laptop's failure with neither page having changed.

	An assignment rather than a mention, because the app-wide form was a settable property and the
	per-display form is a pair of functions. Nothing can assign to those, so a match here is a stored
	app-wide slot having come back.
	*/
	@Test("No load failure is stored for the app")
	func nothingAssignsAnAppWideLoadError() throws {
		let assignment = try Regex("webViewError\\s*=")

		for (name, text) in try Self.sources() {
			for match in text.matches(of: assignment) {
				Issue.record(
					"""
					\(name) assigns `webViewError`, which was one slot shared by every display. \
					Call `setWebViewError(_:on:)` with the display the load was for. \
					Around: \(Self.context(around: match.range, in: text))
					"""
				)
			}
		}
	}

	/**
	One place says what the menu bar icon is about.

	The icon is a single glyph shared by every display and its tooltip is the only sentence it has, so
	a per-display path writing it directly is the same defect in a second place: the scene that
	finished last spoke for all of them. `WallpaperScene` wrote the page title there on every
	successful load, which meant a routine reload on one display replaced another display's failure
	with an unrelated page's name.

	The same argument `refreshLoadingIndicator` makes for the icon itself, applied to the words next
	to it.
	*/
	@Test("Only one place says what the menu bar icon is about")
	func theTooltipHasOneWriter() throws {
		let owner = try Self.body(of: "func refreshStatusItemTooltip()", in: Self.source(named: "AppState.swift"))
		let assignment = try Regex("toolTip\\s*=")

		for (name, text) in try Self.sources() {
			let outside = name == "AppState.swift" ? text.replacing(owner, with: "") : text

			for match in outside.matches(of: assignment) {
				Issue.record(
					"""
					\(name) writes the status item's tooltip directly. Change what \
					`refreshStatusItemTooltip()` answers and call it, so one display's page cannot \
					overwrite another display's failure. Around: \(Self.context(around: match.range, in: outside))
					"""
				)
			}
		}
	}
}
