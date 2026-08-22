import CoreGraphics
import Testing

@testable import NifroGeometry

/**
The crop maths. Page coordinates run down from the top-left, view coordinates run up from the bottom-left, and getting the flip wrong shows the wrong part of the page while looking entirely plausible — which is exactly the kind of bug a test has to catch instead of an eye.
*/
@Suite("Crop geometry")
struct CropGeometryTests {
	private let pageSize = CGSize(width: 1600, height: 1000)

	@Test("A crop at the page origin puts the page flush with the top of the window")
	func cropAtOrigin() {
		let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
		let frame = crop.contentFrame(pageSize: pageSize)

		#expect(frame.origin.x == 0)
		// The page hangs below the window by everything the crop does not show.
		#expect(frame.origin.y == -700)
		#expect(frame.size == pageSize)
	}

	@Test("A crop lower down the page pulls the page further up")
	func cropBelowTheFold() {
		let crop = CGRect(x: 100, y: 600, width: 400, height: 300)
		let frame = crop.contentFrame(pageSize: pageSize)

		#expect(frame.origin.x == -100)
		#expect(frame.origin.y == -100)
	}

	@Test("A crop covering the whole page leaves the page unmoved")
	func fullPageCrop() {
		let crop = CGRect(origin: .zero, size: pageSize)
		let frame = crop.contentFrame(pageSize: pageSize)

		#expect(frame.origin == .zero)
	}

	@Test("Cropping the bottom of the page is not the same as cropping the top")
	func verticalFlipIsNotSymmetric() {
		let top = CGRect(x: 0, y: 0, width: 400, height: 300).contentFrame(pageSize: pageSize)
		let bottom = CGRect(x: 0, y: 700, width: 400, height: 300).contentFrame(pageSize: pageSize)

		#expect(top.origin.y != bottom.origin.y)
		#expect(bottom.origin.y == 0)
	}

	@Test("The crop lands where it was framed, not at the screen corner")
	func screenPlacement() {
		let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
		let crop = CGRect(x: 100, y: 200, width: 400, height: 300)
		let placed = crop.screenFrame(inScreen: screen)

		#expect(placed.minX == 100)
		// 200pt down from the top of a 1000pt screen, and 300pt tall, so its bottom sits at 500.
		#expect(placed.minY == 500)
		#expect(placed.size == crop.size)
	}

	@Test("Page and screen coordinates are exact inverses")
	func roundTrip() {
		// What the drag-to-select mode relies on: you draw on screen, it stores page pixels,
		// and putting the window back has to land on the same rectangle you drew.
		let screen = CGRect(x: 1600, y: 200, width: 1600, height: 1000)

		for crop in [
			CGRect(x: 0, y: 0, width: 100, height: 100),
			CGRect(x: 250, y: 700, width: 400, height: 300),
			CGRect(x: 0, y: 900, width: 1600, height: 100)
		] {
			let there = crop.screenFrame(inScreen: screen)
			let back = there.pageFrame(inScreen: screen)

			#expect(back == crop)
		}
	}

	@Test("Placement follows a screen that is not at the global origin")
	func screenPlacementOnSecondaryDisplay() {
		let screen = CGRect(x: 1600, y: 200, width: 1600, height: 1000)
		let crop = CGRect(x: 100, y: 0, width: 400, height: 300)
		let placed = crop.screenFrame(inScreen: screen)

		#expect(placed.minX == 1700)
		#expect(placed.maxY == 1200)
	}
}

/**
Coverage detection. What it has to get right is the difference between "one patch you would actually notice" and "slivers that add up to a number".
*/
@Suite("Coverage detection")
struct CoverageTests {
	private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

	/// Roughly 200×200pt, matching `OcclusionMonitor.minimumMeaningfulPatchArea`.
	private let meaningful = 40_000.0

	@Test("Nothing on screen leaves the whole screen visible")
	func noWindows() {
		#expect(largestUncoveredRegion(of: screen, covering: []).area == 1600 * 1000)
	}

	@Test("A window filling the screen leaves nothing")
	func fullCover() {
		#expect(largestUncoveredRegion(of: screen, covering: [screen]).area == 0)
	}

	@Test("A window covering half the screen leaves the other half")
	func halfCover() {
		let half = CGRect(x: 0, y: 0, width: 800, height: 1000)
		let patch = largestUncoveredRegion(of: screen, covering: [half]).area

		#expect(abs(patch - 800 * 1000) < 1000)
		#expect(patch > meaningful)
	}

	@Test("Overlapping windows are not double counted")
	func overlappingWindows() {
		let left = CGRect(x: 0, y: 0, width: 1000, height: 1000)
		let right = CGRect(x: 600, y: 0, width: 1000, height: 1000)

		#expect(largestUncoveredRegion(of: screen, covering: [left, right]).area == 0)
	}

	@Test("A window off to the side covers nothing")
	func windowOnAnotherDisplay() {
		let elsewhere = CGRect(x: 2000, y: 0, width: 800, height: 600)
		#expect(largestUncoveredRegion(of: screen, covering: [elsewhere]).area == 1600 * 1000)
	}

	@Test("The case this whole mechanism exists for: everything covered but a thin strip")
	func onlyAStripShowing() {
		// One maximized window on the desktop. What survives is a band too shallow to read as wallpaper.
		let almostEverything = CGRect(x: 0, y: 0, width: 1600, height: 985)

		#expect(largestUncoveredRegion(of: screen, covering: [almostEverything]).area < meaningful)
	}

	@Test("Thin margins on all four sides do not add up to something visible")
	func scatteredSlivers() {
		// The case a percentage rule gets wrong: four 10pt margins are 3.6% of the screen,
		// comfortably past a 2% threshold, while showing nothing anybody would call a wallpaper.
		let window = CGRect(x: 10, y: 10, width: 1580, height: 980)

		let totalUncovered = (1600.0 * 1000) - (1580.0 * 980)
		#expect(totalUncovered / (1600 * 1000) > 0.02)

		// Each margin is its own patch, and every one of them is too thin to matter.
		#expect(largestUncoveredRegion(of: screen, covering: [window]).area < meaningful)
	}

	@Test("A genuinely visible desktop stays above the threshold")
	func visibleDesktop() {
		let window = CGRect(x: 200, y: 200, width: 900, height: 600)

		#expect(largestUncoveredRegion(of: screen, covering: [window]).area > meaningful)
	}

	@Test("Two patches touching only at a corner are two patches")
	func diagonalPatchesDoNotJoin() {
		// Windows meeting at the centre leave four quadrants that touch only at one point.
		let vertical = CGRect(x: 700, y: 0, width: 200, height: 1000)
		let horizontal = CGRect(x: 0, y: 400, width: 1600, height: 200)

		let patch = largestUncoveredRegion(of: screen, covering: [vertical, horizontal]).area

		// One quadrant, not the sum of four.
		#expect(patch < 1600 * 1000 / 2)
		#expect(patch > meaningful)
	}

	@Test("A degenerate region reports nothing visible rather than dividing by zero")
	func emptyRegion() {
		#expect(largestUncoveredRegion(of: .zero, covering: [screen]).area == 0)
	}

	@Test("Window-server rectangles flip into AppKit coordinates")
	func flipping() {
		// A menu-bar-height band at the top of a 1000pt arrangement.
		let fromWindowServer = CGRect(x: 0, y: 0, width: 1600, height: 25)
		let flipped = flippingFromWindowServer(fromWindowServer, arrangementHeight: 1000)

		#expect(flipped.minY == 975)
		#expect(flipped.maxY == 1000)
	}
}
