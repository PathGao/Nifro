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
		/// Below this, do nothing. Two screens side by side do not show a sixth of a second.
		static let ignore = 0.15

		/// Above this, jump. Past a couple of seconds it is an event — a stall, a loop, a wake — and
		/// not drift, and nudging would take minutes to catch up.
		static let seek = 2.0

		/// How much faster or slower a follower runs while catching up. Invisible on screen and under a
		/// third of a semitone, which WebKit corrects for anyway.
		static let nudge = 0.02

		/// How often to compare. A wallpaper has nowhere to be.
		static let period = 5.0

		/// Quiet after a jump, so the seek can land before it is judged again.
		static let settle = 5.0
	}

	private static var timer: Timer?
	private static var quietUntil = [Website.ID: Date]()

	/**
	Which followers have been put in step at least once.

	The nudge is for drift, and drift is small. What two players start with is not drift: they are
	loaded separately and each begins wherever it begins, which measured about a second apart — and a
	second closed at two percent takes the better part of a minute, during which the two screens are
	visibly out of step. So the first alignment jumps, and every one after it nudges.
	*/
	private static var aligned = Set<Website.ID>()

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
		let groups = Dictionary(grouping: AppState.shared.scenes) {
			Defaults[.syncGroups][Display.settingsKey(for: $0.display)]
		}

		for (group, scenes) in groups where group != nil && scenes.count > 1 {
			await align(scenes)
		}
	}

	/**
	The first scene leads and is never corrected; the rest follow.

	A fixed leader rather than "whoever reported first". Two followers correcting towards each other
	chase a moving target and never settle.
	*/
	private static func align(_ scenes: [WallpaperScene]) async {
		guard
			let leader = scenes.first,
			let clock = await leader.mediaClock()
		else {
			return
		}

		let sampledAt = Date()

		for follower in scenes.dropFirst() {
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

			let isFirst = !aligned.contains(websiteID)
			let seeked = await follower.alignMedia(
				to: target,
				duration: clock.duration,
				// One jump to get in step, then never again unless something knocks it out.
				jumpingRegardless: isFirst
			)

			// Marked only when a jump actually landed. Marking it on the attempt spent the one free jump
			// on a page whose video had not loaded yet — measured, and it left the two a second apart
			// for the next minute.
			if seeked {
				aligned.insert(websiteID)
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

		// A display joining a group has never been put in step, whatever it did in a previous one.
		aligned.removeAll()
	}
}
