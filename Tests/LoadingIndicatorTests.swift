import Foundation
import Testing

/**
The guardrail on "the menu bar icon pulses while a page is on its way".

`WallpaperScene.isLoading` is a computed property, so nothing is published when it moves. The menu
bar icon is a `CABasicAnimation` that has to be added and removed by somebody. Bridging the two is
the whole of this feature, and there are two ways to do it: call the bridge from every place a load
starts or ends, or hang it off the stored properties the computed one reads. The first is a list, and
this feature already died once of a list — an `AppState.loadingScenes` counter, incremented and
decremented at each call site, which on the plain-load path took two increments for one decrement and
left the icon pulsing until the app was quit.

So the assertions below are on the shape of the source rather than on behaviour, and it is worth
being plain about why behaviour is not on offer: the SwiftPM target next door compiles nine files out
of `Sites` and `Support`, none of `Wallpaper`, none of `App`, and it depends on neither AppKit's
status bar nor `Defaults`. There is no `WallpaperScene` to instantiate from here, and no status item
to sample. The observed check is a running build with the animation read off the status item's layer;
that is a thing a person does, not a thing `swift test` does.

What a person cannot do is notice, six months from now, that the load path they just added writes
`hasRevealedPage` without going through the observer — because it will still compile, still pass
review, and still work every way except the one nobody looks at. That is what these catch.
*/
@Suite("The loading pulse cannot be forgotten")
struct LoadingIndicatorTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func source(_ path: String) throws -> String {
		try String(contentsOf: root.appending(path: path), encoding: .utf8)
	}

	/**
	The same file with its prose taken out.

	Every one of these files argues for itself at length, and the arguments name the very things the
	assertions look for — the counter that was deleted, the numbers that are no longer written out.
	Matching against the comments would fail on the explanation of why the code is right.
	*/
	private static func stripComments(_ source: String) throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")
		return source.replacing(block, with: "").replacing(line, with: "")
	}

	private static func scene() throws -> String {
		try stripComments(source("Nifro/Wallpaper/WallpaperScene.swift"))
	}

	/**
	The stored properties `isLoading` is worked out from, read off `isLoading` itself.

	Parsed rather than written down here, so a fourth input added to that expression tomorrow is in
	the test below by existing. A list of three names typed into this file would be the same kind of
	list the observers exist to avoid.
	*/
	private static func inputsOfIsLoading() throws -> [String] {
		let source = try scene()

		guard let body = source.firstMatch(of: try Regex("var\\s+isLoading\\s*:\\s*Bool\\s*\\{([^}]*)\\}")) else {
			Issue.record("`WallpaperScene.isLoading` is no longer a computed `Bool` this test can read.")
			return []
		}

		let identifier = try Regex("[A-Za-z_][A-Za-z0-9_]*")
		let notProperties: Set<String> = ["nil", "true", "false"]

		var found: [String] = []

		for match in String(body[1].substring!).matches(of: identifier) {
			let name = String(match.output[0].substring!)

			guard
				!notProperties.contains(name),
				!found.contains(name)
			else {
				continue
			}

			found.append(name)
		}

		return found
	}

	@Test("Every input of `isLoading` tells the menu bar itself")
	func everyInputIsObserved() throws {
		let source = try Self.scene()
		let inputs = try Self.inputsOfIsLoading()

		#expect(inputs.count >= 2, "Parsed \(inputs) out of `isLoading`, which is too few to be the real expression.")

		for input in inputs {
			let observed = try Regex("var\\s+\(input)\\b[^\\n{]*\\{\\s*didSet\\s*\\{\\s*loadingStateChanged\\(\\)\\s*\\}\\s*\\}")

			#expect(
				source.contains(observed),
				"""
				`\(input)` feeds `isLoading` but does not carry `didSet { loadingStateChanged() }`. \
				Whoever writes it next can then start or end a load without the menu bar icon hearing \
				about it, and nothing will say so.
				"""
			)
		}
	}

	@Test("Nothing calls the bridge by hand")
	func theBridgeIsOnlyReachedThroughTheObservers() throws {
		let source = try Self.scene()
		let mentions = source.matches(of: try Regex("loadingStateChanged\\(\\)")).count
		let declaration = source.matches(of: try Regex("func\\s+loadingStateChanged\\(\\)")).count
		let calls = mentions - declaration
		let inputs = try Self.inputsOfIsLoading()

		// One per observer and no more. A hand-written call is a call site that can be left out of the
		// next one, which is the failure this whole arrangement is built to make impossible.
		#expect(
			calls == inputs.count,
			"`loadingStateChanged()` is called \(calls) times for \(inputs.count) observed inputs — a call by hand has crept in."
		)
	}

	@Test("The counter that pulsed forever has not come back")
	func noTally() throws {
		let source = try Self.stripComments(Self.source("Nifro/App/AppState.swift"))

		#expect(!source.contains("loadingScenes"))
		#expect(!source.contains("beginLoadingIndicator"))
		#expect(!source.contains("endLoadingIndicator"))

		// Asked of the scenes at the moment of asking, so there is nothing kept that could drift.
		#expect(source.contains("scenes.contains(where: \\.isLoading)"))
	}

	/**
	Two indicators, and only one of them is the app's to pace.

	The menu bar icon has no stock equivalent — nothing system-drawn breathes inside a status item — so
	it keeps its CoreAnimation pulse and keeps reading the one constant that sets its rate.

	The panel's was a second hand-rolled pulse: a tinted pill behind the website chooser, animated on
	that same constant so the two would read as one thing happening rather than two. It is a stock
	`ProgressView` now, which paces itself. What that gives up is the shared cadence, so this asserts
	the panel paces nothing by hand rather than that it paces it the same way — and the constant, which
	one caller could otherwise quietly outlive, stays guarded by the half that still reads it.
	*/
	@Test("The menu bar paces its own pulse, and the panel paces nothing")
	func oneCadence() throws {
		let menuBar = try Self.stripComments(Self.source("Nifro/Support/MenuSupport.swift"))
		let panel = try Self.stripComments(Self.source("Nifro/Screens/DisplayPanel.swift"))

		#expect(menuBar.contains("pulse.duration = WallpaperScene.loadingPulseDuration"))

		#expect(panel.contains("ProgressView()"))
		#expect(!panel.contains("phaseAnimator"))
		#expect(!panel.contains("loadingPulseDuration"))
	}

	/**
	The swap says the page it adopted has arrived.

	`isLoading` is computed from `pendingWebView` and `hasRevealedPage`, and the swap clears only the
	first. The second is set by `WebViewController.pageDidSettle`, which guards on the web view being
	the live one — and a replacement finishes loading while it is still the pending one. So the only
	thing that can say a swapped-in page is up is the swap itself.

	Asserted on `adopt`, because that is the moment the page becomes the one on screen, and against
	`revealPage` by name rather than against `hasRevealedPage`: the flag is `private(set)` and reveal
	is more than the flag. It samples the menu bar band off the page it has just decided is up, so a
	swap that set the flag alone would stop the pulse and leave the band on the previous page's colour.
	*/
	@Test("A swapped-in page is revealed by the swap")
	func adoptingRevealsThePage() throws {
		let source = try Self.source("Nifro/Wallpaper/SwapLoading.swift")

		// Sliced rather than brace-matched: `adopt` is the last method in its extension, so the next
		// declaration is the end of it, and a slice that is too long can only make this pass by
		// accident on a `revealPage` somewhere else in the file — which there is not, and which the
		// second expectation below rules out anyway.
		guard let start = source.range(of: "private func adopt(_ replacement: SSWebView)") else {
			Issue.record("`adopt` is no longer written that way, so this test is reading nothing.")
			return
		}

		let body = String(source[start.upperBound...])

		#expect(
			source.components(separatedBy: "revealPage()").count == 2,
			"More than one place in `SwapLoading` reveals the page, so the slice below no longer says which one does."
		)

		#expect(
			body.contains("revealPage()"),
			"`adopt` does not reveal the page it just put on screen, so `isLoading` stays true until the backstop from the previous load fires — and the menu bar band keeps the colour it took off the page before this one."
		)
	}

	/**
	The panel reports a load and does nothing else with it.

	A load used to disable the whole column, on the argument that every control in it would be aimed
	at a display already on its way somewhere, and that it "lasts a few seconds and lets go by itself,
	so nothing has to be exempt from it". A page that never answers holds it for the whole of
	`WallpaperScene.loadTimeout` instead, and the website chooser — the control that would take the
	display off the page that is stuck — was disabled with the rest. The way out of a stuck load was
	the gallery in another window.

	Counted rather than matched against the spelling of any one control. `disabled(column.isLoading)`
	was the shape it took the first time; asserting that exact call back out would pass on a ternary,
	on an `opacity`, on a guard inside a button's action. One use of `column.isLoading` in the file is
	the whole rule: the spinner beside the chooser. Anything that consults a load to decide whether a
	control may act has to add a second.

	Comments stripped for the reason `stripComments` gives — the block above the column argues this,
	names it, and would otherwise be the second use.
	*/
	@Test("A load is reported to the panel and does not disable it")
	func aLoadDoesNotTrapTheColumn() throws {
		let source = try Self.stripComments(Self.source("Nifro/Screens/DisplayPanel.swift"))

		#expect(
			source.components(separatedBy: "column.isLoading").count == 2,
			"`column.isLoading` is read more than once in the panel. The second reader is deciding whether some control may act, which traps the column behind a page that never answers — the fault this file's chooser spinner replaced."
		)
	}
}
