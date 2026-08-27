import Defaults
import Foundation

/**
Keeping the same video at the same place on synced displays.

Each display is its own web view with its own decoder, so this is not one source shown twice — it is
two players told to agree. Frame-exact is not on offer and is not claimed: independent decoders,
independent compositing, no genlock, and `currentTime` itself is defined as an approximation.

**Nobody follows anybody.** The app hands every page in a group the same number — the wall-clock
moment that group's video was at zero — and each page works out where it should be from that and
its own clock, twice a second, for as long as it is up. Two web views on one Mac read the same
system clock, so two pages given the same epoch agree without exchanging anything.

That is the whole design, and it replaced the obvious one. Reading the leader's position and
correcting the follower towards it was measured for a fortnight of afternoons and never got below
a second: a seek aims at where the leader *was* while the leader keeps moving, a stall on one
display drags the other, and a round trip through the app puts a floor under how often it can look.
None of those exist here. A page that stalls comes back onto the same curve on its own, and the
page beside it never knew.

The app still has to be the hub for the one number, because every website has its own
`WKWebsiteDataStore`: the pages share no storage at all — `BroadcastChannel`, `localStorage`,
`SharedWorker` and service workers are partitioned per store — so they have no way to speak to each
other. But it is one number stated every couple of seconds, not a correction negotiated five times
a minute.

The script rides in `.defaultClient` alongside the audio control, because that is the only world the
app can talk to: `addJavaScript` puts each script in a fresh anonymous world, which is write-only
from Swift. `forMainFrameOnly: false` puts a copy inside the framed player too, where the media
element is same-origin and can simply be read — which is why this needs no YouTube IFrame API. That
API could not do the job anyway: `setPlaybackRate` only accepts the discrete rates the player
offers, and there is no 1.1 among them.
*/
@MainActor
enum MediaSync {
	/**
	Thresholds, together, because they are the part that wants tuning against real screens.

	Read by the page rather than by anything here — they are interpolated into the script.
	*/
	enum Tolerance {
		/// Above this, start correcting.
		///
		/// Every page holds itself to the clock, so two displays are at worst twice this apart — the
		/// number to compare against what anybody can see is `2 × engage`, not `engage`. At a sixth of
		/// a second, which is where this started, the pair sat at a steady third of a second and the
		/// dead zone was the whole of the remaining error.
		static let engage = 0.06

		/// Below this, stop correcting. Separate from `engage` on purpose: one threshold for both
		/// switches the correction on and off around the same number, and every switch costs a visible
		/// hitch on WebKit — `playbackRate` interrupts playback for a moment on each change there
		/// (WebKit bug 208142, which dash.js works around by refusing rate changes under 0.25 on
		/// Safari). With a gap between the two, one correction is one rate change in and one out.
		static let release = 0.02

		/// Above this, jump. Past a couple of seconds it is an event — a loop, a wake, a page that
		/// reloaded — and not something playing faster can close.
		///
		/// Deliberately not lower, though a second out of step is plainly visible. Seeking a streaming
		/// player costs a re-buffer, and a re-buffer is about as long as the error being corrected.
		static let seek = 2.0

		/// How much faster or slower a page runs while it is correcting.
		///
		/// A tenth is well inside what anybody sees. A hundred observers watching football were not
		/// spontaneously aware of speed changes up to twelve percent, and asked to discriminate they
		/// managed about nine — and that was with the sound on.
		static let nudge = 0.10

		/// How often the app re-states the epoch.
		///
		/// Nothing depends on this being quick, because the page is correcting itself in between. It
		/// exists so that a page which has just reloaded — a rotation, a reload interval, a display
		/// switched back on — is told again without anything having to notice that it reloaded.
		static let refresh = 2.0
	}

	private static var timer: Timer?

	/**
	Start stating the epoch, or stop if nothing is synced.
	*/
	static func restart() {
		timer?.invalidate()
		timer = nil

		// Once either way: a group that has just been dissolved has pages still holding an epoch, and
		// they have to be told to stop.
		broadcast()

		guard !Defaults[.syncGroups].isEmpty else {
			return
		}

		timer = Timer.scheduledTimer(withTimeInterval: Tolerance.refresh, repeats: true) { _ in
			Task { @MainActor in
				await tick()
			}
		}
	}

	/**
	Fix where this group's clock reads zero, from where its leader is now.

	Taken from the leader rather than from nothing, so joining a group does not send the display that
	was already playing back to the start of its video. Called when a group forms, and again whenever
	somebody drags a progress bar.
	*/
	static func anchor(_ leader: Display?, at position: Double? = nil) async {
		let key = Display.settingsKey(for: leader)

		let now: Double
		if let position {
			now = position
		} else {
			let scene = AppState.shared.scenes.first { $0.display == leader }
			now = await scene?.mediaClock()?.time ?? 0
		}

		Defaults[.syncEpochs][key] = Date().timeIntervalSince1970 - now
		restart()
	}

	/**
	The epoch a display should be holding to, or `nil` when it is in no group.
	*/
	private static func epoch(for display: Display?) -> Double? {
		let key = Display.settingsKey(for: display)
		let groups = Defaults[.syncGroups]

		guard let leaderKey = groups[key] ?? (groups.values.contains(key) ? key : nil) else {
			return nil
		}

		return Defaults[.syncEpochs][leaderKey]
	}

	private static func broadcast() {
		for scene in AppState.shared.scenes {
			scene.setMediaEpoch(epoch(for: scene.display))
		}
	}

	/**
	State the epoch again, and adopt any drag somebody made in the meantime.

	A drag moves the group rather than being undone a quarter of a second later: whoever dragged
	becomes the new zero and every other display converges on it. Which is also what a progress bar
	on the panel would need, when there is one.
	*/
	private static func tick() async {
		for scene in AppState.shared.scenes {
			guard epoch(for: scene.display) != nil else {
				continue
			}

			if let scrubbed = await scene.scrubbedPosition() {
				let leader = SyncGroup.leader(of: scene.display) ?? scene.display
				await anchor(leader, at: scrubbed)
				return
			}
		}

		broadcast()
	}
}
