import Foundation
import Testing

/**
Who arms the watch, and who stops it.

`SceneTimerLifetimeTests` finds every `Timer?` on the scene and requires both exits to stop it, so
`firstPaintTimer` is covered there by existing. What that cannot see is the third ending, which is
the one this timer is actually for: the page arrives, `revealPage` runs, and the watch has nothing
left to watch. Left armed it goes on firing every 150ms for the life of the display — taking no
snapshots, because the tick returns on `hasRevealedPage`, and doing nothing else either. A clock that
costs a little and achieves nothing is the hardest kind to notice.

The other half is that only the plain load arms it. A swap keeps the outgoing page on screen for the
whole fetch and reveals through `adopt`, so there is nothing missing from the desktop to hurry, and a
watch there would be spending snapshots to reveal a page that is already up.

Shape rather than behaviour, for the reason `CropLifetimeTests` gives: the SwiftPM target compiles
nothing from `Wallpaper`. The rule the watch applies is a different matter and is exercised for real
in `FlatColourTests`.
*/
@Suite("The watch for a first paint is armed once and stopped by whoever reveals")
struct FirstPaintRevealTests {
	private static func source(named name: String) throws -> String {
		let file = URL(filePath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Nifro/Wallpaper/\(name)")

		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(contentsOf: file, encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	private static func body(of declaration: String, in source: String) throws -> String {
		let start = try #require(source.range(of: declaration))
		var depth = 0
		var body = ""

		for character in source[start.upperBound...] {
			if character == "{" {
				depth += 1
			}

			if depth > 0 {
				body.append(character)
			}

			if character == "}" {
				depth -= 1

				if depth == 0 {
					return body
				}
			}
		}

		Issue.record("`\(declaration)`'s body is unbalanced.")
		return ""
	}

	@Test("The plain load arms it and the swap does not")
	func onlyThePlainLoadArms() throws {
		let scene = try Self.source(named: "WallpaperScene.swift")

        #expect(
			try Self.body(of: "func load(", in: scene).contains("watchForFirstPaint()"),
			"A plain load no longer watches for the page being drawn, so the desktop is back to waiting for the whole load event."
		)

		#expect(
			try !Self.body(of: "func loadBySwapping(", in: Self.source(named: "SwapLoading.swift")).contains("watchForFirstPaint()"),
			"The swap path arms the watch, which spends snapshots to hurry a reveal that is deliberately waiting — the outgoing page is on screen for all of it."
		)
	}

	@Test("Revealing stops the watch")
	func revealingStopsTheWatch() throws {
		let reveal = try Self.body(of: "func revealPage()", in: Self.source(named: "WallpaperScene.swift"))

		#expect(
			reveal.contains("firstPaintTimer?.invalidate()"),
			"Nothing stops the watch when the page goes up, so it fires every 150ms for the life of the display, does nothing, and shows no symptom."
		)
	}

	@Test("The watch reveals through the one door, and asks the one photographer")
	func theWatchGoesThroughRevealPage() throws {
		let tick = try Self.body(of: "func revealIfPageHasDrawn() async", in: Self.source(named: "WallpaperScene.swift"))

		#expect(
			tick.contains("revealPage()"),
			"The watch puts the page on screen itself instead of going through `revealPage`, so everything ordered behind that moment — the band's colour, its visibility, its cadence — is skipped on the path that now usually wins."
		)

		#expect(
			tick.contains("await snapshot()"),
			"The watch takes its own picture rather than asking `snapshot()`, which is a second answer to what part of the page the display is showing."
		)
	}
}
