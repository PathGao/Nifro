import Foundation
import Testing
@testable import NifroLogic

/**
The two rules of the management page that are silent when they are broken.

Everything else on that page reports itself. A rename that does not write shows the old name. A drag
that does not stick springs back. A delete that misses leaves the row where it was. These two do not:
both of them draw exactly what the user expected, and the damage arrives later, in another window, as
something that reads like a different bug entirely.

**A shallow duplicate.** `Playlist.websites` holds bodies rather than ids, so a copy that hands back
the members it was given produces two rows over one set of websites. It compiles, the copy has the
right name and the right count, reordering one list leaves the other alone — and then cropping a page
in one changes it in the other, which is the one thing duplication exists to make possible. The user's
report is "changing the crop on one screen changed the other screen", and nothing in it points at
duplication.

**A bound default playlist.** The default is what a display with no choice of its own shows. Bind it
to one display and every other display's picker is empty: nothing to select, nothing on that screen,
and no way back out from the panel, because the entry that would have got them out is the one now
held back. Nothing fails at the moment of binding. The screen that goes blank is a different screen,
possibly on a different day, and the control that caused it is three levels into a menu on a row about
something else.

The first is runnable, because it was made runnable: `withFreshIDs` is generic and lives in the
package target for exactly this. The second is a claim about source, on `WORKSPACE_GUIDE.md`'s
criterion — the refusal is a property of a type that reaches `Defaults`, which this target does not
compile, and the thing worth pinning is that no route around the refusal is added rather than that one
particular call returns one particular value.
*/
@Suite("A copy is a copy, and the default playlist is nobody's")
struct PlaylistRulesTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func source(named name: String) throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		guard
			let url = FileManager.default
				.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
				.compactMap({ $0 as? URL })
				.first(where: { $0.lastPathComponent == name })
		else {
			Issue.record("\(name) is gone from Nifro/, so this test is reading nothing.")
			return ""
		}

		return try String(contentsOf: url, encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	private struct Member: Equatable {
		var id: UUID
		var crop: String
	}

	@Test("Every member of a copy is a new member")
	func duplicationIsDeep() {
		let members = [
			Member(id: UUID(), crop: "top left"),
			Member(id: UUID(), crop: "whole page")
		]

		let copies = withFreshIDs(members, id: \.id)

		#expect(copies.count == members.count)
		#expect(copies.map(\.crop) == members.map(\.crop), "A copy keeps every setting; only identity changes.")

		let originalIDs = Set(members.map(\.id))

		for copy in copies {
			#expect(
				!originalIDs.contains(copy.id),
				"""
				A copied member kept its original id, so both lists now hold one website. Editing either \
				row edits the other, and the data store, the thumbnail and the remembered scroll \
				position are shared as well — all of it filed under the id this was supposed to change.
				"""
			)
		}

		#expect(Set(copies.map(\.id)).count == copies.count, "Two members of one copy share an id.")
	}

	/**
	Copying the same list twice gives two different lists.

	Written out because the cheap wrong fix for the test above is one fresh id reused for every member,
	and the second cheap wrong fix is an id derived from the original — both of which pass a check that
	only compares a copy against what it came from.
	*/
	@Test("Copying twice does not give the same copy twice")
	func duplicationDoesNotRepeatItself() {
		let members = [Member(id: UUID(), crop: "top left")]

		let first = withFreshIDs(members, id: \.id)
		let second = withFreshIDs(members, id: \.id)

		#expect(first != second)
	}

	/**
	The ids come from the caller's supply, in order, one per member.

	`next` is a parameter so that this can be checked rather than inferred from ids being different:
	an implementation that copies the first member and repeats it would satisfy every assertion above
	that does not look at how many ids it asked for.
	*/
	@Test("One new id is taken per member")
	func oneIDPerMember() {
		let supply = [UUID(), UUID(), UUID()]
		var handed = 0

		let members = (0..<3).map { Member(id: UUID(), crop: "\($0)") }
		let copies = withFreshIDs(members, id: \.id) {
			defer { handed += 1 }
			return supply[handed]
		}

		#expect(handed == 3)
		#expect(copies.map(\.id) == supply)
	}

	/**
	The duplicate the user gets is the one this file tests.

	The assertions above are about a function; this is about it being the one on the path. Periphery
	catches the case where nothing calls it at all, and this catches the case where something else does
	the copying beside it.
	*/
	@Test("The playlist copy is made with it")
	func theCopyOnThePathUsesIt() throws {
		#expect(try Self.source(named: "Playlist.swift").contains("withFreshIDs("))
	}

	/**
	Every write to a playlist's binding asks first whether it is the default one.

	Absolute, with no allowlist, and phrased against the assignment rather than against a caller: the
	refusal is worth nothing if a third way in is added later, and a third way in is what a screen
	needing to set a binding will reach for. `private(set)` is what keeps the search to one file; the
	two writers inside it are the initializer, which drops a binding handed to the default playlist, and
	`bind(to:)`, which returns without writing.

	The menu item being disabled is not counted as a guard here on purpose. A disabled control is the
	honest half — it stops the user reaching a state they cannot get out of — but it is drawn by a view
	and can be lost to a refactor of that view, and what it protects is not on the screen it lives on.
	*/
	@Test("Nothing binds a playlist without asking whether it is the default")
	func theDefaultPlaylistRefusesADisplay() throws {
		let playlist = try Self.source(named: "Playlist.swift")

		#expect(
			playlist.contains("private(set) var boundDisplay"),
			"`boundDisplay` is writable from outside `Playlist.swift`, so the refusal below can be gone around without touching it."
		)

		let assignment = try Regex("boundDisplay\\s*=[^=]")
		let writes = playlist.matches(of: assignment)

		#expect(!writes.isEmpty, "Nothing assigns `boundDisplay` any more, so this test is reading nothing.")

		for write in writes {
			// The assignment and the question can be one line — the initializer's ternary — or four, as in
			// `bind(to:)`, where the question is the guard above it. A window rather than a line.
			let start = playlist.index(write.range.lowerBound, offsetBy: -120, limitedBy: playlist.startIndex)
			let statement = String(playlist[(start ?? playlist.startIndex)..<write.range.upperBound])

			#expect(
				statement.contains("isDefault"),
				"""
				A write to `boundDisplay` that does not ask `isDefault` first. The default playlist is \
				what a display with no choice of its own shows, so binding it to one display empties \
				every other display's picker — nothing to select, nothing on that screen, and no way \
				back from the panel. Around: \(statement)
				"""
			)
		}
	}
}
