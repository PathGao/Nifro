import CoreGraphics

/**
The geometry behind cropping and coverage detection.

Kept free of AppKit so the tests can call it directly. Everything here is a pure function of rectangles. The views and windows that call it only supply the numbers.
*/

/**
How big one uncovered patch has to be, in square points, to be worth rendering live.

Roughly 200 by 200 points, a block you would notice on any display. An absolute size rather than a
share of the screen: a percentage means something different on a 6K display than on a laptop, and
four thin margins around a nearly maximised window add up to a healthy percentage while showing
nothing anybody would call a wallpaper.

It lives here rather than next to the code that reads it so the tests can assert against the same
number the app uses. A threshold and the check guarding it in two files means changing the threshold
leaves every test green.
*/
let minimumMeaningfulPatchArea = 40_000.0

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
The bounding rectangle of the largest single uncovered patch of `region`, plus its area.

The area is what a threshold looks at. The rectangle is what you shrink the window to when only that part is still on show.
*/
func largestUncoveredRegion(
	of region: CGRect,
	covering: [CGRect],
	columns: Int = 64,
	rows: Int = 40
) -> (rect: CGRect, area: Double) {
	guard
		region.width > 0,
		region.height > 0,
		columns > 0,
		rows > 0
	else {
		return (.zero, 0)
	}

	let cellWidth = region.width / Double(columns)
	let cellHeight = region.height / Double(rows)
	var isCovered = [Bool](repeating: false, count: columns * rows)

	for rect in covering {
		let overlap = rect.intersection(region)

		guard !overlap.isNull, !overlap.isEmpty else {
			continue
		}

		let firstColumn = max(0, Int(((overlap.minX - region.minX) / cellWidth).rounded(.down)))
		let lastColumn = min(columns - 1, Int(((overlap.maxX - region.minX) / cellWidth).rounded(.up)) - 1)
		let firstRow = max(0, Int(((overlap.minY - region.minY) / cellHeight).rounded(.down)))
		let lastRow = min(rows - 1, Int(((overlap.maxY - region.minY) / cellHeight).rounded(.up)) - 1)

		guard firstColumn <= lastColumn, firstRow <= lastRow else {
			continue
		}

		for row in firstRow...lastRow {
			for column in firstColumn...lastColumn {
				isCovered[row * columns + column] = true
			}
		}
	}

	var isVisited = [Bool](repeating: false, count: columns * rows)
	var best = (cells: 0, minColumn: 0, maxColumn: 0, minRow: 0, maxRow: 0)
	var stack = [Int]()

	for start in 0..<(columns * rows) where !isCovered[start] && !isVisited[start] {
		isVisited[start] = true
		stack.append(start)

		var cells = 0
		var minColumn = columns
		var maxColumn = 0
		var minRow = rows
		var maxRow = 0

		while let index = stack.popLast() {
			cells += 1

			let column = index % columns
			let row = index / columns
			minColumn = min(minColumn, column)
			maxColumn = max(maxColumn, column)
			minRow = min(minRow, row)
			maxRow = max(maxRow, row)

			// Four-way connectivity: two patches touching only at a corner are two patches.
			var neighbours = [Int]()

			if column > 0 { neighbours.append(index - 1) }
			if column < columns - 1 { neighbours.append(index + 1) }
			if row > 0 { neighbours.append(index - columns) }
			if row < rows - 1 { neighbours.append(index + columns) }

			for neighbour in neighbours where !isCovered[neighbour] && !isVisited[neighbour] {
				isVisited[neighbour] = true
				stack.append(neighbour)
			}
		}

		if cells > best.cells {
			best = (cells, minColumn, maxColumn, minRow, maxRow)
		}
	}

	guard best.cells > 0 else {
		return (.zero, 0)
	}

	let rect = CGRect(
		x: region.minX + Double(best.minColumn) * cellWidth,
		y: region.minY + Double(best.minRow) * cellHeight,
		width: Double(best.maxColumn - best.minColumn + 1) * cellWidth,
		height: Double(best.maxRow - best.minRow + 1) * cellHeight
	)

	return (rect, Double(best.cells) * cellWidth * cellHeight)
}

/**
Converts a rectangle reported by the window server, which measures down from the top of the whole display arrangement, into AppKit coordinates, which measure up from the bottom.
*/
func flippingFromWindowServer(_ rect: CGRect, arrangementHeight: CGFloat) -> CGRect {
	CGRect(
		x: rect.minX,
		y: arrangementHeight - rect.maxY,
		width: rect.width,
		height: rect.height
	)
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
	The whole page, which is what a zoom starts as before anyone drags anything.
	*/
	static let identity = Self(center: CGPoint(x: 0.5, y: 0.5), scale: 1)

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
