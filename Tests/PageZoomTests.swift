import Testing

@testable import NifroLogic

/**
The guardrail on "a page cannot be zoomed until it is gone".

The context menu's Zoom Out subtracted a fixed 0.2 from a level with no floor, and the result is not
a mistake that stays on screen long enough to be undone: it is written to `zoomLevel_<address>` and
applied to that page on every later load, across restarts. Five presses reached 0 and the wallpaper
went blank; the sixth stored a negative level. Getting back out meant knowing that Actual Size exists
in a menu that cannot be opened until the wallpaper has been raised.

These are on `PageZoom` rather than on `SSWebView` because the bound is arithmetic and the view is
not reachable from here — the SwiftPM target next door compiles ten pure files out of `Sites` and
`Support`, none of `Wallpaper`. So the arithmetic was moved to where a test can call it instead of
being asserted through the shape of the source, which would have pinned the spelling of the fix
rather than the property.

The literals are spelled out rather than read back off `PageZoom.range`. A test that quotes the
constant it is checking agrees with any value the constant is later given, including 0.
*/
@Suite("Page zoom bounds")
struct PageZoomTests {
	@Test("Zooming out stops before the page disappears")
	func thereIsAFloor() {
		#expect(PageZoom.clamped(0.4) == 0.5)
		#expect(PageZoom.clamped(0) == 0.5)
		#expect(PageZoom.clamped(-0.2) == 0.5)
	}

	@Test("Zooming in stops")
	func thereIsACeiling() {
		#expect(PageZoom.clamped(3.2) == 3)
		#expect(PageZoom.clamped(1000) == 3)
	}

	@Test("A level between the ends is left alone")
	func theRangeIsNotQuantised() {
		#expect(PageZoom.clamped(0.5) == 0.5)
		#expect(PageZoom.clamped(1) == 1)
		#expect(PageZoom.clamped(1.4) == 1.4)
		#expect(PageZoom.clamped(3) == 3)
	}

	@Test("Holding Zoom Out lands on the floor rather than on nothing")
	func theReportedSequence() {
		var level = 1.0

		for _ in 1...6 {
			level = PageZoom.clamped(level - 0.2)
		}

		#expect(level == 0.5)
	}

	/**
	Actual Size is enabled on `pageZoom != 1`, and it is the only way back to 1 from either end. A
	bound that clamped to 1 would switch off the escape hatch at exactly the moment it is wanted.
	*/
	@Test("Both ends leave Actual Size something to do")
	func neitherEndIsActualSize() {
		#expect(PageZoom.clamped(-1) != 1)
		#expect(PageZoom.clamped(1000) != 1)
	}
}
