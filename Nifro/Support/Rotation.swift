import Foundation

/**
Which of a display's websites is the one on screen, expressed without any of the app around it.

The app runs one wallpaper per display, and each of them rotates and schedules on its own. "Current"
is therefore a question per display, not one answer for the whole list — and it used to be stored as a
flag on each website, which is a shape that lets a list-wide answer be written by accident. It was:
making one website current cleared the flag on every other website, including the ones belonging to a
different screen, so a two-display setup had one display's rotation wiping the other's mark on every
tick. The other display then read "nothing is current", started counting from the beginning, and never
moved past the first website in its list.

The answer now lives in a dictionary with one entry per display — `Defaults[.currentWebsites]`, read
through `WebsitesController.currentWebsiteID(on:)` — so the two functions that kept the flags unique
are gone with the flags. What is left here is the arithmetic *around* the answer, which is where the
two-display case can still be got wrong: where the next website is, and which of two claims on one
desktop wins.

Kept here as plain functions over plain values so the two-display case can be checked by `swift test`,
without a second display, a stored list or a window server. That is the whole reason this is a file
and not four lines inside the controller: the mechanism was written on a one-display machine, it is
only wrong when there are two, and reasoning is what got it wrong the first time.
*/

/**
The position after `current` in a rotation of `count` websites, wrapping at the end.

`nil` means no website on this display is marked, which is the state a display should never be left
in: the answer is the first one, so a display that has lost its mark starts again rather than stopping.
Reaching that state on every tick is the failure the per-display cursor exists to prevent, and this is
where it showed — as a display that never advanced.
*/
func nextRotationIndex(count: Int, after current: Int?) -> Int? {
	guard count > 0 else {
		return nil
	}

	guard let current, (0..<count).contains(current) else {
		return 0
	}

	return (current + 1) % count
}

/**
Which of a display's websites is the one actually on screen.

A display shows one page, and until now the answer was "the first marked one in list order", which is
fine while every mark belongs to the display it is on. Unplugging a screen breaks that: a website
pinned to the departed display moves to the main one and arrives still carrying the mark it held over
there, so the main display has two, and list order — the order the websites happen to have been added
in — decided which of them the user ended up looking at.

`isEvicted[i]` is whether website `i` is only on this display because its own was unplugged. Those
come first, which is the whole rule: the arriving wallpaper takes the screen.

Only one mark can reach here now, because there is one entry per display for a mark to live in, so the
ordering settles the case where the display has no mark at all, which is a screen that has never been
started. `handOverCurrentWebsites` settles the other case, by writing the arrival into the entry of the
screen it lands on rather than leaving two claims for this to choose between. It can do that because
the two claims are two entries and the arrival's own entry stays where it is; with one flag per
website there was nowhere to write the answer that did not also destroy the departed display's mark,
which is why this had to be a tie-break at all.

`nil` when there is nothing to show, which is a display with no websites on it.
*/
func showingIndex(isCurrent: [Bool], isEvicted: [Bool]) -> Int? {
	guard isCurrent.count == isEvicted.count else {
		return isCurrent.firstIndex(of: true) ?? (isCurrent.isEmpty ? nil : 0)
	}

	let order = isEvicted.indices.filter { isEvicted[$0] } + isEvicted.indices.filter { !isEvicted[$0] }

	// No mark at all is a display that has never been started, and the top of its list is where
	// `advance` counts from too.
	return order.first { isCurrent[$0] } ?? order.first
}
