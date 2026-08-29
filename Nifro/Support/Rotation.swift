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
two-display case can still be got wrong: where the next website is, what a display that has never
been started shows, and — since Random became shuffle — what order a display walks its websites in
and what a change to those websites does to an order already decided.

Kept here as plain functions over plain values so the two-display case can be checked by `swift test`,
without a second display, a stored list or a window server. That is the whole reason this is a file
and not four lines inside the controller: the mechanism was written on a one-display machine, it is
only wrong when there are two, and reasoning is what got it wrong the first time.

The two below about the order are here for the second half of that reason rather than the first. An
order and the rules for keeping it are a list and a cursor and nothing else — no `Defaults`, no
display, no web view — so they can be run rather than reasoned about, and the rules are exactly the
kind that read as obvious and are not: what happens to a website added halfway through a pass, and
what "halfway through" even means once it has been added.
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

/**
A fresh order for a display's websites, with the one it is showing at the front.

Shuffle play rather than random playback, which is the distinction the mode is named for. Random
playback picks the next website when the last one ends and is free to pick one it has just shown;
shuffle decides a whole order at once and does not come back to a website until it has been through
the others. What is returned is therefore a *list*, and that is the point of it being a list: the two
functions above already know how to walk one, so a shuffled display steps by the same arithmetic as a
looping one and there is no second kind of stepping to keep in agreement with the first.

`showing` is what is on that screen at the moment the order is decided, and putting it at the front is
what stops the wallpaper jumping. An order is decided three times and in all three there is already a
page up. On the first tick after a relaunch, because the order is not stored and the cursor is — a
wallpaper has no "start listening" moment, so it carries on rather than starting over. At the end of a
pass, because a wallpaper never finishes. And when a display is pointed at another list, which is the
one of the three the user just asked for and still not a reason to replace the page they are looking
at before they have looked away.

At the front rather than left where it fell, so that the position the cursor names is the position the
stepping starts from: the order and the mark agree by construction instead of by a repair. It also
settles the end of a pass without a rule of its own — the website the last pass ended on heads the next
one, so the first step of a new pass cannot land on the website that was just up.

`nil`, or a website this list does not hold, is the ordinary state of a display nobody has picked for
and of one whose website was deleted. There is nothing on that screen worth keeping, so all of it is
shuffled.
*/
func shuffledOrder<ID: Equatable>(of ids: [ID], startingWith showing: ID?) -> [ID] {
	guard
		let showing,
		let index = ids.firstIndex(of: showing)
	else {
		return ids.shuffled()
	}

	var rest = ids
	rest.remove(at: index)

	return [showing] + rest.shuffled()
}

/**
An order carried through a change to the websites it was made out of.

The set a display can show moves under an order that has already been decided, and three ordinary
things move it: a website added to the playlist, a website deleted from it, and a website whose hours
have just begun or ended. The third is the one worth naming, because it is a change with no edit
behind it — the schedule is a filter applied when the list is asked for, so nothing is written and no
publisher fires when a window closes. Asking this question where the order is *read* rather than
where a key changes is what covers all three with one rule, and the third one is the one a rule
hung off a publisher cannot reach at all.

A website that has gone drops out. That is forced.

A website that is new is **appended to the end** rather than shuffled in, and that is chosen. Shuffled
in, it would land somewhere among the websites this pass has already been through and would not be
seen until the pass after next — a site added to the playlist you are watching, invisible for two
rounds. Appended, it is coming.

Which settles what the end of a pass means once something has been appended: the pass is over at the
end of the order **as it now stands**, not where the end was when the order was decided. There is
nothing here recording where the end used to be, deliberately — a website appended past an end that
had already been reached would be reshuffled away before it was ever shown, which is the append rule
meaning nothing.

Empty means there is nothing left of this order: every website it named has gone, which is what
pointing a display at a different playlist looks like from in here. The caller decides again from
scratch, because what survives a change that large is not an order, it is a list in whatever order the
playlist happens to hold it. Empty rather than `nil`, because an order of nothing and nothing left of
an order are answered the same way, and an optional collection is a second kind of empty to tell apart
from the first.
*/
func orderCarriedForward<ID: Hashable>(_ order: [ID], through eligible: [ID]) -> [ID] {
	let live = Set(eligible)
	let kept = order.filter { live.contains($0) }

	guard !kept.isEmpty else {
		return []
	}

	let known = Set(kept)

	return kept + eligible.filter { !known.contains($0) }
}
