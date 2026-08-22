import Foundation

/**
Whether `hour` falls inside the daily window from `start` up to (but not including) `end`.

Kept as a free function on plain integers so the awkward case can be tested without a clock: a window that wraps midnight — 22 to 6 — is two ranges, and treating it as one comparison silently makes it match nothing.
*/
func isHour(_ hour: Int, within start: Int, until end: Int) -> Bool {
	if start == end {
		return true
	}

	if start < end {
		return hour >= start && hour < end
	}

	return hour >= start || hour < end
}
