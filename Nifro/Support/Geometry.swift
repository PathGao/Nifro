import CoreGraphics

// The geometry behind cropping a page and placing it on a screen.
//
// Kept free of AppKit so the tests can call it directly. Everything here is a pure function of
// rectangles. The views and windows that call it only supply the numbers.

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
	How many times the page is drawn larger than life so that the region fills the wallpaper.

	Derived from the region rather than read off `scale`, because `region(inPageOfSize:)` clamps and
	`scale` does not, so the two disagree exactly when the region has been pushed back onto the page.
	*/
	func magnification(inPageOfSize pageSize: CGSize) -> Double {
		let region = region(inPageOfSize: pageSize)
		return region.width > 0 ? pageSize.width / region.width : 1
	}

	/**
	The strip of the page that ends up along the top of the display, in the coordinates of the view
	the page is drawn in.

	`PageView` magnifies the page and then slides it so the top-left corner of the region lands in the
	top-left corner of the window. So a point `(px, py)` on the page sits at `(px * scale, py * scale)`
	in the view, and the strip on show at the top of the display starts at the region's own origin,
	magnified.

	The width and the height are not scaled. They are already measured in the magnified points the
	view's coordinates are in, so scaling them again is the mistake this exists to make impossible to
	make twice: the menu bar band worked this out on its own, got the top strip of the whole page
	instead, and tinted the menu bar with a part of the page that is usually not even on screen.
	*/
	func topStrip(inPageOfSize pageSize: CGSize, height: Double) -> CGRect {
		let region = region(inPageOfSize: pageSize)
		let scale = magnification(inPageOfSize: pageSize)

		return CGRect(
			x: region.minX * scale,
			y: region.minY * scale,
			width: pageSize.width,
			height: height
		)
	}

	/**
	As far in as a region is allowed to go.

	At 20× the region is a twentieth of the page across, which is a few words of body text filling a
	display. Past that there is nothing left to frame, and a scroll gesture that never stops is a
	worse answer than one that stops somewhere defensible.
	*/
	static let maximumScale = 20.0

	/**
	The same region moved by a distance in view points, with the region kept on the page.

	The frame moves with the drag, not against it: the page underneath stays where it is, and what
	moves is the rectangle picking a part of it.

	The centre is clamped here rather than only in `region(inPageOfSize:)`. Clamping only the
	rectangle lets the centre wander off the page while the frame stops moving, and then the gesture
	has to be given back exactly as far before anything happens again — which reads as the drag having
	stuck.
	*/
	func movedFrame(byViewDelta delta: CGSize, inPageOfSize pageSize: CGSize) -> Self {
		Self(
			center: CGPoint(
				// View coordinates run up from the bottom and page coordinates run down from the top,
				// so the vertical sign is the opposite of the horizontal one.
				x: center.x + delta.width / pageSize.width,
				y: center.y - delta.height / pageSize.height
			),
			scale: scale
		)
		.clampedToPage()
	}

	/**
	The same region with the frame made `factor` times bigger, around its own middle.

	Stated as the frame growing rather than as the magnification rising, because the frame is the
	thing under the fingers: spreading two of them makes what they are on bigger. Magnification is the
	inverse of frame size — a frame half as wide is twice the magnification — so a gesture written the
	other way round comes out backwards, which is exactly how it shipped the first time.

	Around its middle rather than around the pointer, because the page does not move here — only the
	frame does. Anchoring the size change to the pointer would slide the frame out from under it,
	which is the sort of thing that feels right when the picture is moving and wrong when it is not.
	*/
	func resizedFrame(byGrowing factor: Double) -> Self {
		guard factor > 0 else {
			return self
		}

		return Self(center: center, scale: (max(scale, 1) / factor).clamped(to: 1...Self.maximumScale))
			.clampedToPage()
	}

	/**
	The same region moved as little as possible to sit inside the page.
	*/
	func clampedToPage() -> Self {
		let scale = max(scale, 1).clamped(to: 1...Self.maximumScale)
		let half = 1 / (2 * scale)

		return Self(
			center: CGPoint(
				x: center.x.clamped(to: half...(1 - half)),
				y: center.y.clamped(to: half...(1 - half))
			),
			scale: scale
		)
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
