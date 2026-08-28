import Foundation
import Testing

@testable import NifroLogic

/**
The guardrail on "exactly one website is current per display in use".

`currentFlags` keeps that true when the app moves the mark itself, and it is tested next door. This is
about the other way the mark moves: not through `makeCurrent` at all. A website's "Show on" is a
`Binding` into the stored list, so changing it is a plain list write that carries the website's mark
across to the new display with it. The display it left is then unmarked and the display it arrived on
has two marks, and the visible result is that the display the user *named* does not change: a tie is
broken by list order, so the website already on that screen keeps it and the one just sent there is
ignored. Measured on two displays — the built-in never fetched the website it was given, the monitor
switched to a third website nobody asked for, and the websites window drew two ticks.

Only half of the invariant was being enforced, and it is the half whose failure is loud. A display
with no mark reads as "never started", so rotation begins again at the top of its list every time and
the display sits on its first website for good — that got noticed and fixed. A display with two marks
changes nothing visibly except which of them wins, so it did not.

Both halves are one function over plain values for the same reason `currentFlags` is: the failure only
exists when there are two displays, and reasoning about two displays on a one-display machine is what
wrote it wrong the first time.

The last test here is a different shape, and says so where it stands: the other defect this file was
opened for has no arithmetic in it, only a question of where an answer lives.
*/
@Suite("Exactly one website is current per display")
struct CurrentMarkTests {
	/**
	One website, as much of it as the mark arithmetic can see.

	Written out as a triple rather than three parallel arrays at every call site, because the middle
	one and the last one are both `Bool` and a test that swaps them silently still passes.
	*/
	private struct Entry {
		let display: String?
		let isCurrent: Bool
		let wasAlreadyCurrentHere: Bool
	}

	private static func repaired(_ entries: [Entry]) -> [Bool] {
		repairedCurrentFlags(
			displays: entries.map(\.display),
			isCurrent: entries.map(\.isCurrent),
			wasAlreadyCurrentHere: entries.map(\.wasAlreadyCurrentHere)
		)
	}

	/**
	The invariant itself, asked of an answer rather than of a case.

	Every test below states what it expects exactly, which pins the tie-breaks. This one pins the thing
	the tie-breaks exist to serve, so a future rule that resolves a tie some other way still has to
	leave one mark per display.
	*/
	private static func hasOneMarkPerDisplay(_ entries: [Entry], _ flags: [Bool]) -> Bool {
		Set(entries.map(\.display)).allSatisfy { display in
			zip(entries, flags).count { $0.display == display && $1 } == 1
		}
	}

