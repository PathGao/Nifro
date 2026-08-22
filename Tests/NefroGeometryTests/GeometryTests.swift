import CoreGraphics
import Testing

@testable import NefroGeometry

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
Coverage detection. The threshold it feeds is 2%, so what matters is that "completely covered" and "a sliver showing" land on opposite sides of it.
*/
@Suite("Coverage detection")
struct CoverageTests {
	private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

	@Test("Nothing on screen means nothing is covered")
	func noWindows() {
		#expect(uncoveredFraction(of: screen, covering: []) == 1)
	}

	@Test("A window filling the screen covers all of it")
	func fullCover() {
		#expect(uncoveredFraction(of: screen, covering: [screen]) == 0)
	}

	@Test("A window covering half the screen leaves half")
	func halfCover() {
		let half = CGRect(x: 0, y: 0, width: 800, height: 1000)
		#expect(abs(uncoveredFraction(of: screen, covering: [half]) - 0.5) < 0.01)
	}

	@Test("Overlapping windows are not double counted")
	func overlappingWindows() {
		let left = CGRect(x: 0, y: 0, width: 1000, height: 1000)
		let right = CGRect(x: 600, y: 0, width: 1000, height: 1000)

		#expect(uncoveredFraction(of: screen, covering: [left, right]) == 0)
	}

	@Test("A window off to the side covers nothing")
	func windowOnAnotherDisplay() {
		let elsewhere = CGRect(x: 2000, y: 0, width: 800, height: 600)
		#expect(uncoveredFraction(of: screen, covering: [elsewhere]) == 1)
	}

	@Test("The case this whole mechanism exists for: everything covered but a thin strip")
	func onlyAStripShowing() {
		// What the user sees when one maximized window sits on the desktop: the wallpaper survives
		// only where the Dock and menu bar are, and that has to read as covered.
		let almostEverything = CGRect(x: 0, y: 0, width: 1600, height: 985)

		let uncovered = uncoveredFraction(of: screen, covering: [almostEverything])

		#expect(uncovered < 0.02)
	}

	@Test("A genuinely visible desktop stays above the threshold")
	func visibleDesktop() {
		// A normal window on an otherwise clear desktop.
		let window = CGRect(x: 200, y: 200, width: 900, height: 600)

		#expect(uncoveredFraction(of: screen, covering: [window]) > 0.02)
	}

	@Test("A degenerate region reports visible rather than dividing by zero")
	func emptyRegion() {
		#expect(uncoveredFraction(of: .zero, covering: [screen]) == 1)
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
