import Foundation
import Testing
@testable import NifroLogic

/**
The guardrail on the one conversion that cannot be run twice.

There is no upgrade mechanism in this app — roadmap E23 says so — and this is the change that needs
one. The website list is not derived from anything: the user typed the addresses, cropped the pages,
wrote the CSS and put them in the order they wanted. Turning that list into playlists happens once,
on whichever launch first has the new build, and every way it can go wrong is silent. A website left
out of every group is a website gone. A group built in the wrong order is a list the user did not
write. Neither throws, neither logs, and neither can be told from "that is what was there" by anybody
who was not looking beforehand.

Which is why the grouping is a function over plain values in `Sites/PlaylistMigration.swift` and this
suite runs it. The rest of the conversion — reading the stored list, asking a display for its name,
writing the new key — needs `Website`, `Defaults` and `NSScreen`, none of which the package target
compiles and none of which this change is entitled to move; `WebsiteMigrationTests` next door makes
that argument in full and it holds here unchanged. So the parts of the claim that can only be made
about the source are made about the source, at the bottom of this file, and they are the two that
would cost the most: that the migration knows it has already run, and that it does not overwrite what
it is reading.
*/
@Suite("The website list survives becoming playlists")
struct PlaylistMigrationTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	Every website ends up in exactly one playlist.

	The assertion the whole file is for, and the one whose failure is invisible. It is stated over the
	indices rather than over a particular list because "which website" is not what can go wrong here —
	dropping one is, and a dropped one is only detectable by counting what came out against what went
	in.

	The lists below are the shapes a stored list actually comes in: nothing pinned, everything pinned,
	a mixture, one display used twice, and the same again with the pinned entries first so that the
	default group is not simply the one that started.
	*/
	@Test("No website is lost, duplicated or invented, whatever the list looked like")
	func everyWebsiteLandsInExactlyOnePlaylist() {
		let lists: [[Int?]] = [
			[],
			[nil],
			[nil, nil, nil],
			[1, 2],
			[nil, 1, nil, 2, 1],
			[1, 1, nil],
			[2, 2, 2],
			[nil, 3, 3, nil, 1, 2, 1]
		]

		for list in lists {
			let landed = playlistMigration(displays: list).flatMap(\.websites)

			#expect(
				landed.sorted() == Array(list.indices),
				"A list of \(list.count) came back as \(landed.sorted()), so a website was lost, duplicated or invented."
			)
		}
	}

	/**
	There is always a default playlist, and it is the first one.

	Unconditional, which is the part worth running: the tempting version builds it from the websites
	that have no display, and then a user who pinned every website they own gets a set of playlists
	that are all bound to something. Every display they later add has an empty picker — nothing to
	select, nothing on the screen — and the panel has no way out of it.
	*/
	@Test("A default playlist exists even when every website was pinned")
	func theDefaultGroupIsAlwaysFirstAndAlwaysThere() {
		for list in [[], [1, 2, 3], [nil, 1], [nil]] as [[Int?]] {
			let groups = playlistMigration(displays: list)

			#expect(groups.first?.screen == nil, "The first group is not the unbound one, so nothing makes the default playlist.")
			#expect(groups.count >= 1)
		}

		#expect(playlistMigration(displays: [] as [Int?]).count == 1, "An empty list should still produce the default playlist and nothing else.")
		#expect(playlistMigration(displays: [1, 2] as [Int?]).first?.websites.isEmpty == true)
	}

	/**
	A website with no display of its own goes in the default playlist, and one with a display does not.

	The rule the migration is described by, checked directly rather than inferred from the counts
	above.
	*/
	@Test("Pinned websites leave the default playlist and unpinned ones stay in it")
	func pinningDecidesTheGroup() {
		let groups = playlistMigration(displays: [nil, 1, nil, 2, 1])

		#expect(groups.first?.websites == [0, 2])
		#expect(groups.count == 3)
		#expect(groups[1].screen == 1)
		#expect(groups[1].websites == [1, 4])
		#expect(groups[2].screen == 2)
		#expect(groups[2].websites == [3])
	}

	/**
	The order the user put their websites in is the order they come out in.

	Both orders: the websites inside a playlist, and the playlists themselves, which follow the order
	the list first mentions each display. Nobody asked the user about either, so changing either is
	changing their list without being asked.
	*/
	@Test("Websites and playlists keep the order the stored list had")
	func orderIsPreserved() {
		let groups = playlistMigration(displays: [3, nil, 1, 3, 1, nil, 2])

		#expect(groups.map(\.screen) == [nil, 3, 1, 2], "The displays are not in the order the list first names them.")
		#expect(groups.map(\.websites) == [[1, 5], [0, 3], [2, 4], [6]], "A group has its websites in an order the stored list did not have.")
	}

	/**
	One display named twice is one playlist, not two.

	`Display` is a UUID wrapped in a struct, so equality is the display and nothing else. Grouping on
	something that compared identity instead — the `NSScreen`, say, which is a different object each
	time the screens are reconfigured — would give the user a playlist per website.
	*/
	@Test("The same display twice makes one playlist")
	func equalDisplaysShareAPlaylist() {
		let groups = playlistMigration(displays: [1, 1, 1] as [Int?])

		#expect(groups.count == 2)
		#expect(groups[1].websites == [0, 1, 2])
	}

	// MARK: - What can only be said about the source

	private static func source(_ path: String) throws -> String {
		let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return text.replacing(block, with: "").replacing(line, with: "")
	}

	/**
	The body of a declaration, from its opening brace to the brace that closes it.

	Counted rather than matched with a regex, for the reason `ScopeTests` gives: the bodies below hold
	braces of their own, and a pattern stopping at the first `}` reads a guard clause as the whole
	function.
	*/
	private static func body(of declaration: String, in source: String) throws -> String {
		guard
			let start = source.range(of: declaration),
			let open = source[start.upperBound...].firstIndex(of: "{")
		else {
			Issue.record("`\(declaration)` is gone, so this test is reading nothing.")
			return ""
		}

		var depth = 0

		for index in source.indices[open...] {
			if source[index] == "{" {
				depth += 1
			} else if source[index] == "}" {
				depth -= 1

				if depth == 0 {
					return String(source[open...index])
				}
			}
		}

		Issue.record("`\(declaration)` has no closing brace, so this test is reading nothing.")
		return ""
	}

	/**
	The migration knows it has already run from a flag, and not from the playlists being empty.

	An empty playlist list is a state the user reaches by ordinary use and can sit in, so a guard that
	read it as "not done yet" would rebuild their playlists out of a website list they stopped editing
	long ago — every launch, for as long as they left it that way, silently undoing whatever they had
	arranged. The failure has no error and no half-state: the app simply keeps putting their old list
	back.

	Anchored on the key rather than on the shape of the guard, so that rewriting the guard cannot pass
	by accident and deleting the key cannot pass at all.
	*/
	@Test("The migration is guarded by a flag of its own")
	func migrationKnowsItHasRun() throws {
		let controller = try Self.source("Nifro/Sites/WebsitesController.swift")
		let migration = try Self.body(of: "func migrateToPlaylistsIfNeeded()", in: controller)

		#expect(
			migration.contains("guard !Defaults[.hasMigratedWebsitesToPlaylists]"),
			"""
			The migration no longer returns early on its own flag. Whatever it checks instead, it now \
			runs more than once — and running it twice rebuilds the user's playlists from a website \
			list they may not have touched since.
			"""
		)

		#expect(
			migration.contains("Defaults[.hasMigratedWebsitesToPlaylists] = true"),
			"The migration never records that it ran, so it runs on every launch for ever."
		)

		#expect(
			!migration.contains("Defaults[.playlists].isEmpty"),
			"The migration decides whether it has run by looking at what it wrote. An empty playlist list is a state the user can reach."
		)

		#expect(
			try Self.source("Nifro/App/Constants.swift").contains("Key<Bool>(\"hasMigratedWebsitesToPlaylists\""),
			"The flag's stored name changed, which means every user who has already migrated migrates again."
		)
	}

	/**
	The migration reads the website list and does not write it.

	`websites` has to stay exactly as it was until its last reader is gone: somebody who runs this
	build and goes back to the previous one still opens their list, and anything that looks wrong about
	the playlists can be checked against what they were made from. Both of those stop being true the
	first time this writes over the thing it is reading — and it would look fine, because the playlists
	it wrote would be right.
	*/
	@Test("Nothing in the migration writes over the website list")
	func theOldListIsLeftReadable() throws {
		let controller = try Self.source("Nifro/Sites/WebsitesController.swift")
		let migration = try Self.body(of: "func migrateToPlaylistsIfNeeded()", in: controller)

		#expect(!migration.isEmpty)

		for write in ["Defaults[.websites] =", "all =", "all.append", "all.remove"] {
			#expect(
				!migration.contains(write),
				"The migration writes the website list (`\(write)`), which is the one thing it must not do until nothing reads that key any more."
			)
		}
	}

	/**
	The default playlist cannot be bound to a display.

	The guard that keeps every display's picker non-empty, and it holds by being unreachable rather
	than by being remembered: the binding is settable only through `Playlist`'s own initializer, which
	drops it for the default playlist. Written as a plain `var`, the refusal would be a rule each of
	the management page, the panel and the migration had to know, and the failure — a display with an
	empty picker and nothing on the screen — has no way back out from the panel.
	*/
	@Test("A binding cannot be written onto the default playlist")
	func theDefaultPlaylistIsUnbindable() throws {
		let playlist = try Self.source("Nifro/Sites/Playlist.swift")

		#expect(
			playlist.contains("private(set) var boundDisplay"),
			"`boundDisplay` can be assigned from anywhere again, so nothing stops the default playlist being bound and a display being left with an empty picker."
		)

		#expect(
			playlist.contains("self.boundDisplay = isDefault ? nil : boundDisplay"),
			"The initializer no longer drops a binding handed to the default playlist, which is the only place that refusal is made."
		)
	}
}
