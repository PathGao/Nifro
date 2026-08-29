import Foundation
import Testing
@testable import NifroLogic

/**
Where the user's websites live, and what must not overwrite them.

`playlists` is the whole of it. There is no second copy and no conversion into it any more: the
pre-playlist `websites` key and the migration that read it are deleted, along with every other
migration in this app.

What is left to guard is the install. The shipped websites are laid in once, behind a flag, and the
one thing that would put them back over a list the user has since edited is that flag being reset on
the launch path — which is exactly what `installDefaultPlaylist` does on purpose, for its own caller.
The claim can only be made about the source, because `Defaults` and `Website` are not in the package
target; `WebsiteDecodingTests` next door makes that argument in full and it holds here unchanged.
*/
@Suite("Where the website list is stored")
struct PlaylistStorageTests {
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
	The flag reset stays out of the shared ordering.

	`prepareWebsiteStorage` is the install and nothing else now. The reason it is not simply the body
	of `installDefaultPlaylist` is one line: that method first
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
