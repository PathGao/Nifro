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
two-display case can still be got wrong: where the next website is, and what a display that has never
been started shows.

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

The marked one, and the top of the list when nothing is marked. Not marked is the ordinary state of a
display nobody has picked for yet, and it is also what a display whose website has since been deleted
reads as, so answering it with "nothing" would leave a screen blank on a fresh install and after every
deletion. The top of the list is where `nextRotationIndex` counts from too, so a display that has lost
its mark starts again rather than stopping.

It used to take a second array as well. A website was pinned to a display, and unplugging that display
moved it to the main one still carrying its own mark — so one desktop had two claims on it and list
order, which is the order the websites happened to be added in, decided which of them the user saw.
A website belongs to a playlist now and a display picks a playlist, so nothing is ever pushed onto a
screen it was not chosen for and there is no second claim to break a tie between.

`nil` when there is nothing to show, which is a display with no websites on it.
*/
func showingIndex(isCurrent: [Bool]) -> Int? {
	isCurrent.firstIndex(of: true) ?? (isCurrent.isEmpty ? nil : 0)
}
