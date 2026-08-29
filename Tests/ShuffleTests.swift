import Foundation
import Testing

@testable import NifroLogic

/**
The order a shuffled display walks its websites in, and what a change to those websites does to it.

Random used to be random playback: an iterator that picked the next website when the last one ended.
Shuffle play is the other thing, and it is the one a wallpaper wants — the whole order is decided at
once, so it can be listed in the chooser, walked backwards, and finished. Everything about deciding one
and keeping it is a list and a mark, which is why it is in `Rotation.swift` and runnable here rather
than argued about in a comment: the rules read as obvious and two of them are not.

**What was actually wrong**, and it was worse than "the shuffle repeated". The iterator was thrown away
only when the flattened website ids across every playlist changed, which a playlist switch does not do.
So after a switch the iterator went on yielding the *old* list's websites; each tick wrote the mark to
a website the new playlist does not contain; `scheduled(for:)` read that as "this display has not
started" and answered with the top of the list; and the guard above the load saw no change and returned.
The display froze on the new playlist's first website, rotation looked dead, and a website picked by
hand was undone on the next tick. No page from the old list ever reached the screen either — the two
halves cancelled into stillness.

The suite below is in two parts. The rules are run. The two things that cannot be — `WebsitesController`
reaches `Defaults`, `SwiftUI` and `AppState`, and `Package.swift` compiles none of that — are asserted
against the source, on the criterion the other shape suites set out: pin the property that keeps the fix
true tomorrow, not the behaviour, and observe the behaviour on a running build.
*/
@Suite("A shuffled order is decided, not drawn")
struct ShuffleOrderTests {
	/**
	Every website is in the order, once, and none that was not.

	The promise shuffle play makes and random playback does not. Asserted as membership rather than as a
	particular permutation, because the permutation is the one thing here that is allowed to differ
	between two runs.
	*/
	@Test("A fresh order holds the same websites and no others")
	func theOrderIsAPermutation() {
		let ids = [1, 2, 3, 4, 5]
		let order = shuffledOrder(of: ids, startingWith: nil)

		#expect(order.count == ids.count)
		#expect(Set(order) == Set(ids))
	}

	/**
	The page already up heads the new order.

	Which is the whole of why a relaunch does not make the wallpaper jump: the order is not stored and
	the mark is, so the first tick of a session decides an order around what is already on screen. It
	is also what settles the end of a pass — the website the last pass ended on heads the next one, so
	the first step of a new pass cannot land back on the page that is up.
	*/
	@Test("An order starts at the website already showing")
	func theShowingWebsiteLeads() {
		let ids = [1, 2, 3, 4, 5]

		for id in ids {
			let order = shuffledOrder(of: ids, startingWith: id)

			#expect(order.first == id)
			#expect(Set(order) == Set(ids))
		}
	}

	/**
	A website the list does not hold names nothing to preserve.

	The ordinary state of a display nobody has picked for, and of one whose website was deleted. The
	cheap wrong implementation puts it at the front anyway and hands back a list with a website in it
	that the display cannot show.
	*/
	@Test("An unknown or absent website leaves the whole order shuffled")
	func anUnknownWebsiteIsNotPrepended() {
		let ids = [1, 2, 3]

		#expect(Set(shuffledOrder(of: ids, startingWith: 9)) == Set(ids))
		#expect(shuffledOrder(of: ids, startingWith: 9).count == 3)
		#expect(shuffledOrder(of: [], startingWith: 1).isEmpty)
	}

	/**
	A website that leaves drops out, and the rest keep their places.

	Forced rather than chosen — a display cannot show a website that is gone — but the *rest keeping
	their places* is the half worth pinning. Deciding the order again over a deletion is the behaviour
	this replaces, and it throws away a pass the user is halfway through every time they tidy a list.
	*/
	@Test("A removed website drops out and the order around it stands")
	func aRemovedWebsiteDropsOut() {
		#expect(orderCarriedForward([3, 1, 4, 2], through: [1, 2, 3]) == [3, 1, 2])
	}

	/**
	A website that arrives goes to the end.

	The rule the specification is explicit about, and the one a reasonable implementation gets wrong by
	reshuffling: shuffled in, a website added to the list you are watching lands somewhere the pass has
	already been through and is not seen for two rounds. Appended, it is coming.

	Two of them keep the order the playlist holds them in. There is nothing better to sort them by, and
	shuffling the newcomers among themselves would be a second, smaller shuffle inside a pass.
	*/
	@Test("An added website is appended, not shuffled in")
	func anAddedWebsiteIsAppended() {
		#expect(orderCarriedForward([3, 1, 2], through: [1, 2, 3, 4, 5]) == [3, 1, 2, 4, 5])
	}

	/**
	And both at once, which is what an ordinary edit looks like.
	*/
	@Test("A pass survives a website leaving and a website arriving together")
	func removalAndAdditionTogether() {
		#expect(orderCarriedForward([3, 1, 2], through: [2, 3, 4]) == [3, 2, 4])
	}

