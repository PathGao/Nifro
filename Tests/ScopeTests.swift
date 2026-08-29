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
			("BrowsingModeShortcut.swift", "private func begin()", "refuse the hold because another display is browsing")
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
		let source = try Self.source(named: "BrowsingModeShortcut.swift")
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
	The hold refuses to begin after the press it belongs to is already over.

	One key now carries both behaviours, so the hold starts on a timer half a second after the key goes
	down rather than on the key itself — and a hotkey's key-up never arrives when the modifiers are
	released first. Without this check the timer lands on a press nobody is making any more and turns
	Browsing Mode on with nothing left to turn it off: no key-up coming, and the modifier watch is
	installed too late to see a release that already happened.
	*/
	@Test("A hold whose keys are already up does not begin")
	func holdChecksTheKeysAreStillDown() throws {
		let begin = try Self.body(
			of: "private func begin()",
			in: Self.source(named: "BrowsingModeShortcut.swift")
		)

		#expect(
			begin.contains("NSEvent.modifierFlags.contains(requiredModifiers)"),
			"`begin()` no longer checks the shortcut is still held, so a lost key-up strands Browsing Mode on."
		)
	}

	/**
	The identifier the first-run explanation of Browsing Mode is stored under.

	Keyed on rather than on the Swift name around it because this one cannot be renamed by a
	refactoring: `SSApp.runOnce` writes it into `UserDefaults`, so changing the spelling shows the
	alert a second time to every install that has already seen it. A rule keyed on the function name
	instead would go red on a rename that changed nothing, which is the difference between a useful
	red and noise.
	*/
	private static let explanationKey = "activatedBrowsingMode"

	/**
	What the app calls the one place that explanation lives, read out of the app rather than written
	down here.

	The tests below check that each route reaches it, and a route reaching it has to name it — so the
	name would otherwise be spelled four times in this file and go red the day somebody renames the
	function without touching what it does. Found instead by looking for the identifier above and
	taking the declaration it sits inside, so a rename renames both sides at once.
	*/
	private static func explainer() throws -> String {
		let all = try sources()
		let copies = all.reduce(0) { $0 + $1.text.ranges(of: explanationKey).count }

		guard
			copies == 1,
			let text = all.first(where: { $0.text.contains(explanationKey) })?.text
		else {
			Issue.record(
				"""
				`\(explanationKey)` is written \(copies) times. The explanation of Browsing Mode \
				has one home and every route calls it: a second copy is the defect this area has already \
				been through, where four entry points each carried their own and one of them was missed.
				"""
			)
			return ""
		}

		guard
			let at = text.range(of: explanationKey),
			let declaration = text[..<at.lowerBound].range(of: "func ", options: .backwards)
		else {
			Issue.record("`\(explanationKey)` is not inside a function any more, so these tests are reading nothing.")
			return ""
		}

		return String(text[declaration.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" })
	}

	/**
	Every way of switching Browsing Mode on says what Browsing Mode is.

	This is the second time. The explanation began on the menu item, so the shortcut, the URL and the
	Shortcuts action all switched Browsing Mode on and said nothing — and `Action` was built to hold
	the body once so that could not happen. Then the panel replaced the menu, called `setBrowsingMode`
	itself, and the same defect came back through the surface that is now the most discoverable way
	in. Nothing went red either time, which is the whole reason this test exists rather than a
	convention: the explanation is not a courtesy but the only sentence the app has about the page
	being behind the user's windows, so a route without it hands somebody an interactive wallpaper
	they cannot see and cannot account for.

	Written as an allowlist of sites permitted to write the switch on their own, so a new surface
	fails until somebody argues for it here. `setBrowsingMode(false` is not a route in — it is every
	way *out*, and the way out has nothing to explain.

	The hold is the argued exception and the reason its exception is written down: its `begin()` runs
	with the key still down, and an `NSAlert` is app-modal, so raising one there puts a run loop of
	its own between the hold and both of its exits. It explains at `end()` instead, which is asserted
	below in both directions.
	*/
	@Test("Every route into Browsing Mode explains it the first time")
	func everyRouteThatSwitchesBrowsingModeOnExplainsIt() throws {
		let allowed = [
			// The verb every other route goes through. It explains, which is asserted below.
			"AppState.swift": ["func toggleBrowsingMode(on display: Display?)"],
			// The hold, which explains at the other end.
			"BrowsingModeShortcut.swift": ["private func begin()"]
		]

		let switchesOn = try Regex("setBrowsingMode\\(\\s*(?!false)")

		for (name, text) in try Self.sources() {
			// Declaring the switch is not throwing it. Struck by name, the way the tests above strike
			// the readers they are counting.
			var remaining = text.replacing("func setBrowsingMode", with: "")

			for declaration in allowed[name] ?? [] {
				remaining = remaining.replacing(try Self.body(of: declaration, in: text), with: "")
			}

			for match in remaining.matches(of: switchesOn) {
				Issue.record(
					"""
					\(name) switches Browsing Mode on by writing the switch. Call the app's own toggle, \
					which explains what Browsing Mode is the first time it comes on — or add this site \
					to the allowlist in `ScopeTests` with the reason it may hand over a page it does not \
					account for. Around: \(Self.context(around: match.range, in: remaining))
					"""
				)
			}
		}

		let explainer = try Self.explainer()

		guard !explainer.isEmpty else {
			return
		}

		#expect(
			try Self.body(of: "func toggleBrowsingMode(on display: Display?)", in: Self.source(named: "AppState.swift"))
				.contains(explainer),
			"The toggle every surface shares no longer explains Browsing Mode, so none of them do."
		)

		let shortcut = try Self.source(named: "BrowsingModeShortcut.swift")

		#expect(
			try Self.body(of: "private func end()", in: shortcut).contains(explainer),
			"Letting go of the hold no longer explains Browsing Mode, and the hold is the one route that cannot explain it at the other end."
		)

		#expect(
			try !Self.body(of: "private func begin()", in: shortcut).contains(explainer),
			"""
			The hold explains Browsing Mode while the key is still down. An `NSAlert` is app-modal and \
			runs a run loop of its own, and the hold leaves only through the Carbon key-up or the local \
			`.flagsChanged` monitor — either one lost to that session strands the wallpaper in front of \
			the desktop with the hotkey refusing to put it back.
			"""
		)
	}

	/**
	And the switch itself is written in one file.

	The allowlist above reads the name of the setter, so a route reaching around it into the stored
	set would satisfy it by saying nothing. `browsingDisplays` is the key that set is saved under, so
	this is the same rule asked of the store rather than of the verb — the shape `theCursorHasOneWriter`
	uses for what a display is showing, and for the same reason: storage that only one file writes is
	the thing that makes one answer enough.

	Only the insert. Every file may already be seen clearing the set — the empty-website-list rule in
	`Events` does — and taking Browsing Mode away is not a route in.
	*/
	@Test("Only the app switches Browsing Mode on for a display")
	func onlyAppStatePutsADisplayIntoBrowsingMode() throws {
		let insert = try Regex("browsingDisplays\\]\\s*\\.insert")

		for (name, text) in try Self.sources() where name != "AppState.swift" {
			for match in text.matches(of: insert) {
				Issue.record(
					"""
					\(name) puts a display into Browsing Mode by writing `browsingDisplays` directly, \
					which walks past the first-time explanation of what Browsing Mode is. \
					Around: \(Self.context(around: match.range, in: text))
					"""
				)
			}
		}
	}

	/**
	A tap goes through the action, not straight at the switch.

	`Action.toggleBrowsingMode` runs the toggle every surface shares, and that toggle carries the
	first-run explanation of what Browsing Mode is. The hold reaches past it on purpose — it is not a
	toggle and says so — but the tap *is* that toggle, and calling `setBrowsingMode` from here would
	quietly fork it into a second copy that drifts.
	*/
	@Test("Tapping the key runs the same toggle as everything else")
	func tapRunsTheSharedToggle() throws {
		let keyUp = try Self.body(
			of: "private func keyUp()",
			in: Self.source(named: "BrowsingModeShortcut.swift")
		)

		#expect(
			keyUp.contains("Action.toggleBrowsingMode.run"),
			"A tap no longer runs the shared toggle, so it has its own copy of what Browsing Mode means."
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
	The property that says the page in the web view is the website the display resolves to.

	A private name, and the file's other tests say why that is usually the wrong thing to anchor on. It
	is what there is: this question has no stored key and no exported symbol behind it, and the
	alternative is matching the comparison itself — which is exactly the thing the second test below
	forbids anybody from writing again.
	*/
	private static let pageIsTheAnswer = "hasLoadedItsWebsite"

	/**
	Nothing writes what the user chose to a website while the page they chose it in front of is another one.

	The same mistake as the one this suite was built for, one layer further in. `beginCropSelection`
	used to find a scene by matching the list-wide current website, so on two displays it framed
	whichever screen last held the mark; that was fixed by passing the scene. The scene then answers
	with `website`, which is where the display is *heading*, and the region the user drags out lands on
	whatever the web view is actually showing. Those two are the same for all but a few seconds of a
	swap, and the panel disables the column for exactly those seconds — so the gap opens only when a
	load stops being outstanding without arriving.

	Which is what a failed swap is. `loadBySwapping` stores the error and returns, its `defer` clears
	`pendingWebView`, `isLoading` goes false, and the column comes back naming the website that never
	loaded over the picture of the one still up. Crop then framed the page on screen and stored the
	region on the other website, and Mute changed the audio of a website that was not the one making
	the sound. The next successful load closed the window, so the column looked right again and neither
	write was ever seen to be wrong. With the network down that window is as long as the network is down.

	**The two writers, and only those two.** The set is not "controls that touch the page" — Browsing
	Mode does that and is deliberately outside, because it writes `browsingDisplays`, keyed by display,
	and nothing per website: what it hands over is the page genuinely on the screen, so there is no
	wrong record for it to write and gating it only took away the page the user could still see. It is
	`hasPage`'s doc that argues that, and a third writer arriving is what this test is here to catch.

	On each verb rather than on each button, because a button is one of several ways in: the keyboard
	shortcuts reach `beginCropSelection` and `toggleSound` without going past anything the panel draws.
	The panel's own gate is asserted too — a control that does nothing should not look pressable — but
	it is the second line of defence and not the first.

	Shape rather than behaviour for this suite's usual reason: the SwiftPM target next door compiles
	nothing from `App`, `Wallpaper`, `Zoom`, `Sites`' scene extensions or `Screens`, and there is no
	`WallpaperScene` here to give a page that disagrees with its website. What was run by hand is in
	the pull request.
	*/
	@Test("Both writers wait for the page to be the website they will write to")
	func theWritersRefuseAPageThatIsNotTheAnswer() throws {
		let writers = [
			("CropSelection.swift", "func beginCropSelection(on scene: WallpaperScene? = nil)", "store the region on"),
			("RotationBehaviour.swift", "func toggleSound()", "change the audio setting of")
		]

		for (file, declaration, writes) in writers {
			#expect(
				try Self.body(of: declaration, in: Self.source(named: file)).contains(Self.pageIsTheAnswer),
				"""
				`\(declaration)` no longer checks that the page on screen is the website it will \
				\(writes). A load that failed leaves those two disagreeing with nothing on screen \
				saying so, and a keyboard shortcut reaches this without passing the panel.
				"""
			)
		}

		let hasPage = try Self.body(
			of: "private var hasPage: Bool",
			in: Self.source(named: "DisplayPanel.swift")
		)

		#expect(
			hasPage.contains(Self.pageIsTheAnswer),
			"""
			The panel enables its writing controls on the display's answer rather than on the page in \
			its web view, so they look pressable on a column whose load failed.
			"""
		)
	}

	/**
	And muting is written in one place, so the guard above cannot be half-applied.

	It was two copies — one in the `Action` table, one in the panel's column — which is exactly what
	`toggleBrowsingMode` was pulled out of, and it failed the same way: the panel's copy checked there
	was a website, the shortcut's copy checked the same, and the guard the panel later needed could
	only ever be added to one of them. The flip lives on the scene now, beside `shouldPlaySound`, which
	is the property it writes.

	Matched on the flip rather than on `audio =`, which a website is also given when it is imported
	from the site catalogue — a starting value is not a toggle.
	*/
	@Test("Only the scene flips its own sound")
	func theAudioFlipHasOneHome() throws {
		let flip = try Regex("audio\\s*==\\s*\\.unmuted\\s*\\?")

		for (name, text) in try Self.sources() {
			let remaining = name == "RotationBehaviour.swift"
				? text.replacing(try Self.body(of: "func toggleSound()", in: text), with: "")
				: text

			for match in remaining.matches(of: flip) {
				Issue.record(
					"""
					\(name) carries its own copy of the mute flip. Call `WallpaperScene.toggleSound()`, \
					which is the copy that checks the page making the sound is the website being \
					written to. Around: \(Self.context(around: match.range, in: remaining))
					"""
				)
			}
		}
	}

	/**
	And the page and the answer are compared in one place.

	The test above reads a name, so a caller that writes the comparison out by hand satisfies it by
	saying nothing — an expression copied N times is either wrong N times or fixed in one of them, and
	the panel is the copy that was never written at all. Two existing ones came out on this test's first
	run. `AppState.applyLiveSettings` had it exactly, and reads the property now. `installContentView`
	had it with `loadedWebsiteID == nil ||` in front, which is not the same claim — it lets a display
	that has loaded nothing through, where the controls have to refuse one — so it keeps the `nil` and
	reads the property for the rest.

	Only the identity comparison. `loadedWebsite == website` in `reloadInPlace` and
	`loadedWebsite == scheduled(for:)` in `isUpToDate` compare the whole struct on purpose, because a
	page built from an older version of the same website has to be built again — a different question,
	with a different answer, and both argue for themselves where they are written.
	*/
	@Test("One expression asks whether the page is the answer")
	func thePageAndTheAnswerAreComparedOnce() throws {
		// Not `== nil`, which is "has this display loaded anything at all" and is a question about one
		// layer rather than a comparison of two — `installContentView` asks it beside the property and
		// says why.
		let byHand = try Regex("loadedWebsite(ID|\\?\\.id)\\s*(==|!=)(?!\\s*nil\\b)|(==|!=)\\s*[A-Za-z.]*loadedWebsite(ID|\\?\\.id)")

		for (name, text) in try Self.sources() {
			// Defining the question is not asking it, the way the tests above strike the readers they
			// are counting.
			let remaining = name == "WallpaperScene.swift"
				? text.replacing(try Self.body(of: "var \(Self.pageIsTheAnswer): Bool", in: text), with: "")
				: text

			for match in remaining.matches(of: byHand) {
				Issue.record(
					"""
					\(name) compares the page with the display's answer by hand. Read \
					`WallpaperScene.\(Self.pageIsTheAnswer)`, so the panel and the controls it draws \
					cannot come to two answers about one display. \
					Around: \(Self.context(around: match.range, in: remaining))
					"""
				)
			}
		}
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

	`currentWebsites` and `currentPlaylists` are in that list for the same reason and are the case it
	was drawn for: which wallpaper is up on a screen, and which list it is drawn from, are choices the
	user made about that screen. Unplug the monitor at night and it has to come back in the morning
	showing what it was showing. Which website is up does not stop being true when the cable comes out,
	it stops being visible — and there is nothing else for an unplug to do, because a display with no
	scene has no wallpaper to move anywhere.
	*/
	@Test("Unplugging clears Browsing Mode and leaves the preferences alone")
	func onlyTheStateIsPruned() throws {
		let rebuild = try Self.body(of: "func rebuildScenes()", in: Self.source(named: "AppState.swift"))

		#expect(
			rebuild.contains("browsingDisplays"),
			"Nothing clears Browsing Mode for a display whose scene is torn down, so an unplugged display keeps it for good."
		)

		for preference in ["disabledDisplays", "rotationModes", "rotationIntervals", "currentWebsites", "currentPlaylists"] {
			#expect(
				!rebuild.contains(preference),
				"`rebuildScenes` touches `\(preference)`. A display switched off, pinned, or showing a website it was given before it went away has to come back that way."
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

	The answer is `Defaults[.currentWebsites]` now, one entry per display, so neither is expressible —
	and the field itself is gone, which is what the first assertion below says. A payload that still
	carries the key decodes exactly as before, because a decoder ignores what it is not looking for.

	`display` is asserted with it, and it is the same claim one step out: a website belonged to a
	screen, so "which website is up" looked like a fact about the website. Neither field can come back
	without this going red.

	Then reads, because a field can be reintroduced under any name. An assignment is not a second home:
	the Shortcuts entity has a property of its own called `isCurrent` that it fills from the app.
	*/
	@Test("Nothing asks a website whether it is the current one")
	func nothingReadsTheFlagOnTheWebsite() throws {
		let website = try Self.source(named: "Website.swift")

		for field in ["isCurrent", "display"] {
			#expect(
				!website.contains("var \(field)"),
				"""
				`Website` carries `\(field)` again. A website does not belong to a screen and does not \
				know whether it is on one: both of those are one entry per display in `Defaults`, and a \
				slot on the website is a slot with room for one answer to a question that has one per \
				display.
				"""
			)
		}

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
	"Is this website up" is asked of the screens, not of what the screens were last told.

	`currentWebsites` is an intention and the scenes are the fact, and they are allowed to disagree —
	`add(_:to:)` ends in `makeCurrent(…, switchingDisplayOn: false)`, "marked, not shown", so adding a
	website moves the mark and changes no wallpaper. The entry also outlives both its display and its
	website: nothing prunes it when a monitor is unplugged, by design, and `remove(_:)` does not clear
	it either. All three were live on one Mac at once — the mark naming a website deleted weeks ago,
	`scheduled` resolving that ghost to the top of the order, and the one tick in the window drawn
	against the ghost while the website actually on screen had none.

	So the assertion that carries this is the negative one: `isShowing` must not consult the mark, by
	either spelling. `currentWebsiteID(on:)` is pinned by name two tests up, so renaming it fails there
	first rather than quietly loosening this — and `.values` is the original defect, which read the
	dictionary without going through that function at all.

	Two positives, and the second is not implied by the first. The scenes are one per attached display,
	which is what "the screens" means. `isSwitchedOff` is separate because a switched-off scene keeps
	its `website`: `rebuildScenes` assigns it before it asks whether the display is off, and `suspend()`
	does not clear it.
	*/
	@Test("What is on a screen is asked of the screens")
	func showingIsAskedOfTheLiveDisplays() throws {
		let controller = try Self.source(named: "WebsitesController.swift")
		let answer = try Self.body(of: "func isShowing(", in: controller)

		// Both, because they are one question. The tick says a website is on a screen and the rule says
		// removing what is on a screen switches it off, so the two disagreeing is a display left on and
		// substituted under — which is what the rule is for. Asserted together rather than in two tests,
		// so the pair cannot drift a spelling apart.
		for (name, body) in [
			("isShowing", answer),
			("switchOffDisplaysShowing", try Self.body(of: "func switchOffDisplaysShowing(", in: controller))
		] {
			#expect(
				!body.contains("currentWebsiteID"),
				"`\(name)` asks what the display was last told rather than what it is holding. The two diverge on purpose — adding a website marks it without showing it — and a mark naming a website that was deleted and never cleared makes the answer a ghost."
			)

			#expect(
				body.contains(".website"),
				"`\(name)` no longer reads the scene's own website, which is the fact the mark beside it is only the intention of."
			)
		}

		#expect(
			!answer.contains(".values"),
			"`isShowing` reads across every entry again, so a key left by a display that is not attached answers for one that is."
		)

		#expect(
			answer.contains("scenes"),
			"`isShowing` no longer asks the scenes, which are the only thing that knows what a screen resolved its mark into."
		)

		#expect(
			answer.contains("isSwitchedOff"),
			"`isShowing` no longer asks whether the display is switched off, and a switched-off scene still holds the website it was showing."
		)
	}

	/**
	Removing what a display is showing switches that display off, on every route that removes.

	Left alone, a deleted website leaves its display's entry naming nothing, and `showingPosition`
	reads nothing-named as position zero — so the screen moves to whatever sorts first in whatever list
	it falls back to. That is the app choosing a wallpaper, in the middle of an act that was about
	something else, and indistinguishable from a rotation tick. Off instead: the app does not pick a
	replacement, because there is no replacement the user asked for.

	Three routes, and the reason this is a list rather than one assertion is that two of them do not go
	through the third. A website leaves the list by being deleted, by its playlist being deleted, or by
	Clear All Website Data, and only the first is `remove(_:)`. A rule enforced on the route somebody
	happened to be looking at is the defect this suite keeps finding.

	`switchOffDisplaysShowing` where the websites are known and `switchOffEveryDisplay` where the answer
	is all of them.

	**Restore All Settings was a fourth row here and is not one now**, which is a change in what Restore
	does rather than a hole in this rule. It emptied the domain, `playlists` was in the domain, so it
	deleted every website and owed the rule an answer. It preserves the websites now — the rule is about
	removing what a screen is showing, and it removes nothing. What each display shows goes back to the
	default playlist's first website, out of a list that is still there, which is a restored setting and
	not a substitution. Put the row back the day Restore deletes a website again.
	*/
	@Test("Every route that deletes a website switches off the displays showing it")
	func everyDeletionSwitchesTheDisplayOff() throws {
		let routes = [
			("WebsitesController.swift", "func remove(_ website: Website)", "switchOffDisplaysShowing", "a website deleted from its row, or by the Shortcuts action"),
			("WebsitesScreen.swift", "private func delete(_ playlist: Playlist)", "switchOffDisplaysShowing", "a playlist deleted with websites in it"),
			("WebsitesController.swift", "func removeEverything()", "switchOffEveryDisplay", "Clear All Website Data")
		]

		for (file, declaration, verb, what) in routes {
			#expect(
				try Self.body(of: declaration, in: Self.source(named: file)).contains(verb),
				"`\(declaration)` in \(file) takes a website out of the list without switching off the displays showing it, so \(what) moves those screens on to whatever sorts first."
			)
		}
	}

	/**
	And the two methods that only ever add do not.

	The trap is the same shape `PlaylistMigrationTests` guards the install flag against, one line down.
	`installDefaultPlaylist` is how the shipped websites get into the list, so anything about websites
	and displays looks like it belongs in there — and its one caller is the Advanced pane's Add the
	Default Playlist, which deletes nothing, while below it `prepareWebsiteStorage` is what every launch
	runs. Folded into either, the app comes up dark on every run, for everybody, and a fresh install
	cannot tell the difference.

	Asserted on both bodies rather than on the one that would hurt more, so moving the line fails rather
	than only adding it in the wrong place.
	*/
	@Test("Installing the shipped websites switches nothing off")
	func theInstallPathSwitchesNothingOff() throws {
		let controller = try Self.source(named: "WebsitesController.swift")

		for declaration in ["func prepareWebsiteStorage()", "func installDefaultPlaylist()"] {
			let body = try Self.body(of: declaration, in: controller)

			#expect(!body.isEmpty)

			#expect(
				!body.contains("switchOff"),
				"`\(declaration)` switches displays off. Every launch runs it through `prepareWebsiteStorage`, and the Advanced pane\'s Add the Default Playlist runs it without deleting anything — so Nifro comes up with every screen dark."
			)
		}
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
				.contains("wakeDisplay"),
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
	A failed load is said somewhere a user will see it.

	The other half of the test above, and the reason that one was only half a fix. Splitting the slot
	made the store correct — each display's failure kept under its own key, no writer able to erase
	another's — and left it read by one surface: the tooltip on the menu bar icon, which appears only
	if somebody rests a pointer on a glyph that gives no sign of having anything to say. A wallpaper
	whose URL starts answering with an error therefore keeps drawing the last page that worked, on the
	desktop and in the panel's picture alike, while the column names the website as though nothing had
	happened.

	The column is where it belongs because the column is per display and so is the failure. Asserted as
	"the model asks for this display's error and the view draws it", the two ends of one field, because
	either on its own is the state this had for six releases: a value carried and shown by nothing, or
	a view with nothing to show.
	*/
	@Test("The panel reads the failure recorded for its own display")
	func theColumnCanSayAPageDidNotLoad() throws {
		let model = try Self.source(named: "DisplayPanelModel.swift")

		#expect(
			try Self.body(of: "private func column(for scene: WallpaperScene", in: model).contains("webViewError(on:"),
			"A column is built without asking whether this display's page loaded, so a page that stopped arriving is reported in a tooltip and nowhere else."
		)

		#expect(
			try Self.source(named: "DisplayPanel.swift").contains("column.failure"),
			"The column carries the failure and nothing draws it, which is the same as not carrying it."
		)
	}

	/**
	What the display is showing is one rectangle, not one per reader.

	The same shape as `canRotate` above, in geometry. Under a framed region the wallpaper's web view is
	laid out as the whole page several times larger than the window, and `PageView` clips it — so the
	view's bounds and the part of it on screen are two different rectangles, and everything that
	photographs that view has to say which one it means. Two things do. The menu bar band worked the
	answer out for itself; the panel's thumbnail said nothing, which `WKSnapshotConfiguration` reads as
	the bounds, so the column drew an entire website shrunk into 260 points while the display showed
	one slice of it.

	One derivation on the scene, `wallpaperRect`, over one pure function in `Geometry`, which is where
	the numbers are actually tested. What this adds is that both readers go through it — a second
	`case .live(let zoom?)` appearing anywhere else is the defect coming back, whatever it computes.
	*/
	@Test("Everything that photographs the wallpaper asks for the same rectangle")
	func bothSnapshotsShareOneRectangle() throws {
		#expect(
			try Self.body(of: "func snapshot() async -> NSImage?", in: Self.source(named: "WallpaperScene.swift")).contains("wallpaperRect"),
			"The panel's thumbnail does not say what part of the web view it wants, so it gets the bounds — which under a framed region is the whole page, not what the display is showing."
		)

		#expect(
			try Self.body(of: "private func topStripOfWallpaper(height: Double)", in: Self.source(named: "MenuBarBand.swift")).contains("wallpaperRect"),
			"The band works out what is on screen for itself again. That expression is `wallpaperRect`, and a second copy of it is how the thumbnail came to have none."
		)
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

	/**
	The menu bar icon says whether there is a wallpaper anywhere, and the Shortcuts action says the same.

	Both asked `AppState.isEnabled`, which is the app-wide switch and nothing per display, and both are
	the single answer a whole Mac gets — so this is the scope defect this suite is about, in the one
	place where "the app-wide question" was the only question anybody thought there was. On a
	single-display Mac, switching that display off from the panel took the wallpaper, the menu bar band
	and both timers, and left the icon drawn as fully on with a tooltip naming a website, while
	`GetEnabledStateIntent` answered `true` to a script that had no other way to find out. Nothing was
	wrong with `isEnabled`: none of the three things it is made of is per display.

	Which relaunches into the same state. Both switches are on disk now — `disabledDisplays` always
	was, and `isManuallyDisabled` was the one member of its class without storage, so the only "off"
	that survived a quit was exactly the one the icon refused to draw.

	One expression, `isShowingWallpaper`, and both readers named here. It asks `isSwitchedOff` rather
	than the two switches, so a third thing that comes to mean off reaches the icon and the intent by
	joining that predicate — which is `SwitchedOffTests`'s subject, and why the first assertion is the
	only one about the inside of it here.
	*/
	@Test("The icon and the Shortcuts answer ask about the displays")
	func theIconAndTheIntentAskAboutTheDisplays() throws {
		let state = try Self.source(named: "AppState.swift")

		#expect(
			try Self.body(of: "var isShowingWallpaper: Bool", in: state).contains("isSwitchedOff"),
			"`isShowingWallpaper` works out what \"off\" means for itself again, so the per-display half can drop out of it the way it already did once."
		)

		for (file, declaration, what) in [
			("AppState.swift", "func refreshStatusItem()", "The menu bar icon"),
			("Intents.swift", "func perform() async throws -> some IntentResult & ReturnsValue<Bool>", "The Shortcuts action")
		] {
			#expect(
				try Self.body(of: declaration, in: Self.source(named: file)).contains("isShowingWallpaper"),
				"\(what) answers \"is Nifro on\" from something other than `isShowingWallpaper`, which is how it came to say yes on a Mac with every display switched off."
			)
		}

		// One writer, for the reason the tooltip has one: two places dimming the icon is two places
		// deciding what "off" means, and the second one is where the per-display half goes missing.
		let owner = try Self.body(of: "func refreshStatusItem()", in: state)

		for (name, text) in try Self.sources() {
			let outside = name == "AppState.swift" ? text.replacing(owner, with: "") : text

			for match in outside.matches(of: try Regex("appearsDisabled")) {
				Issue.record(
					"""
					\(name) dims the menu bar icon directly. Change what `refreshStatusItem()` answers \
					and call it, so the icon cannot be drawn from a narrower reading of "off" than the \
					one the wallpapers obey. Around: \(Self.context(around: match.range, in: outside))
					"""
				)
			}
		}
	}

	/**
	The other Shortcuts action, which asked the same question one layer up.

	`GetEnabledStateIntent` was half of a pair and the half that got fixed. `GetCurrentWebsiteIntent`
	reads `AppState.currentWebsite`, and that read `primaryScene.website` — the website the main
	display was *told* to show, which is not the website on it. Both ways they part are reachable and
	neither leaves the script anything to check against.

	A swap that fails moves the answer and leaves the page, so with the network down this named the
	website that never arrived while the desktop kept the one that had — for as long as the network
	stayed down. And a main display switched off keeps its website, so this named a page on a black
	screen; with a second display still showing something, `isShowingWallpaper` is true, so the pair
	agreed and a script asking both was told nothing was wrong.

	`loadedWebsite`, the page, and the switched-off case falls out of it rather than being asked for:
	`suspend` releases the web view and `releaseWebView` clears that property, so a display with
	nothing on it has nothing to name. Pinned on the property rather than on the intent, because
	`currentWebsite` exists to have exactly one reader and the reader is the thing that would be
	rewritten.

	Not `hasLoadedItsWebsite`, which is the neighbouring predicate and belongs to the controls: those
	refuse when the two part because they write to the website. A query writes nothing, so the page
	that is up is the answer, and `nil` there would be a refusal to say what the user is looking at.
	*/
	@Test("The Shortcuts query names the page, not the website the display was told to show")
	func theCurrentWebsiteQueryNamesThePage() throws {
		let state = try Self.source(named: "AppState.swift")

		#expect(
			try Self.body(of: "var currentWebsite: Website?", in: state).contains("loadedWebsite"),
			"`currentWebsite` answers from the display's mark again, so a failed swap and a switched-off main display both name a website that is not on any screen."
		)

		#expect(
			try !Self.body(of: "var currentWebsite: Website?", in: state).contains(".website"),
			"`currentWebsite` reads the mark alongside the page, which is the two-layer answer this replaced rather than a narrowing of it."
		)

		// The one reader, so the property cannot be quietly stepped around by asking the scene
		// directly — which is how the app-wide answer this replaced came to be read in four places.
		for (name, text) in try Self.sources() where name == "Intents.swift" {
			#expect(
				!text.contains("primaryScene"),
				"An intent reaches past `currentWebsite` to the scene, so it answers from whichever layer that line happened to pick. `primaryScene` also rebuilds the scene list as a side effect, which an intent is not the place to trigger."
			)
		}
	}
}
