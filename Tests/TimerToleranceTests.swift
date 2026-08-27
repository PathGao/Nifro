import Foundation
import Testing

/**
The guardrail on "a timer that outlives the moment it was armed for says how late it may be".

Both of this app's repeating timers are armed once per display and then run until the app quits: the
minute tick that reads the schedule and counts out the rotation interval, and the page reload. Left
at `Timer`'s default tolerance of zero, each of those is a wakeup macOS is forbidden to merge with
anything else it was about to do, once a minute per display for the tick alone — which is the exact
case Apple's energy guidance names `tolerance` for.

Zero is also what a timer gets by saying nothing, so the defect is invisible in review: the two calls
that shipped without it look like every `Timer.scheduledTimer` anybody has ever written. That is the
whole argument for a test rather than a comment beside each one. A comment is read by whoever is
already looking at that line; this is read by whoever adds the third timer.

Shape rather than behaviour, for the reason `ScopeTests` and `LoadingIndicatorTests` spell out at
length: the SwiftPM target next door compiles ten pure files out of `Sites` and `Support`, none of
`App`, `Wallpaper` or `Visibility`, so there is no `WallpaperScene` here to arm anything on. But even
with one, tolerance has no observable behaviour to assert — it is permission granted to the run loop,
and whether the run loop takes it depends on what else the machine is doing. There is nothing to run.

The two names matched below, `Timer.scheduledTimer` and `tolerance`, are Foundation's. Nothing this
repo could rename turns one of these red without the behaviour changing with it.
*/
@Suite("Every long-lived timer sets a tolerance")
struct TimerToleranceTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The app's Swift files with their prose taken out.

	Both timers argue for their own tolerance in a comment directly underneath it, and those comments
	name `Timer` and `tolerance` while explaining them. Counted with the prose left in, a file would
	satisfy this test by talking about the rule instead of following it.
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

	@Test("Every scheduled timer is given one")
	func everyScheduledTimerHasATolerance() throws {
		let scheduled = try Regex("Timer\\.scheduledTimer\\b")
		let tolerance = try Regex("\\.tolerance\\s*=")

		var total = 0

		for file in try Self.sources() {
			let timers = file.text.matches(of: scheduled).count

			guard timers > 0 else {
				continue
			}

			total += timers

			#expect(
				file.text.matches(of: tolerance).count == timers,
				"""
				\(file.name) schedules \(timers) timer(s) and sets \(file.text.matches(of: tolerance).count) \
				tolerance(s). A timer that says nothing gets zero, which forbids macOS from firing it \
				alongside anything else it was already waking for — and every timer in this app is armed \
				once per display and then runs until the app quits.
				"""
			)
		}

		// Not a count anybody has to keep up to date — it only has to stay above the point where this
		// test could pass by matching nothing at all, which is what a rename of Foundation's API out
		// from under the regex above would look like.
		#expect(total >= 2, "Found \(total) scheduled timers in Nifro/, which is fewer than this app has.")
	}
}
