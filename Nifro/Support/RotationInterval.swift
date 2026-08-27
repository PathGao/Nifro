import Foundation

/**
How long a display waits before it moves to the next website, in minutes.

Per display, like the mode it belongs to. It was one number for the whole machine, living in
Settings, so the laptop and the monitor had to agree about something they have no reason to agree
about — and that same number was doing double duty as "does this rotate at all", a question each
display has answered for itself since `RotationMode` arrived.

Minutes rather than seconds, which is what the machine-wide setting stored. The only thing that reads
this is a field the user types minutes into, and the only thing that writes it is that field, so
storing seconds would mean two conversions on every trip for the benefit of nobody. The one place the
old unit still shows up is the fallback below, which divides once.

Plain functions over plain values, for the reason `Rotation.swift` gives: the answer differs per
display, a machine with one display cannot show it being wrong, and the fallback an upgrading user
lands on is a branch that wants checking rather than reasoning about.
*/

/**
The shortest and longest wait a display can be given.

A minute at the bottom because that is the tick rotation runs on, so anything smaller would round up
to it anyway and only look like it had been accepted. A day at the top because the number comes
straight out of a text field: nothing stops somebody typing a year into it, and a display that will
next move in a year is indistinguishable from one that is broken.
*/
let rotationIntervalRange = 1.0...(60.0 * 24)

/**
What a display waits when nobody has said otherwise.

Half an hour, which is what the Settings toggle this replaces filled in when it was switched on.
*/
let defaultRotationIntervalMinutes = 30.0

/**
How long `stored` minutes means in practice, falling back to the machine-wide number it replaced.

`legacySeconds` is `Defaults[.playlistInterval]`, which every version up to 0.1.3 used for every
display at once. A display with nothing of its own inherits it, so somebody who had set forty-five
minutes there keeps forty-five minutes on every screen rather than being quietly moved to the
default.

Read on every tick rather than copied across once at launch, because the displays that exist at
launch are not the displays that exist: a monitor plugged in next month was not there to be migrated,
and it should inherit the same number its neighbours did rather than the default.

The fallback can go once nobody is upgrading from 0.1.3 or older — there is no signal for that, so
the honest condition is a version: delete `legacySeconds`, the `playlistInterval` key and this
paragraph in 1.0.
*/
func rotationInterval(stored: Double?, legacySeconds: Double?) -> Double {
	guard
		let minutes = stored ?? legacySeconds.map({ $0 / 60 }),
		minutes.isFinite
	else {
		return defaultRotationIntervalMinutes
	}

	return min(max(minutes, rotationIntervalRange.lowerBound), rotationIntervalRange.upperBound)
}

/**
What a number typed into the field becomes.

`entered` is `nil` for anything the field could not read as a number at all, including an empty one,
and the answer there is `current`: an empty field is somebody midway through typing or somebody who
changed their mind, and neither of them asked for the wallpaper to stop. Zero and negatives are
numbers the field can read and nobody can mean, so they land on the bottom of the range rather than
being refused — the user gets the fastest rotation on offer, which is visibly not what they typed and
therefore self-correcting, instead of a display that never moves again.
*/
func rotationInterval(entered: Double?, current: Double) -> Double {
	guard
		let entered,
		entered.isFinite
	else {
		return current
	}

	return min(max(entered.rounded(), rotationIntervalRange.lowerBound), rotationIntervalRange.upperBound)
}
