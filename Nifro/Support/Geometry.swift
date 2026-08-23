import CoreGraphics

/**
The geometry behind cropping and coverage detection.

Kept free of AppKit so the tests can call it directly. Everything here is a pure function of rectangles. The views and windows that call it only supply the numbers.
*/

extension CGRect {
	/**
	Where a page has to sit inside a crop window so that `self` is what shows. `self` is a region in page coordinates with the origin at the top-left.

	Page coordinates run down from the top and view coordinates run up from the bottom, so the vertical offset is the distance from the bottom of the crop to the bottom of the page.
	*/
	func contentFrame(pageSize: CGSize, scale: Double = 1) -> CGRect {
		CGRect(
			x: -minX * scale,
			y: (maxY - pageSize.height) * scale,
			width: pageSize.width * scale,
			height: pageSize.height * scale
		)
	}

	/**
	Where this page-coordinate crop lands on a screen, so the framed region stays where it was and everything around it disappears.
	*/
	func screenFrame(inScreen screenFrame: CGRect) -> CGRect {
		CGRect(
			x: screenFrame.minX + minX,
			y: screenFrame.maxY - maxY,
			width: width,
			height: height
		)
	}
}

extension CGRect {
	/**
	Where a screen rectangle falls in page coordinates, the inverse of `screenFrame(inScreen:)`.

	Only valid while the page lays out at the size of that screen, which is the arrangement the wallpaper always uses.
	*/
	func pageFrame(inScreen screenFrame: CGRect) -> CGRect {
		CGRect(
			x: minX - screenFrame.minX,
			y: screenFrame.maxY - maxY,
			width: width,
			height: height
		)
	}
}

/**
Which part of a page fills the wallpaper.

Stored as a place and a magnification rather than a rectangle, because the same website can be on two
displays at once and a rectangle only fits the one it was drawn on. A 16:10 rectangle framed on the
laptop screen, shown on a 16:9 external, either has to be letterboxed or has to show something the
user did not frame. A centre and a magnification survive the move: each display works out its own
rectangle, always the shape of that display, always around the same part of the page.

The region is the shape of the display's page area rather than anything the user chose, which is why
the selection is locked to that shape while it is being drawn. Framing a square and getting a
widescreen back would be worse than not being allowed to draw the square.
*/
struct Zoom: Codable, Hashable, Sendable {
	/**
	The middle of the region, as a fraction of the page. Origin at the top-left, so (0.5, 0.5) is the
	middle of the page.
	*/
	var center: CGPoint

	/**
	How many times the region is enlarged to fill the wallpaper. 1 is the whole page.
	*/
	var scale: Double

	/**
	The region this zoom picks out of a page of `pageSize`, in page coordinates from the top-left.

	Kept inside the page. A centre near an edge, or a page whose shape differs from the one the zoom
	was drawn on, would otherwise put part of the region past the end of the page and show a band of
	nothing along that side.
	*/
	func region(inPageOfSize pageSize: CGSize) -> CGRect {
		let scale = max(scale, 1)
		let size = CGSize(width: pageSize.width / scale, height: pageSize.height / scale)

		return CGRect(
			x: (center.x * pageSize.width - size.width / 2).clamped(to: 0...(pageSize.width - size.width)),
			y: (center.y * pageSize.height - size.height / 2).clamped(to: 0...(pageSize.height - size.height)),
			width: size.width,
			height: size.height
		)
	}

	/**
	The zoom that picks out `region` of a page of `pageSize`.
	*/
	init(region: CGRect, inPageOfSize pageSize: CGSize) {
		center = CGPoint(x: region.midX / pageSize.width, y: region.midY / pageSize.height)
		scale = region.width > 0 ? pageSize.width / region.width : 1
	}

	// periphery:ignore - exercised by the SwiftPM test target, which the scan cannot see.
	init(center: CGPoint, scale: Double) {
		self.center = center
		self.scale = scale
	}
}

extension Comparable {
	fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
		min(max(self, range.lowerBound), range.upperBound)
	}
}

/**
How tall the menu bar's strip is on a screen, given the screen's two rectangles.

`visibleFrame` is the screen minus the menu bar and minus the Dock. Only the menu bar is at the top,
so the distance between the two top edges is the menu bar and nothing else — wherever the Dock is,
and whatever the display's shape.

The previous answer was a guess checked against a constant: "the menu bar is 33 points tall on a
notched display, 24 otherwise, plus one point of padding — so if the space at the top is smaller than
that, the menu bar must be set to hide itself". On this machine the space at the top is 33 and the
constant said 34, so the app concluded the menu bar was hidden, laid the page out over it, and never
built the colour band because it believed there was no menu bar to tint. Nothing else was wrong; the
guess was one point out.

Zero when the menu bar hides itself, which is the right answer for that case too: the space is the
user's again, and a wallpaper should have it.
*/
func menuBarStripHeight(frame: CGRect, visibleFrame: CGRect) -> Double {
	max(0, frame.maxY - visibleFrame.maxY)
}