	/**
	Nothing left of the order means there is no order to carry.

	Which is what a playlist switch looks like from in here, and it is the reported defect in its
	smallest form. The implementation that keeps the survivors and appends the rest — correct for every
	case above — answers this one with the new playlist in its own list order and calls it a shuffle.
	*/
	@Test("An order with no survivors is not carried forward")
	func aDisjointListStartsAgain() {
		#expect(orderCarriedForward([1, 2, 3], through: [7, 8, 9]).isEmpty)
		#expect(orderCarriedForward([], through: [1, 2]).isEmpty)
		#expect(orderCarriedForward([1, 2], through: []).isEmpty)
	}

	/**
	A website is not in the order twice because it is both kept and eligible.

	The cheap implementation of "append what is new" appends everything eligible, and the order grows a
	second copy of every website it already held on the first edit after it was decided.
	*/
	@Test("Carrying an order forward does not duplicate what it already holds")
	func nothingIsCarriedTwice() {
		let carried = orderCarriedForward([2, 1, 3], through: [1, 2, 3])

		#expect(carried == [2, 1, 3])
		#expect(Set(carried).count == carried.count)
	}
}

/**
The two things about the order that `swift test` cannot run, pinned as shape.

`Package.swift` compiles eleven pure files. `WebsitesController.swift`, `RotationBehaviour.swift` and
`DisplayPanelModel.swift` are not among them and cannot be: they reach `Defaults`, `AppKit` and
`AppState`, so there is no controller here to point at a playlist, no display to key an order by, and
no panel to open. What is asserted instead is the property each fix rests on — where the question is
asked, and where the decision is made — because both are the kind that stay green while quietly moving
back to where they were.
*/
@Suite("Where the order is renewed, and where a display is committed")
struct ShuffleShapeTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The file with its prose taken out, for the reason the other shape suites give about their copies of
	this: the code below argues for itself at length and quotes the very expressions these assertions
	look for, so a match against the whole file would pass on the explanation of why the code is right.
	*/
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

	/**
	The body of a declaration, from its opening brace to the brace that closes it.

	Counted rather than matched with a regex, for the reason the other shape suites give: every body read
	below contains braces of its own, and a regex stopping at the first `}` would read a `guard` clause
	as the whole function.
	*/
	private static func body(of declaration: String, in source: String) -> String {
		guard let start = source.range(of: declaration) else {
			Issue.record("`\(declaration)` is no longer written that way, so this test is reading nothing.")
			return ""
		}

		guard let open = source[start.upperBound...].firstIndex(of: "{") else {
			Issue.record("`\(declaration)` has no body.")
			return ""
		}

		var depth = 0

		for index in source.indices[open...] {
			switch source[index] {
			case "{":
				depth += 1
			case "}":
				depth -= 1

				if depth == 0 {
					return String(source[open...index])
				}
			default:
				break
			}
		}

		Issue.record("`\(declaration)`'s body is unbalanced.")
		return ""
	}

	/**
	An order is asked whether it still describes its display where it is read, not where a key moves.

	Four things change what a display can show and only three of them write anything: a website added, a
	website deleted, the display pointed at another playlist, and a website falling in or out of its
	scheduled hours — which happens on the turn of the hour with no edit behind it and no publisher to
	fire. A reset hung off a publisher can only ever cover three, and the one it was hung off covered
	one and a half: it compared the flattened website ids across every playlist, which a playlist switch
	leaves identical and a drag that only reorders a list does not.

	Asked where the order is read, all four are one question. That is what the absence below is: nothing
	watches for this, because there is nothing to watch for.
	*/
	@Test("The order is renewed where it is read, and the shuffle is not an iterator")
	func theOrderIsCheckedWhereItIsUsed() throws {
		let controller = try Self.source(named: "WebsitesController.swift")

		#expect(
			!controller.contains("AnyIterator"),
			"The shuffled order is an iterator again. An iterator will not say what is coming, so the chooser cannot list it and Previous cannot walk back into it."
		)

		#expect(
			controller.contains("[String: ShuffledOrder]"),
			"""
			The order is no longer one entry per display key. Keyed by `Display?` it was keyed by a value \
			one screen has two of — `nil` and the main display — so a display reached under both names got \
			two orders over one list and stopped being able to promise no repeats.
			"""
		)

		let events = Self.body(of: "private func setUpEvents()", in: controller)

		#expect(
			!events.contains("oldValue"),
			"""
			The playlists sink decides something by comparing the list against the list before it. That is \
			how a stale order used to be found, and the comparison is blind to the change that was \
			reported — a playlist switch leaves every website in the app exactly where it was.
			"""
		)

		#expect(
			!events.contains("shuffledOrders"),
			"""
			A publisher decides when a shuffled order is stale again. No key moves when a website's hours \
			end, so that answer is missing a case whatever it watches.
			"""
		)

		let ordered = Self.body(of: "func ordered(", in: try Self.source(named: "RotationBehaviour.swift"))

		#expect(
			ordered.contains("orderCarriedForward("),
			"`ordered` no longer carries an order through a change to the websites, so an edit either restarts the pass or is not noticed at all."
		)

		#expect(
			ordered.contains("Display.settingsKey(for:"),
			"`ordered` keys the order by something other than the display, so what it reads and writes is not a per-display answer."
		)
	}

	/**
	Arriving at Random deals a new order, and arriving is not the same as being written.

	The order is held against the display and the playlist, and the mode is in neither — so it outlived
	the mode, and a three-way button pressed three times came back to Random in the middle of the pass
	it had left. That is the one change to a shuffled display a read cannot find for itself: the four
	`ordered` covers all move the set of websites, and this one moves nothing a later read could compare
	against.

	Both halves are pinned, and for different lengths of reason. Without the call, the mode button is
	the control that says "shuffle" and does not — that is a defect today. Without the mode in the
	condition, the setter drops an order on every write rather than on arriving at one, which no caller
	can tell apart right now because the only writer goes through `RotationMode.next`; it is pinned
	because the second writer is the one that would find out.
	*/
	@Test("Arriving at Random deals again, and only on arrival")
	func arrivingAtRandomDropsTheOrder() throws {
		let setter = Self.body(
			of: "var rotationMode: RotationMode",
			in: try Self.source(named: "RotationBehaviour.swift")
		)

		#expect(
			setter.contains("forgetOrder("),
			"""
			Setting the mode no longer drops the held order, so leaving Random and coming back resumes \
			the pass the user left instead of dealing a new one — and the mode button is the only \
			gesture that reads as "shuffle again".
			"""
		)

		#expect(
			setter.contains(".random"),
			"""
			The order is dropped on every write of the mode rather than on arriving at Random. Restore \
			writes these from a dictionary, so an unconditional drop reshuffles displays nobody touched.
			"""
		)
	}

	/**
	Where a display is standing is one answer, whether it is stepped by hand or by the clock.

	The same shape as `canRotate` in `ScopeTests`, one turn further in. There, the arrows were lit by one
	expression and stepped by another. Here the clock had a whole second verb — `advance`, which looked
	the mark up with a `firstIndex` of its own while Next asked `scheduled`. The two agree for exactly
	as long as the mark names a website the list still holds, and there are two everyday ways to break
	that: a website falling out of its hours, and a website deleted.

	In both, the top of the list is already on screen, so the arrows stepped to the second website and
	the tick stepped to the first — to where the display was already standing, for a whole interval.

	One verb now, which is also what lets Random be a mode rather than a branch at the call site: a
	shuffled display is one whose candidates come back in a decided order, and stepping does not have to
	know. The mode being absent from `advanceRotation` is the assertion that keeps it that way.
	*/
	@Test("The clock and the arrows are one step, over one position")
	func steppingIsOneVerb() throws {
		let rotation = try Self.source(named: "RotationBehaviour.swift")

		for declaration in ["func makeNextCurrent(", "private func scheduled(in candidates:"] {
			#expect(
				Self.body(of: declaration, in: rotation).contains("showingPosition(in:"),
				"`\(declaration)` works out where the display is standing on its own again, so a rotation tick and an arrow press can disagree about where the rotation is."
			)
		}

		#expect(
			!Self.body(of: "private func advanceRotation(", in: rotation).contains("rotationMode == .random"),
			"""
			The rotation tick branches on the mode again. Shuffling and looping differ in the order the \
			candidates come back in and in nothing else, so a branch here is a second stepping for the \
			arrows beside it to drift away from.
			"""
		)
	}

	/**
	Choosing a website is the only thing in the panel that decides anything.

	Both halves, because each fails on its own and they fail differently. If the panel writes the
	playlist itself, the wallpaper moves the moment a list is opened — before the user has said which
	page they want, and with no way to look at a list without being taken to it. If the commit does not
	carry the playlist, choosing a website out of a list the display is not pointed at shows a page from
	a list it is not on, and the next tick takes it back.

	Absolute on the write, with no allowlist, for the reason `ScopeTests` gives about the mark: a
	per-display fact with two writers is the shape that suite was written for, and `makeCurrent` is
	where every route to either key now meets.
	*/
	@Test("The playlist and the website are committed together, by the website chooser")
	func thePlaylistIsCommittedWithTheWebsite() throws {
		let assignment = try Regex("Defaults\\[\\.currentPlaylists\\](\\[[^\\]]*\\])?\\s*=[^=]")
		let model = try Self.source(named: "DisplayPanelModel.swift")

		#expect(
			model.firstMatch(of: assignment) == nil,
			"""
			The panel writes which playlist a display is pointed at. That is the write that moved the \
			wallpaper on a look at a menu; the commit is `makeCurrent`, which writes it beside the website \
			it was chosen with.
			"""
		)

		#expect(
			try Self.body(of: "func makeCurrent(", in: Self.source(named: "WebsitesController.swift"))
				.contains("currentPlaylists"),
			"`makeCurrent` no longer writes the playlist with the website, so the two can be apart for a turn of the run loop — which is the turn the wallpaper jumps in."
		)
	}
}
