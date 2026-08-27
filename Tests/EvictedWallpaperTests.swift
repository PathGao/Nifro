import Testing

@testable import NifroLogic

/**
Which wallpaper a display shows when a second one is pushed onto it by a cable being pulled.

The rule is one line — the arriving website wins — and the reason it needs a test is that the case
cannot be reached on a machine with one display, which is the machine it was written on. Two screens,
each showing its own website, each website marked current on its own screen. Unplug one and both
marks land on the survivor, and nothing in the app writes anything down: `scheduled(for:)` picks from
what it is handed, so this is the whole of the behaviour.
*/
@Suite("An unplugged display's wallpaper takes over the one it lands on")
struct EvictedWallpaperTests {
	@Test("The arriving website wins over the one already there")
	func evictedBeatsResident() {
		// Index 0 is the main display's own website, listed first and current there. Index 1 came from
		// the display that was just unplugged, and is current on that one.
		#expect(showingIndex(isCurrent: [true, true], isEvicted: [false, true]) == 1)
	}

	@Test("List order does not decide it")
	func listOrderIsNotTheAnswer() {
		// The same two websites, added to the list the other way round. Before the rule, this pair
		// answered 0 and the pair above answered 0 as well — the same unplug showing a different
		// wallpaper depending on the order two websites happened to be added in.
		#expect(showingIndex(isCurrent: [true, true], isEvicted: [true, false]) == 0)
	}

	@Test("An arrival that is not current still yields to a display's own current website")
	func onlyTheMarkedArrivalTakesOver() {
		// The unplugged display had two websites and was showing the second. Both arrive; only the one
		// that was actually up over there takes the screen.
		#expect(showingIndex(isCurrent: [true, false, true], isEvicted: [false, true, true]) == 2)
	}

	@Test("Nothing arriving leaves the display alone")
	func noEvictionChangesNothing() {
		#expect(showingIndex(isCurrent: [false, true], isEvicted: [false, false]) == 1)
	}

	@Test("A display that has never started shows the top of its list")
	func noMarkFallsBackToTheFirst() {
		#expect(showingIndex(isCurrent: [false, false], isEvicted: [false, false]) == 0)
	}

	@Test("An arrival takes the screen from a display that has never started")
	func noMarkStillYieldsToAnArrival() {
		#expect(showingIndex(isCurrent: [false, false], isEvicted: [false, true]) == 1)
	}

	@Test("A display with no websites shows nothing")
	func emptyDisplay() {
		#expect(showingIndex(isCurrent: [], isEvicted: []) == nil)
	}
}
