import Defaults
import Foundation

/**
What a display does when its rotation ticks.

Per display, not per app, as is how often it ticks — see `RotationInterval.swift`. Everything about a
wallpaper is a question per screen: which website, how loud, how it is cropped, and now both halves of
how it rotates. Rotation was the odd one out for a while: one interval for the whole machine, and
"rotating at all" derived from whether that interval happened to be set. So turning rotation off on the
laptop turned it off on the monitor too, and there was no way to say "shuffle over here every ten
minutes, hold still over there".

Stored keyed by display rather than as a property of anything, because there is nothing else that is
one-per-display: a scene is rebuilt whenever screens change, and a website belongs to a display rather
than being one.
*/
enum RotationMode: String, CaseIterable, Defaults.Serializable {
	/**
	Stay on this one. Where a display starts, and the only one that is not lit.

	Rotation stops; nothing else does. The arrows and the picker still work, because "do not change it
	behind my back" and "do not let me change it" are different requests and only the first was made.
	The schedule still applies — a website whose hours end still gives way, or "pinned" would quietly
	mean "ignore the times I set".
	*/
	case pinned

	/**
	Round the list in order.
	*/
	case loop

	/**
	Round the list in an order decided in advance.

	Shuffle play, not random playback, and the two are different promises rather than two spellings of
	one. Random playback picks a website when the last one ends, so it can offer the same page twice in
	a row and take four rounds to get to a list of four. Shuffle deals the whole list out at once and
	goes through it, which is the promise a wallpaper wants: every website is seen once before any of
	them is seen again.

	Because the order is decided rather than drawn, it can be shown — the website chooser lists it, in
	the order it will happen — and it can be walked backwards, which is a meaning Previous did not have
	while this was an iterator handing out one website at a time and remembering none of them.

	The order is not stored. A relaunch decides a new one around the page already up, so the wallpaper
	carries on rather than starting over; `WebsitesController.shuffledOrders` is where it lives and why.

	Arriving at this mode decides one too, so a control that cycles back round to Random deals again
	rather than resuming a pass the user left. `WallpaperScene.rotationMode` is where that happens and
	`WebsitesController.forgetOrder(on:)` is what it calls.
	*/
	case random

	/**
	The one after this, for a control that cycles.
	*/
	var next: Self {
		let all = Self.allCases

		guard let index = all.firstIndex(of: self) else {
			return .pinned
		}

		return all[(index + 1) % all.count]
	}
}

extension Display {
	/**
	The key this display's per-display settings are stored under.

	`nil` means the main display, the one with the menu bar. There is only ever one of those, so it
	gets a name of its own rather than being folded into whichever display that currently is —
	otherwise every setting made against it would move the day the user rearranged their displays or
	docked the laptop.

	A key here outlives the display it names, which is what makes a monitor come back as it was left.
	Which per-display facts are kept that way and which are erased when the display goes is the three
	classes at `Defaults.Keys`; there is deliberately no key saying whether a display is attached at
	all.
	*/
	static func settingsKey(for display: Self?) -> String {
		display?.id.uuidString ?? "default"
	}
}
