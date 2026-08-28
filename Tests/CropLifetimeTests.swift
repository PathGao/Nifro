import Foundation
import Testing

/**
The guardrail on "framing always ends".

Choosing a region puts the wallpaper window at `.floating`, at full opacity, taking clicks, and puts
one overlay inside it. The overlay is the only thing that can call `onFinish`, and `onFinish` is the
only thing that puts any of that back — so an overlay that goes away without being asked leaves a
wallpaper pinned above every other window with `isSelectingCrop` still true, which also refuses every
later attempt to frame anything. Quitting was the way out.

It went away because it is a subview of `window.contentView`, and that slot is written from
`applyContent` for reasons that have nothing to do with framing: `releaseWebView` swaps in a fresh web
view on every screen lock, battery transition, Disable and per-display power button, and `tearDown`
empties it when the framed display is unplugged. Both were fixed once by guarding a caller —
`installContentView` refuses while framing, `applyOpacity` leaves a framing window alone — and both
times the next writer along had no guard, because a guard is something a writer has to remember.

So the ending is not a guard. `CropSelectionView` ends the mode when it leaves the window, whoever
took it out and for whatever reason, and these two assertions are the shape that makes that hold: one
ending, and it fires on a nil window. Shape rather than behaviour for the reason `SwitchedOffTests`
gives at length — the SwiftPM target next door compiles nothing from `Zoom`, `Wallpaper` or `App`, and
this path needs an AppKit window to be taken away from it. What was checked by hand is in the pull
request.
*/
@Suite("A crop that is interrupted still ends")
struct CropLifetimeTests {
	private static let overlay = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "Nifro/Zoom/CropSelectionView.swift")

	/**
	The file with its prose taken out. It argues for itself at length and the argument names the very
	thing being looked for.
	*/
	private static func source() throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(contentsOf: overlay, encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	@Test("There is one ending, and it can only run once")
	func oneEnding() throws {
		let source = try Self.source()

		// Anchored on `onFinish`, which `CropSelection.swift` assigns and this file calls, rather than on
		// the name of whatever private helper does the clearing: a rule written against a local name
		// goes red on a rename with the behaviour untouched, and this one has to survive being tidied.
		//
		// Calling the handler directly is what makes a second ending possible — it removes the view from
		// the window, and that removal is itself an ending. So: never called through the optional, and
		// cleared somewhere before it is called.
		#expect(!source.contains("onFinish?("))
		#expect(
			source.contains(try Regex("onFinish\\s*=\\s*nil")),
			"Nothing clears the handler, so an ending can arrive twice"
		)
	}

	@Test("Leaving the window ends the mode")
	func leavingTheWindowEnds() throws {
		let source = try Self.source()

		// `viewDidMoveToWindow` is AppKit's name, not ours — a rename is a compile error rather than a
		// silent change, which is what makes it a safe thing to anchor on.
		let body = try #require(source.components(separatedBy: "override func viewDidMoveToWindow()").last)

		// The whole point: no writer of `window.contentView` has to know framing exists. The mode ends
		// on the absent window, whoever took it away.
		#expect(body.contains("guard let window else"))
	}
}
