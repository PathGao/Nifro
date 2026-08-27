import Defaults
import Foundation

/**
Displays that show the same thing, and which one decides.

Two screens on one website are two website entries, each with its own crop, its own sound and its own
zoom — that is what lets a 27-inch and a 14-inch show the same page at the same *physical* size, with
the big one simply showing more of it. Syncing does not undo that; it says the two entries are the
same wallpaper, so a change to one is a change to both.

**The display that asks becomes the follower.** Picking "sync with B" on A is A saying *show me what B
shows*, so A stops deciding and B carries on as it was. Stored that way too: an entry maps a follower
to its leader, which makes "who follows whom" a fact rather than something derived from the order
displays happen to be in.
*/
enum SyncGroup {
	/**
	Whether a mirror is already under way. See `mirrorAcrossSyncGroup`.
	*/
	@MainActor
	fileprivate static var isMirroring = false

	/**
	The display `display` is following, or `nil` when it leads or is alone.
	*/
	@MainActor
	static func leader(of display: Display?) -> Display? {
		guard let key = Defaults[.syncGroups][Display.settingsKey(for: display)] else {
			return nil
		}

		return AppState.shared.scenes
			.first { Display.settingsKey(for: $0.display) == key }?
			.display
	}

	/**
	The displays following `display`.
	*/
	@MainActor
	static func followers(of display: Display?) -> [Display?] {
		let key = Display.settingsKey(for: display)

		return AppState.shared.scenes.map(\.display).filter {
			Defaults[.syncGroups][Display.settingsKey(for: $0)] == key
		}
	}

	/**
	Everything showing what `display` shows, or showing what it shows — itself excluded.
	*/
	@MainActor
	static func peers(of display: Display?) -> [Display?] {
		if let leader = leader(of: display) {
			// A follower's peers are its leader and its leader's other followers.
			return [leader] + followers(of: leader).filter {
				Display.settingsKey(for: $0) != Display.settingsKey(for: display)
			}
		}

		return followers(of: display)
	}

	/**
	Make `display` follow `other`.

	Anything that was following `display` is handed over rather than left pointing at a display that no
	longer decides anything — a chain of followers is a group that disagrees with itself.
	*/
	@MainActor
	static func follow(_ display: Display?, following other: Display?) {
		let key = Display.settingsKey(for: display)
		let otherKey = Display.settingsKey(for: other)

		guard key != otherKey else {
			return
		}

		var groups = Defaults[.syncGroups]

		// The new leader cannot itself be a follower, or the group would have two opinions.
		groups.removeValue(forKey: otherKey)

		for (follower, leader) in groups where leader == key {
			groups[follower] = otherKey
		}

		groups[key] = otherKey
		Defaults[.syncGroups] = groups
	}

	/**
	Stop `display` following anything.
	*/
	@MainActor
	static func leave(_ display: Display?) {
		Defaults[.syncGroups].removeValue(forKey: Display.settingsKey(for: display))
	}

	/**
	Release everything that follows `display`.
	*/
	@MainActor
	static func releaseFollowers(of display: Display?) {
		let key = Display.settingsKey(for: display)
		Defaults[.syncGroups] = Defaults[.syncGroups].filter { $0.value != key }
	}
}

extension WebsitesController {
	/**
	Make every display following `display` show what it is showing.

	Copies the whole entry except the two things that are the entry's identity rather than its
	contents: `id`, and `display` itself. Copying `display` would move the website instead of mirroring
	it, and copying `id` would make two entries the same entry.

	`zoom` is copied like everything else, which is the one that looks wrong and is not. A region is
	stored as a centre and a magnification, not a rectangle, so the same value on a wider screen shows
	the same part of the page across a wider view — which is exactly what "the same wallpaper on both"
	should mean. A screen that wants its own framing stops following.

	Creating a follower's entry when it has none is deliberate: syncing a display that was empty should
	fill it, and the alternative is a group where one member silently shows nothing.
	*/
	@MainActor
	func mirrorAcrossSyncGroup(from display: Display?) {
		// Mirroring writes to the followers, and writing to a follower is exactly what asks for a mirror.
		// Without this the first sync would bounce until the stack ran out.
		guard !SyncGroup.isMirroring else {
			return
		}

		SyncGroup.isMirroring = true

		defer {
			SyncGroup.isMirroring = false
		}

		// A follower has nothing to say; what it shows is decided by the display it follows.
		let source = SyncGroup.leader(of: display) ?? display

		guard
			let leading = scheduled(for: source),
			!SyncGroup.followers(of: source).isEmpty
		else {
			return
		}

		for follower in SyncGroup.followers(of: source) {
			var copy = leading
			copy.display = follower
			copy.isCurrent = true

			if let existing = scheduled(for: follower) {
				copy.id = existing.id
				update(existing.id) { $0 = copy }
			} else {
				copy.id = UUID()
				all.append(copy)
			}

			if let mirrored = all[id: copy.id] {
				makeCurrent(mirrored)
			}
		}
	}
}
