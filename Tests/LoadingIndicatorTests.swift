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
	The two pulses run on different clocks — SwiftUI's and CoreAnimation's — so they cannot be in
	phase and nothing here pretends otherwise. What they can share is the rate, and a rate they share
	by both reading one constant cannot be half-changed.
	*/
	@Test("Both pulses breathe at the same rate")
	func oneCadence() throws {
		let menuBar = try Self.stripComments(Self.source("Nifro/Support/MenuSupport.swift"))
		let panel = try Self.stripComments(Self.source("Nifro/Screens/DisplayPanel.swift"))

		#expect(menuBar.contains("pulse.duration = WallpaperScene.loadingPulseDuration"))
		#expect(panel.contains(".easeInOut(duration: WallpaperScene.loadingPulseDuration)"))
	}
}
