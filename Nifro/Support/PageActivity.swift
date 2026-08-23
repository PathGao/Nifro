import Foundation

/**
One reading of how busy a page is over a stretch of time.

Everything here is reported by the page about itself. The alternative, photographing the wallpaper
twice and comparing, cannot tell "nothing is animating" apart from "the animation happens to be on
the same frame", and it costs two image buffers to find out.
*/
struct ActivitySample: Equatable, Sendable {
	/**
	Calls to `requestAnimationFrame` during the window. What script-driven animation looks like.
	*/
	let animationFrames: Int

	/**
	Running CSS animations and transitions, from `document.getAnimations()`.

	Needed separately because CSS animation runs on the compositor and never calls
	`requestAnimationFrame`. A page animated entirely in CSS reports zero frames while visibly moving.
	*/
	let runningAnimations: Int

	/**
	Whether any audio or video element is playing.
	*/
	let isPlayingMedia: Bool

	/**
	DOM mutations during the window. What a clock or a feed looks like: no animation, but the picture
	is not the same one minute later.
	*/
	let mutations: Int

	/**
	Length of the window in seconds.
	*/
	let seconds: Double
}

/**
What a page turned out to be, once watched for a while.
*/
enum PageActivity: Equatable, Sendable {
	/**
	Something moves continuously. Rendering it from stills would break it.
	*/
	case animated

	/**
	Nothing moves, but the content changes now and then. A still plus a refresh is the whole page.
	*/
	case periodic

	/**
	Nothing moves and nothing changes. One still is the page until something reloads it.
	*/
	case still
}

/**
Decide what a page is from a series of readings.

The thresholds are deliberately generous towards `animated`. Getting this wrong in that direction
costs a refresh cycle; getting it wrong the other way freezes something the user put there because
it moves, which is the failure they would notice and resent.
*/
func classify(_ samples: [ActivitySample]) -> PageActivity {
	guard !samples.isEmpty else {
		return .animated
	}

	let totalSeconds = samples.reduce(0) { $0 + $1.seconds }

	guard totalSeconds > 0 else {
		return .animated
	}

	if samples.contains(where: { $0.isPlayingMedia || $0.runningAnimations > 0 }) {
		return .animated
	}

	let frameRate = Double(samples.reduce(0) { $0 + $1.animationFrames }) / totalSeconds

	// A page that idles its animation loop still calls back a few times a second. Anything above a
	// couple of frames per second is drawing, not idling.
	if frameRate > 2 {
		return .animated
	}

	let mutationRate = Double(samples.reduce(0) { $0 + $1.mutations }) / totalSeconds

	// A clock ticking seconds mutates about once a second. That is not something to photograph.
	if mutationRate > 1 {
		return .animated
	}

	// Under one change a minute means a still with a refresh loses nothing.
	return mutationRate > 0 ? .periodic : .still
}

/**
How often to refresh a page classified as `periodic`, given how often it was seen to change.

Round up rather than down. Refreshing faster than the page changes spends a whole page load to
produce the picture that was already there.
*/
func refreshInterval(forMutationRate rate: Double) -> Double {
	guard rate > 0 else {
		return 60 * 30
	}

	let period = 1 / rate

	return min(max(period * 2, 60), 60 * 60)
}
