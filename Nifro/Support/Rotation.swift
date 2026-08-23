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
