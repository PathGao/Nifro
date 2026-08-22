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

extension CGRect {
	/**
	The inverse of `screenFrame(inScreen:)`: where a screen rectangle falls in page coordinates.

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

The area is what a threshold looks at; the rectangle is what you shrink the window to when you want to keep rendering only the part still on show.
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
The area, in square points, of the largest single uncovered patch of `region`.

Not the total uncovered area, and not a percentage. Both of those answer the wrong question.

A percentage is not screen-independent: 2% of a 6K display is a block you would notice, 2% of a laptop screen is a sliver. And a total ignores shape — four thin margins around a nearly-maximized window can add up to a respectable number while showing nothing anybody would call a wallpaper. What matters is whether one contiguous piece is big enough to see, so that is what gets measured.

Rasterized onto a grid rather than solved exactly: the answer feeds a "is this big enough to bother rendering for" decision, and a 64×40 grid resolves a patch to well under the size that decision cares about.

- Returns: the area of `region` when nothing covers it, and 0 when it is completely covered.
*/
func largestUncoveredPatch(
	of region: CGRect,
	covering: [CGRect],
	columns: Int = 64,
	rows: Int = 40
) -> Double {
	largestUncoveredRegion(of: region, covering: covering, columns: columns, rows: rows).area
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
