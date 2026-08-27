import WebKit

/**
Keeping the same video at the same place on synced displays.

Each display is its own web view with its own decoder, so this is not one source shown twice — it is
two players told to agree. Frame-exact is not on offer and is not claimed: independent decoders,
independent compositing, no genlock, and `currentTime` itself reads to about a frame. What is on offer
is that nobody standing between two screens can see them disagree.

**Swift is the hub, and has to be.** Since every website has its own `WKWebsiteDataStore`, the pages
share no storage at all — `BroadcastChannel`, `localStorage`, `SharedWorker` and service workers are
partitioned per store, so the two pages have no way to speak to each other. The app is the only thing
that can see both.

The script rides in `.defaultClient` alongside the audio control, because that is the only world the
app can talk back to: `addJavaScript` puts each script in a fresh anonymous world, which is
write-only from Swift. `forMainFrameOnly: false` puts a copy inside the framed player too, where the
media element is same-origin and can simply be read — which is why this needs no YouTube IFrame API.
That API could not do the job anyway: `setPlaybackRate` only accepts the discrete rates the player
offers, and there is no 1.02 among them.
*/
@MainActor
enum MediaSync {
	/**
	Thresholds, together, because they are the part that wants tuning against real screens.
	*/
	enum Tolerance {
		/// Above this, start correcting. Two screens side by side do not show a sixth of a second.
		static let engage = 0.15

		/// Below this, stop correcting. Separate from `engage` on purpose: one threshold for both
		/// makes the correction switch on and off around the same number, and every switch costs a
		/// visible hitch on WebKit — `playbackRate` interrupts playback for a moment on each change
		/// there (WebKit bug 208142, which dash.js works around by refusing rate changes under 0.25 on
		/// Safari). With a gap between the two, one correction is one rate change in and one out.
		static let release = 0.03

		/// Above this, jump. Past a couple of seconds it is an event — a loop, a wake, a page that
		/// reloaded — and not something playing faster can close.
		///
		/// Deliberately not lower, though a second out of step is plainly visible. Seeking a streaming
		/// player costs a re-buffer, and a re-buffer is about as long as the error being corrected:
		/// measured against Bilibili on two displays, jumping every five seconds held the gap at 1.2
		/// seconds indefinitely, because each seek landed and then lost exactly what it had gained.
		/// Below this threshold the only thing that actually converges is running faster.
		static let seek = 2.0

		/// How much faster or slower a follower runs while it is correcting.
		///
		/// One value rather than a proportional law, because on WebKit every change of rate costs a
		/// hitch, so the cheapest correction is the one that changes rate twice: on and off.
		///
		/// A tenth is well inside what anybody sees. A hundred observers watching football were not
		/// spontaneously aware of speed changes up to twelve percent, and asked to discriminate they
		/// managed about nine — and that was with the sound on. A follower here is always silent, so
		/// only the picture is on the line. Two percent, which is where this started, closed a second
		/// in the better part of a minute: slower than the stalls that opened it.
		static let nudge = 0.10

		/// How often to compare.
		///
		/// It was five seconds, on the reasoning that a wallpaper has nowhere to be. That is a
		/// disturbance arriving every few seconds into a loop that samples slower than the
		/// disturbance, which cannot converge whatever the correction is — measured, it sat a second
		/// behind for two minutes. The systems that do this for a living sample far faster than this:
		/// the W3C MediaSync reference at 100ms, dash.js on every `timeupdate`.
		static let period = 1.0

		/// Quiet after a jump, so the seek can land before it is judged again.
		static let settle = 3.0
	}

	private static var timer: Timer?
	private static var quietUntil = [Website.ID: Date]()

	/**
	Start comparing, or stop if nothing is synced.
	*/
	static func restart() {
		timer?.invalidate()
		timer = nil

		guard !Defaults[.syncGroups].isEmpty else {
			return
		}

		timer = Timer.scheduledTimer(withTimeInterval: Tolerance.period, repeats: true) { _ in
			Task { @MainActor in
				await tick()
			}
		}
	}

	private static func tick() async {
		var scenesByDisplay = [String: WallpaperScene]()

		for scene in AppState.shared.scenes {
			scenesByDisplay[Display.settingsKey(for: scene.display)] = scene
		}

		// Grouped by leader rather than by "some group id the members share", because the stored
		// relation is follower-to-leader: a leader has no entry of its own, so grouping on the raw
		// values left every leader out of its own group and every group one scene short of comparing.
		for (leaderDisplay, entries) in Dictionary(grouping: Defaults[.syncGroups], by: \.value) {
			guard let leader = scenesByDisplay[leaderDisplay] else {
				continue
			}

			let followers = entries.compactMap { scenesByDisplay[$0.key] }

			if !followers.isEmpty {
				await align(leader: leader, followers: followers)
			}
		}
	}

	/**
	The leader is never corrected; its followers are moved to it.

	Which display leads is stored rather than worked out from the order scenes happen to be in — two
	followers correcting towards each other chase a moving target and never settle.
	*/
	private static func align(leader: WallpaperScene, followers: [WallpaperScene]) async {
		guard let clock = await leader.mediaClock() else {
			return
		}

		let sampledAt = Date()

		for follower in followers {
			guard
				let websiteID = follower.website?.id,
				quietUntil[websiteID].map({ $0 < Date() }) ?? true
			else {
				continue
			}

			// Where the leader will be by the time this lands, not where it was when it was read. The
			// gap between the two is tens of milliseconds — the same order as the dead zone, so leaving
			// it out would bake in an offset the dead zone then hides.
			let target = clock.time + Date().timeIntervalSince(sampledAt)

			// Quiet after a jump, so the seek can land before it is judged again.
			if await follower.alignMedia(to: target, duration: clock.duration) {
				quietUntil[websiteID] = Date().addingTimeInterval(Tolerance.settle)
			}
		}
	}

	/**
	Forget what was quiet. Called when the group changes, so a display joining does not wait out a
	settle it was never part of.
	*/
	static func forgetQuietPeriods() {
		quietUntil.removeAll()
	}
}
