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
