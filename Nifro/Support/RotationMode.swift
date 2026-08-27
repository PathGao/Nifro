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
	A different one each time, chosen at random.
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

	`nil` means "whatever Settings points at", and there is only ever one of those, so it gets a name
	of its own rather than being folded into whichever display that currently is — otherwise every
	setting made against it would move the day the user changed that preference.
	*/
	static func settingsKey(for display: Self?) -> String {
		display?.id.uuidString ?? "default"
	}
}
