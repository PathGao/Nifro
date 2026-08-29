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
	Every stored website becomes a member, and nothing between the read and the write can drop one.

	This used to be a runnable test over a pure grouping function, and it was the assertion that file
	was for. The grouping is gone — everything lands in one playlist now — and with it went the seam
	that made the property testable by running it. Checked here anyway, and against the source, because
	the property did not go away with the function: this runs once, against the only copy of a list the
	user built by hand, and an entry it drops is dropped for good.

	Stated as an absence, which is what a shape test is the right tool for. The names below are every
	way Swift has to return fewer elements than it was given, and the migration uses none of them: the
	stored list goes into the playlist as it came out of the key. It used to go through a
	`stored.map(\.website)`, unwrapping a type that carried the display each website was pinned to — a
	`map` cannot lose an entry either, but it was a step that did nothing and a step is a place a
	`compactMap` gets typed by mistake.
	*/
	@Test("The migration cannot drop a website on its way into the playlist")
	func migrationKeepsEveryStoredWebsite() throws {
		let body = try Self.body(
			of: "func migrateToPlaylistsIfNeeded()",
			in: Self.source("Nifro/Sites/WebsitesController.swift")
		)

		for losing in ["filter", "compactMap", "dropFirst", "dropLast", "prefix", "suffix", "first", "removeAll"] {
			#expect(
				!body.contains(".\(losing)"),
				"""
				The migration calls `.\(losing)` between reading the stored list and writing the \
				playlists. Every stored website has to become a member: this is the only copy of a list \
				the user built themselves, and it runs once.
				"""
			)
		}

		#expect(body.contains("websites: stored"), "The migration no longer puts the stored list into the playlist whole, so what it writes is not all of what it read.")
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
	The flag reset stays out of the shared ordering.

	`prepareWebsiteStorage` exists so the migrate-then-install order is written once instead of twice.
	The reason it is not simply the body of `installDefaultPlaylist` is one line: that method first
	forces `hasInstalledFeaturedWebsites` back to false, which is what its own caller wants — the
	Advanced pane's button, which must be able to reinstall a set the flag says is already installed. On
	the launch path the same line reinstalls the shipped websites on every run, including the ones the
	user has deleted.

	So the trap is not the ordering, it is the tidying-up that comes for it later: folding that line into
	the shared method reads like finishing the extraction and is silent when it lands, because a fresh
	install cannot tell the difference. Asserted on both bodies rather than one, so moving the line
	fails rather than only removing it.
	*/
	@Test("The shared ordering does not carry the flag reset")
	func theFlagResetStaysWithItsOwnCallers() throws {
		let controller = try Self.source("Nifro/Sites/WebsitesController.swift")
		let shared = try Self.body(of: "func prepareWebsiteStorage()", in: controller)
		let install = try Self.body(of: "func installDefaultPlaylist()", in: controller)

		#expect(!shared.isEmpty)
		#expect(!install.isEmpty)

		#expect(
			!shared.contains("hasInstalledFeaturedWebsites"),
			"The shared ordering resets the installed flag, so launching reinstalls the shipped websites every run — including the ones the user deleted."
		)

		#expect(
			install.contains("hasInstalledFeaturedWebsites"),
			"`installDefaultPlaylist` no longer resets the installed flag, so the Advanced pane's button silently does nothing once the shipped websites have been installed once."
		)
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
