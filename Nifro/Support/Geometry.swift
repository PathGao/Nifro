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
	As far in as a region is allowed to go.

	At 20× the region is a twentieth of the page across, which is a few words of body text filling a
	display. Past that there is nothing left to frame, and a scroll gesture that never stops is a
	worse answer than one that stops somewhere defensible.
	*/
	static let maximumScale = 20.0

	/**
	The same region moved by a distance in view points, with the region kept on the page.

	The centre is clamped here rather than only in `region(inPageOfSize:)`. Clamping only the
	rectangle lets the centre wander off the page while the picture stops moving, and then the
	gesture has to be given back exactly as far before anything happens again — which reads as the
	drag having stuck.
	*/
	func panned(byViewDelta delta: CGSize, inPageOfSize pageSize: CGSize) -> Self {
		let scale = max(scale, 1)

		return Self(
			center: CGPoint(
				// View coordinates run up from the bottom and page coordinates run down from the top,
				// so the vertical sign is the opposite of the horizontal one. Dragging the page down
				// shows what was above it.
				x: center.x - (delta.width / scale) / pageSize.width,
				y: center.y + (delta.height / scale) / pageSize.height
			),
			scale: self.scale
		)
		.clampedToPage()
	}

	/**
	The same region magnified by `factor`, keeping the part of the page under `anchor` where it is.

	`anchor` is a point in a view the size of the page area, running up from the bottom left. Zooming
	around the pointer rather than around the middle is the difference between moving a page and
	operating a control.
	*/
	func magnified(by factor: Double, around anchor: CGPoint, inPageOfSize pageSize: CGSize) -> Self {
		let oldScale = max(scale, 1)
		let newScale = (oldScale * factor).clamped(to: 1...Self.maximumScale)

		// Where the pointer is across the region, from its middle, as a fraction of the region.
		let acrossRegion = anchor.x / pageSize.width - 0.5
		let downRegion = 0.5 - anchor.y / pageSize.height

		// The point of the page under the pointer, which is what has to stay put.
		let held = CGPoint(
			x: center.x + acrossRegion / oldScale,
			y: center.y + downRegion / oldScale
		)

		return Self(
			center: CGPoint(
				x: held.x - acrossRegion / newScale,
				y: held.y - downRegion / newScale
			),
			scale: newScale
		)
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
