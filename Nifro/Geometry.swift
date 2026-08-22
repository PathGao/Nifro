import CoreGraphics

/**
The geometry behind cropping and coverage detection.

Kept free of AppKit so it can be exercised directly. Everything here is a pure function of rectangles; the views and windows that call it only supply the numbers.
*/

extension CGRect {
	/**
	Where a page has to sit inside a crop window so that `self` — a region in page coordinates, origin top-left — is what shows.

	Page coordinates run down from the top and view coordinates run up from the bottom, so the vertical offset is the distance from the bottom of the crop to the bottom of the page.
	*/
	func contentFrame(pageSize: CGSize) -> CGRect {
		CGRect(
			x: -minX,
			y: maxY - pageSize.height,
			width: pageSize.width,
			height: pageSize.height
		)
	}

	/**
	Where this page-coordinate crop lands on a screen, so the framed region stays where it was and everything around it simply disappears.
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
The fraction of `region` that no rectangle in `covering` overlaps.

Rasterized onto a grid rather than solved as an exact rectangle union: the answer feeds a 2% threshold, and a 64×40 grid resolves 0.04% per cell — an order of magnitude finer than the question being asked.

- Returns: 1 when nothing covers the region, 0 when it is completely covered.
*/
func uncoveredFraction(
	of region: CGRect,
	covering: [CGRect],
	columns: Int = 64,
	rows: Int = 40
) -> Double {
	guard
		region.width > 0,
		region.height > 0,
		columns > 0,
		rows > 0
	else {
		return 1
	}

	var grid = [Bool](repeating: false, count: columns * rows)
	let cellWidth = region.width / Double(columns)
	let cellHeight = region.height / Double(rows)

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
				grid[row * columns + column] = true
			}
		}
	}

	let coveredCells = grid.count { $0 }
	return 1 - (Double(coveredCells) / Double(grid.count))
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
