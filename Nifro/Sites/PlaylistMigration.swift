import Foundation

/**
How a stored website list divides into playlists, expressed without any of the app around it.

A website used to carry the display it belonged to, and the screen showed whatever named it. Playlists
turn that around, so the one thing that has to be worked out on the way across is which of the old
pinnings becomes which list. That is a question about grouping and ordering and nothing else, which is
why it is a function over plain values here rather than four lines inside the controller — the same
split, for the same reason, as `Rotation.swift` next door.

The reason it is worth the file is what it costs to get wrong. It runs once, against a list the user
built by hand, on a build with no way back: there is no upgrade mechanism in this app at all, and the
list is the whole of what the app is for. A grouping that drops an entry drops a website, and the only
evidence would be that it is not there any more — no error, no half-state, nothing to restore from.
Here, `swift test` can run it against a two-display list without a second display, a stored list or a
window server. The code that calls it cannot be run at all: that reaches `Website`, `Defaults` and
`NSScreen`, none of which the package target compiles.
*/

/**
Every member of a copied list, as a new object rather than the same object listed twice.

Here, and generic over the member, for one reason: this is the rule in the whole feature that is
silent when it is broken. A copy that hands back the members it was given compiles, draws a second row
with the right name in it, and reorders and renames exactly as expected — and then editing either row
edits one website, because both lists hold the same identity. Nothing on screen says so. The first
sign is a user reporting that changing the crop on one screen changed it on the other, which is the
opposite of the feature duplication exists for.

`Website.id` is what the data store, the thumbnail and the remembered scroll position are all filed
under, so a fresh id is also what makes the copy's page independent rather than merely its settings —
and, in the other direction, what signs the copy out of everything the original was signed into. That
is stated in the confirmation the user sees, because it cannot be undone from here.

Generic and in this file so `swift test` can run it: the app's own `Website` reaches `Defaults` and
SwiftUI, neither of which the package target compiles, and a test that cannot run is how this class of
defect survives. `next` is a parameter so a test can watch the ids being handed out rather than only
that they differ.
*/
func withFreshIDs<Member>(
	_ members: [Member],
	id: WritableKeyPath<Member, UUID>,
	next: () -> UUID = UUID.init
) -> [Member] {
	members.map {
		var copy = $0
		copy[keyPath: id] = next()
		return copy
	}
}
