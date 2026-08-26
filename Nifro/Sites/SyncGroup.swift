import Defaults
import Foundation

/**
Displays that show the same thing.

Two screens on one website are two website entries, each with its own crop, its own sound and its own
zoom — that is what lets a 27-inch and a 14-inch show the same page at the same *physical* size, with
the big one simply showing more of it. Syncing does not undo that; it says the two entries are the
same wallpaper, so a change to one is a change to both, and switching website on one switches the
other.

A group is a set of displays rather than a link between two, because "A follows B" and "B follows A"
are the same statement and storing it twice is how they come to disagree.
*/
enum SyncGroup {
	/**
	Whether a mirror is already under way. See `mirrorAcrossSyncGroup`.
	*/
	@MainActor
	fileprivate static var isMirroring = false

	/**
	The displays synced with `display`, itself excluded.
	*/
	@MainActor
	static func peers(of display: Display?) -> [Display?] {
		let key = Display.settingsKey(for: display)

		guard let group = Defaults[.syncGroups][key] else {
			return []
		}

		let peerKeys = Defaults[.syncGroups].filter { $0.value == group && $0.key != key }.keys

		return AppState.shared.scenes.map(\.display).filter {
			peerKeys.contains(Display.settingsKey(for: $0))
		}
	}

	/**
	Whether `display` is synced with anything.
	*/
	@MainActor
	static func isSynced(_ display: Display?) -> Bool {
		!peers(of: display).isEmpty
	}

	/**
	Put `display` in the same group as `other`.

	Both groups merge rather than one joining the other, so syncing A to B when B is already with C
	leaves all three together. The alternative — B quietly leaving C — is the kind of thing a menu of
	two-way links does, and the reason this is a set.
	*/
	@MainActor
	static func join(_ display: Display?, with other: Display?) {
		let key = Display.settingsKey(for: display)
		let otherKey = Display.settingsKey(for: other)

		var groups = Defaults[.syncGroups]
		let target = groups[otherKey] ?? groups[key] ?? UUID().uuidString

		let merging = Set([groups[key], groups[otherKey]].compactMap(\.self))

		for (existing, group) in groups where merging.contains(group) {
			groups[existing] = target
		}

		groups[key] = target
		groups[otherKey] = target

		Defaults[.syncGroups] = groups
	}

	/**
	Take `display` out of whatever group it is in.

	A group of one is no group, so the last display left behind is dropped too rather than kept as a
	set with nothing to be the same as.
	*/
	@MainActor
	static func leave(_ display: Display?) {
		let key = Display.settingsKey(for: display)

		var groups = Defaults[.syncGroups]

		guard let group = groups.removeValue(forKey: key) else {
			return
		}

		let remaining = groups.filter { $0.value == group }

		if remaining.count < 2 {
			for (key, _) in remaining {
				groups.removeValue(forKey: key)
			}
		}

		Defaults[.syncGroups] = groups
	}
}

extension WebsitesController {
	/**
	Make every display synced with `display` show what it is showing.

	Copies the whole entry except the two things that are the entry's identity rather than its
	contents: `id`, and `display` itself. Copying `display` would move the website instead of mirroring
	it, and copying `id` would make two entries the same entry.

	`zoom` is copied like everything else, which is the one that looks wrong and is not. A region is
	stored as a centre and a magnification, not a rectangle, so the same value on a wider screen shows
	the same part of the page across a wider view — which is exactly what "the same wallpaper on both"
	should mean. A screen that wants its own framing leaves the group.

	Creating the peer's entry when it has none is deliberate: syncing a display that was empty should
	fill it, and the alternative is a group where one member silently shows nothing.
	*/
	@MainActor
	func mirrorAcrossSyncGroup(from display: Display?) {
		// Mirroring writes to the peers, and writing to a peer is exactly what asks for a mirror. Without
		// this the first sync would bounce between the two displays until the stack ran out.
		guard !SyncGroup.isMirroring else {
			return
		}

		SyncGroup.isMirroring = true

		defer {
			SyncGroup.isMirroring = false
		}

		let peers = SyncGroup.peers(of: display)

		guard
			!peers.isEmpty,
			let source = scheduled(for: display)
		else {
			return
		}

		for peer in peers {
			var copy = source
			copy.display = peer
			copy.isCurrent = true

			if let existing = scheduled(for: peer) {
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