	/**
	The measured case: "Show on" moved a showing website to a display that already had one.

	The arrival wins. It is the only answer that does what the person asked for — they named the
	built-in display, so the built-in display shows it — and the display it left is not left blank.
	*/
	@Test("A website moved to another display arrives showing, and the one that was there stands down")
	func aMoveTakesTheMarkWithIt() {
		let entries = [
			// Was showing on the built-in and had no part in this.
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: true),
			// Just sent to the built-in from the monitor, still carrying the mark it held there.
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: false),
			// The monitor's other website, which now has to hold its display's mark.
			Entry(display: "monitor", isCurrent: false, wasAlreadyCurrentHere: false)
		]

		let flags = Self.repaired(entries)

		#expect(flags == [false, true, true])
		#expect(Self.hasOneMarkPerDisplay(entries, flags))
	}

	/**
	Moving a website that was not showing changes nothing about what is.

	The other half of the case above, and the one that says the rule is about the mark rather than
	about the move: a display only re-decides when something arrives claiming it.
	*/
	@Test("Moving a website that was not showing leaves both displays alone")
	func aQuietMoveDisturbsNothing() {
		let entries = [
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: true),
			// Arrived from the monitor unmarked, because it was not the one showing there.
			Entry(display: "built-in", isCurrent: false, wasAlreadyCurrentHere: false),
			Entry(display: "monitor", isCurrent: true, wasAlreadyCurrentHere: true)
		]

		let flags = Self.repaired(entries)

		#expect(flags == entries.map(\.isCurrent))
		#expect(Self.hasOneMarkPerDisplay(entries, flags))
	}

	/**
	Two marks that both predate the change are a stored list that was already wrong.

	Nothing arrived, so there is no claim to prefer, and the first in list order wins — which is the
	one the app was already showing, so repairing an old mess does not change anybody's wallpaper on
	the launch that finds it.
	*/
	@Test("An old duplicate resolves to the website that was already on screen")
	func anOldDuplicateKeepsTheScreen() {
		let entries = [
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: true),
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: true)
		]

		let flags = Self.repaired(entries)

		#expect(flags == [true, false])
		#expect(Self.hasOneMarkPerDisplay(entries, flags))
	}

	/**
	The half that was already enforced, kept enforced.
	*/
	@Test("A display with no mark gets one rather than starting from the beginning every time")
	func anUnmarkedDisplayIsGivenAMark() {
		let entries = [
			Entry(display: "built-in", isCurrent: false, wasAlreadyCurrentHere: false),
			Entry(display: "built-in", isCurrent: false, wasAlreadyCurrentHere: false)
		]

		let flags = Self.repaired(entries)

		#expect(flags == [true, false])
		#expect(Self.hasOneMarkPerDisplay(entries, flags))
	}

	/**
	A list that is already right is returned unchanged.

	Not a nicety. The repair runs from the publisher on the stored list and writes back through it, so
	a repair that "fixes" a correct list writes on every change, and every write is another change.
	*/
	@Test("A list that already holds the invariant is left exactly as it is")
	func nothingIsRewrittenWithoutCause() {
		let entries = [
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: true),
			Entry(display: "built-in", isCurrent: false, wasAlreadyCurrentHere: false),
			Entry(display: nil, isCurrent: true, wasAlreadyCurrentHere: true),
			Entry(display: "monitor", isCurrent: true, wasAlreadyCurrentHere: true)
		]

		#expect(Self.repaired(entries) == entries.map(\.isCurrent))
	}

	/**
	Repairing a repaired list changes nothing, so the write-back cannot chase its own tail.

	The second pass is given the answer as its own starting point with nothing arriving, which is
	exactly what the publisher hands back when the repair writes to the list.
	*/
	@Test("The repair settles in one pass")
	func theRepairIsIdempotent() {
		let entries = [
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: true),
			Entry(display: "built-in", isCurrent: true, wasAlreadyCurrentHere: false),
			Entry(display: nil, isCurrent: false, wasAlreadyCurrentHere: false)
		]

		let once = Self.repaired(entries)

		let again = Self.repaired(
			zip(entries, once).map { Entry(display: $0.display, isCurrent: $1, wasAlreadyCurrentHere: $1) }
		)

		#expect(again == once)
	}

	/**
	Websites following the display named in Settings are one display, not none.

	`nil` is a display like any other here, and the same list holds both kinds. It is the case the
	`Set` in the repair has to key on rather than skip.
	*/
	@Test("The default display is a display")
	func theDefaultDisplayIsRepairedToo() {
		let entries = [
			Entry(display: nil, isCurrent: true, wasAlreadyCurrentHere: true),
			Entry(display: nil, isCurrent: true, wasAlreadyCurrentHere: false),
			Entry(display: "monitor", isCurrent: false, wasAlreadyCurrentHere: false)
		]

		let flags = Self.repaired(entries)

		#expect(flags == [false, true, true])
		#expect(Self.hasOneMarkPerDisplay(entries, flags))
	}

	/**
	Stepping is one answer, in the one place every route to it passes through.

	The other defect: pressing Next over a display that is switched off moved that display's mark under
	a dark screen and asked for nothing, so pressing it a few times looking for a reaction left the
	display to come back later on a website nobody chose. The panel's own two buttons had always
	handled it — stepping a switched-off display is how you wake it — and the keyboard shortcut, the
	`nifro://` commands and the Shortcuts action reached the same verb by another door and skipped it.
	One verb, one display, two answers depending on which control was pressed.

	Shape rather than behaviour, and the reason is the same one `SwitchedOffTests` gives at length: the
	SwiftPM target compiles ten files of pure logic and none of `App`, so there is no `AppState` here to
	switch a display off on and no scene to ask. What can be checked from here is the property that
	makes the fix hold tomorrow — that the answer is not written at a call site, where the next route
	added will not inherit it. The behaviour was observed instead, on a running unsigned build.
	*/
	@Test("Every route to Next and Previous meets the switch in one place")
	func steppingWakesADisplayWhereverItIsAskedFrom() throws {
		let controller = try Self.source(named: "WebsitesController.swift")

		#expect(
			try Self.body(of: "func makeCurrent(", in: controller).contains("setDisplayEnabled"),
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
	One of the app's Swift files, with its prose taken out.

	Every one of these files argues for itself at length and the arguments name the very things the
	assertion looks for, so matching against the comments would pass on an explanation of a fix that
	is no longer there.
	*/
	private static func source(named name: String) throws -> String {
		let root = URL(filePath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Nifro")

		guard
			let found = FileManager.default
				.enumerator(at: root, includingPropertiesForKeys: nil)?
				.compactMap({ $0 as? URL })
				.first(where: { $0.lastPathComponent == name })
		else {
			Issue.record("\(name) is gone from Nifro/.")
			return ""
		}

		return try String(contentsOf: found, encoding: .utf8)
			.replacing(try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines(), with: "")
			.replacing(try Regex("//[^\\n]*"), with: "")
	}

	/**
	The body of a declaration, from its opening brace to the brace that closes it.

	Counted rather than matched, because every body here contains braces of its own — a `guard … else`,
	a closure — and a match that stops at the first `}` would read a guard clause as the whole function
	and pass on whatever came after it.
	*/
	private static func body(of declaration: String, in source: String) throws -> String {
		guard
			let start = source.range(of: declaration),
			let open = source[start.lowerBound...].firstIndex(of: "{")
		else {
			Issue.record("`\(declaration)` is no longer written that way, so this test is reading nothing.")
			return ""
		}

		var depth = 0

		for index in source.indices[open...] {
			depth += source[index] == "{" ? 1 : (source[index] == "}" ? -1 : 0)

			if depth == 0, source[index] == "}" {
				return String(source[open...index])
			}
		}

		Issue.record("`\(declaration)`'s body is unbalanced.")
		return ""
	}
}
