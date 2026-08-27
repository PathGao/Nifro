import Foundation

/**
Which of a display's websites is the current one, expressed without any of the app around it.

The app runs one wallpaper per display, and each of them rotates and schedules on its own. "Current"
is therefore a question per display, not one answer for the whole list — but it is stored as a flag on
each website, which is a shape that lets a list-wide answer be written by accident. It was: making one
website current cleared the flag on every other website, including the ones belonging to a different
screen, so a two-display setup had one display's playlist wiping the other's mark on every tick. The
other display then read "nothing is current", started counting from the beginning, and never moved
past the first website in its list.

Kept here as plain functions over plain values so the two-display case can be checked by `swift test`,
without a second display, a stored list or a window server. That is the whole reason this is a file
and not four lines inside the controller: the mechanism was written on a one-display machine, it is
only wrong when there are two, and reasoning is what got it wrong the first time.
*/

/**
What the "is current" flags become when the website at `target` is made the current one.

`displays[i]` is the display website `i` is shown on, whatever stands in for a display; two websites
are on the same screen exactly when their entries are equal.

Only the entries sharing `target`'s display are rewritten. Everything else keeps the flag it had.
*/
func currentFlags<Screen: Equatable>(
	displays: [Screen],
	wasCurrent: [Bool],
	makingCurrent target: Int
) -> [Bool] {
	guard
		displays.count == wasCurrent.count,
		displays.indices.contains(target)
	else {
		return wasCurrent
	}

	let display = displays[target]

	return displays.indices.map { index in
		guard displays[index] == display else {
			return wasCurrent[index]
		}

		return index == target
	}
}

/**
Which of the shipped websites goes on which display, the first time the app runs.

The Nth display gets the Nth shipped website: one display shows the first one, two displays show the
first and the second, and three show three. The rule is stated for any number of displays rather
than for the one and two cases, because "the first website" alone left every display after the first
with an empty wallpaper and nothing saying so.

`display` is an index into the attached displays, and `nil` for the first one — a website with no
display of its own already means the main display, the one with the menu bar, and that is the first
of the attached displays. Pinning it explicitly would say the same thing today while freezing it: the
main display moves when the user rearranges their screens or docks, and an unpinned website follows
it where a pinned one would not.

More displays than websites gets the websites; more websites than displays leaves the rest in the
list, unshown, which is where a list of eight is meant to be. No displays at all still places the
first website, because there is always one wallpaper: `displaysInUse` falls back to the main display.
*/
func firstLaunchPlacements(displayCount: Int, websiteCount: Int) -> [(website: Int, display: Int?)] {
	(0..<min(max(displayCount, 1), websiteCount)).map {
		($0, $0 == 0 ? nil : $0)
	}
}

/**
The position after `current` in a rotation of `count` websites, wrapping at the end.

`nil` means no website on this display is marked, which is the state a display should never be left
in: the answer is the first one, so a display that has lost its mark starts again rather than stopping.
Reaching that state repeatedly is the failure `currentFlags` exists to prevent, and this is where it
showed — as a display that never advanced.
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
The "is current" flags for a whole list, with exactly one mark per display in use.

`currentFlags` above keeps that true while the app is the one moving the mark. This is for when
something else moves it, and something else does: a website's "Show on" is a binding straight into the
stored list, so changing it is a plain list write that carries the website's mark across to the new
display with it. The display it left is then unmarked, and the display it arrived on has two marks.

Both failures are the same missing invariant and only one of them is loud. An unmarked display reads
as "nothing is current", which is where a rotation starts counting from, so that display sits on the
first website in its list for good — that got noticed, and the loop that fixed it only ever *added* a
mark. Two marks on one display look like nothing at all: `scheduled(for:)` breaks the tie by list
order and shows one of them. So the website the person just sent to that screen was ignored, the
websites window drew two ticks, and the screen they had named did not change — which is the one thing
they asked for.

`wasAlreadyCurrentHere[i]` is whether website `i` held the mark *on this same display* before the
change. Where a display has more than one mark, the ones that were not already there are arrivals, and
an arrival is somebody having just said "show this here", so the incumbent stands down. With no
arrival to prefer — two marks that both predate the change, which is a stored list that was already
wrong rather than a move — the first in list order wins, because that is the one `scheduled(for:)` was
already showing, so repairing an old mess does not change anybody's wallpaper.

`Screen` is `Display?` in the app, where `nil` means the main display — the one with the menu bar,
and not a display named in any setting. That is a display
like any other here, which is why this keys on the value rather than skipping the ones without one.
*/
func repairedCurrentFlags<Screen: Hashable>(
	displays: [Screen],
	isCurrent: [Bool],
	wasAlreadyCurrentHere: [Bool]
) -> [Bool] {
	guard
		displays.count == isCurrent.count,
		displays.count == wasAlreadyCurrentHere.count
	else {
		return isCurrent
	}

	var repaired = isCurrent

	for display in Set(displays) {
		let onDisplay = displays.indices.filter { displays[$0] == display }
		let marked = onDisplay.filter { isCurrent[$0] }

		guard marked.count != 1 else {
			continue
		}

		// `onDisplay` is never empty — the display came out of the list — so the last fallback is what
		// gives a display with no mark at all the first of its websites.
		let keeping = marked.first { !wasAlreadyCurrentHere[$0] } ?? marked.first ?? onDisplay[0]

		for index in onDisplay {
			repaired[index] = index == keeping
		}
	}

	return repaired
}


/**
Which of a display's websites is the one actually on screen.

A display shows one page, and until now the answer was "the first marked one in list order", which is
fine while every mark belongs to the display it is on. Unplugging a screen breaks that: a website
pinned to the departed display moves to the main one and arrives still carrying the mark it held over
there, so the main display has two, and list order — the order the websites happen to have been added
in — decided which of them the user ended up looking at.

`isEvicted[i]` is whether website `i` is only on this display because its own was unplugged. Those
come first, which is the whole rule: the arriving wallpaper takes the screen. It is the same
tie-break `repairedCurrentFlags` makes for a website the user moves by hand — an arrival is the more
recent statement about what this screen should show — and it is stated separately because it is
resolved at a different time. A move rewrites the stored list, so the mark can be repaired there. An
unplug writes nothing, and must not: the mark is what the departed display goes back to when it is
plugged in again, and a cable being pulled out is not somebody choosing a different wallpaper.

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
