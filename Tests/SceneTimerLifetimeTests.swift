import Foundation
import Testing

/**
The guardrail on "a scene's clocks stop when the scene does".

A `WallpaperScene` holds a repeating timer for each thing it does on a cadence — the page reload, the
minute tick that carries rotation and the schedule, and now the sample that keeps the menu bar band
matching a page which changes without navigating. Every one of them is armed once per display and
then runs until something takes it down, and there are exactly two places that take one down for
good: `suspend()`, which is Disable and the battery rule and a locked screen, and `tearDown()`, which
is a display going away.

Both of those are written as a list, and a list is the shape this repository keeps finding a defect
in: a mechanism is built, and one member never joins. `suspend()`'s own doc argues for being one
method rather than four lines at the call site *because* the next thing a scene starts will have to
be stopped here too — which is a promise nothing was keeping. A timer left out of it is not a crash
and not a visible fault. It is a display switched off whose wallpaper is gone and whose clock is
still firing into it: for the band, a sample taken off a page nobody can see, which is precisely the
symptom `SwitchedOffTests` was written after.

So the list is not written down here either. The timers are parsed out of `WallpaperScene` and each
one is required in both methods, which makes the fourth timer a member of this test by existing
rather than by somebody remembering to add it.

Shape rather than behaviour, for the reason the suites either side of this one spell out: the SwiftPM
target next door compiles eleven pure files out of `Sites` and `Support`, none of `Wallpaper`,
`Visibility` or `App`. `WallpaperScene` needs AppKit windows, WebKit and `Defaults`, so there is
nothing here to build and nothing to suspend. That is a missing seam rather than an unrunnable claim,
and it is worth saying which: the honest fix would be a scene whose clocks can be started and stopped
without a window server, and this test is the cheap stand-in until there is one. It also cannot see a
timer stored somewhere other than a `Timer?` property on the scene — a `Task` that sleeps in a loop
is a clock this would not recognise.

`Timer` and `invalidate` are Foundation's names. Nothing this repository could rename turns one of
these red without the behaviour changing with it.
*/
@Suite("Every clock a scene starts is stopped when the scene stops")
struct SceneTimerLifetimeTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The file with its prose taken out.

	Each timer argues for itself at length directly above or below where it is declared and armed, and
	those arguments name the other timers while comparing themselves to them. Counted with the prose
	left in, a scene would satisfy this test by talking about a timer it had stopped stopping.
	*/
	private static func scene() throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(
			contentsOf: root.appending(path: "Nifro/Wallpaper/WallpaperScene.swift"),
			encoding: .utf8
		)
		.replacing(block, with: "")
		.replacing(line, with: "")
	}

	/**
	The body of a declaration, from its opening brace to the brace that closes it.

	Counted rather than matched with a regex, because both bodies below hold braces of their own — a
	closure, a `guard … else { … }`. A regex stopping at the first `}` would read the first statement
	as the whole method and pass on whatever came after it.
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

	@Test("Suspending and tearing down each stop every timer the scene holds")
	func neitherExitLeavesAClockRunning() throws {
		let source = try Self.scene()

		let timers = source
			.matches(of: try Regex("\\bvar (\\w+): Timer\\?", as: AnyRegexOutput.self))
			.map { String($0[1].substring ?? "") }

		// Not a number anybody has to keep up to date. It only has to stay above the point where this
		// test could pass by matching nothing at all, which is what a rename or a move of the timers
		// out of this file would look like from here.
		#expect(timers.count >= 3, "Found \(timers.count) timers on `WallpaperScene`, which is fewer than it has.")

		for exit in ["func suspend()", "func tearDown()"] {
			let body = try Self.body(of: exit, in: source)

			for timer in timers {
				#expect(
					body.contains("\(timer)?.invalidate()"),
					"""
					`\(exit)` does not stop `\(timer)`, so a display that is switched off or unplugged \
					keeps firing it — into a wallpaper that is no longer on screen, for the life of the \
					app. Every timer a scene holds has to be stopped in both exits.
					"""
				)
			}
		}
	}
}
