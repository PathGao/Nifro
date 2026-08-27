import CoreGraphics
import Foundation
import Testing
import WebKit

@testable import NifroLogic

/**
The crop maths. Page coordinates run down from the top-left, view coordinates run up from the bottom-left, and getting the flip wrong shows the wrong part of the page while looking entirely plausible — which is exactly the kind of bug a test has to catch instead of an eye.
*/
@Suite("Crop geometry")
struct CropGeometryTests {
	private let pageSize = CGSize(width: 1600, height: 1000)

	@Test("A crop at the page origin puts the page flush with the top of the window")
	func cropAtOrigin() {
		let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
		let frame = crop.contentFrame(pageSize: pageSize)

		#expect(frame.origin.x == 0)
		// The page hangs below the window by everything the crop does not show.
		#expect(frame.origin.y == -700)
		#expect(frame.size == pageSize)
	}

	@Test("A crop lower down the page pulls the page further up")
	func cropBelowTheFold() {
		let crop = CGRect(x: 100, y: 600, width: 400, height: 300)
		let frame = crop.contentFrame(pageSize: pageSize)

		#expect(frame.origin.x == -100)
		#expect(frame.origin.y == -100)
	}

	@Test("A crop covering the whole page leaves the page unmoved")
	func fullPageCrop() {
		let crop = CGRect(origin: .zero, size: pageSize)
		let frame = crop.contentFrame(pageSize: pageSize)

		#expect(frame.origin == .zero)
	}

	@Test("Cropping the bottom of the page is not the same as cropping the top")
	func verticalFlipIsNotSymmetric() {
		let top = CGRect(x: 0, y: 0, width: 400, height: 300).contentFrame(pageSize: pageSize)
		let bottom = CGRect(x: 0, y: 700, width: 400, height: 300).contentFrame(pageSize: pageSize)

		#expect(top.origin.y != bottom.origin.y)
		#expect(bottom.origin.y == 0)
	}

	@Test("The crop lands where it was framed, not at the screen corner")
	func screenPlacement() {
		let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
		let crop = CGRect(x: 100, y: 200, width: 400, height: 300)
		let placed = crop.screenFrame(inScreen: screen)

		#expect(placed.minX == 100)
		// 200pt down from the top of a 1000pt screen, and 300pt tall, so its bottom sits at 500.
		#expect(placed.minY == 500)
		#expect(placed.size == crop.size)
	}


	@Test("Placement follows a screen that is not at the global origin")
	func screenPlacementOnSecondaryDisplay() {
		let screen = CGRect(x: 1600, y: 200, width: 1600, height: 1000)
		let crop = CGRect(x: 100, y: 0, width: 400, height: 300)
		let placed = crop.screenFrame(inScreen: screen)

		#expect(placed.minX == 1700)
		#expect(placed.maxY == 1200)
	}
}

/**
Daily schedule windows. The wrap-around case is the whole reason this is a function
rather than a comparison written inline at the call site.
*/
@Suite("Schedule windows")
struct ScheduleTests {
	@Test("A normal window covers its hours and nothing else")
	func daytime() {
		#expect(isHour(9, within: 8, until: 18))
		#expect(isHour(8, within: 8, until: 18))
		#expect(!isHour(18, within: 8, until: 18))
		#expect(!isHour(7, within: 8, until: 18))
		#expect(!isHour(23, within: 8, until: 18))
	}

	@Test("A window that wraps midnight covers both sides of it")
	func overnight() {
		// The case a single comparison gets wrong: written as `hour >= 22 && hour < 6`
		// this matches nothing at all, and the website silently never appears.
		#expect(isHour(23, within: 22, until: 6))
		#expect(isHour(2, within: 22, until: 6))
		#expect(isHour(22, within: 22, until: 6))
		#expect(!isHour(6, within: 22, until: 6))
		#expect(!isHour(12, within: 22, until: 6))
	}

	@Test("A window whose ends meet is always open")
	func degenerate() {
		for hour in 0..<24 {
			#expect(isHour(hour, within: 5, until: 5))
		}
	}
}

/**
Turning a video page into its player-only address. The parsing has to reject as confidently as it
accepts: a wrong rewrite sends the wallpaper to a page that does not exist, and the failure looks
like the site being down.
*/
@Suite("Video embedding")
struct VideoEmbedTests {
	@Test("YouTube watch URLs give up their video id")
	func youTubeWatch() throws {
		let url = try #require(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw&t=42"))
		let player = try #require(VideoEmbed.playerURL(for: url))

		#expect(player.absoluteString.hasPrefix("https://www.youtube.com/embed/jNQXAC9IVRw"))
		#expect(player.absoluteString.contains("autoplay=1"))
	}

	@Test("The stored address says nothing about sound")
	func soundIsNotBakedIntoTheAddress() throws {
		// Muting is a per-website setting that outlives this URL. An answer here would be the one the
		// user cannot change.
		for source in [
			"https://www.youtube.com/watch?v=jNQXAC9IVRw",
			"https://www.bilibili.com/video/BV1xx411c7mD"
		] {
			let url = try #require(URL(string: source))
			let player = try #require(VideoEmbed.playerURL(for: url))
			#expect(!player.absoluteString.contains("mute"), "\(source) carries a mute parameter")
		}
	}

	@Test("The framed player is asked to start muted, because that is the only way it starts")
	func framedPlayerStartsMuted() throws {
		// Not a decision about sound: YouTube's player will not autoplay unless it is muted, and the
		// audio script unmutes it afterwards. Without this the video sits paused on its first frame.
		let watch = try #require(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw"))
		let player = try #require(VideoEmbed.playerURL(for: watch))
		let host = try #require(VideoEmbed.hostPage(for: player))

		#expect(host.html.contains("mute=1"))
	}

	@Test("A player address stored before that was known still gets it")
	func olderAddressesAreFixedOnTheWayIn() throws {
		let stored = try #require(URL(string: "https://www.youtube.com/embed/jNQXAC9IVRw?autoplay=1&playsinline=1"))
		let host = try #require(VideoEmbed.hostPage(for: stored))

		#expect(host.html.contains("mute=1"))
	}

	@Test("Short links and shorts work too")
	func youTubeShortForms() throws {
		for source in [
			"https://youtu.be/jNQXAC9IVRw",
			"https://www.youtube.com/shorts/jNQXAC9IVRw"
		] {
			let url = try #require(URL(string: source))
			let player = try #require(VideoEmbed.playerURL(for: url))
			#expect(player.absoluteString.contains("/embed/jNQXAC9IVRw"))
		}
	}

	@Test("An embed URL is left alone")
	func alreadyEmbedded() throws {
		// Rewriting it would append a second query string and break the player.
		let url = try #require(URL(string: "https://www.youtube.com/embed/jNQXAC9IVRw?autoplay=1"))
		#expect(VideoEmbed.playerURL(for: url) == nil)
	}

	@Test("Bilibili video pages give up their BV id")
	func bilibili() throws {
		let url = try #require(URL(string: "https://www.bilibili.com/video/BV1xx411c7mD?p=2"))
		let player = try #require(VideoEmbed.playerURL(for: url))

		#expect(player.absoluteString.hasPrefix("https://player.bilibili.com/player.html?bvid=BV1xx411c7mD"))
		#expect(player.absoluteString.contains("danmaku=0"))
	}

	@Test("Pages that are not a single video are left alone")
	func notVideos() throws {
		for source in [
			"https://www.youtube.com/@NASA/live",
			"https://www.youtube.com",
			"https://live.bilibili.com/1234",
			"https://player.bilibili.com/player.html?bvid=BV1xx411c7mD",
			"https://example.com/watch?v=jNQXAC9IVRw"
		] {
			let url = try #require(URL(string: source))
			#expect(VideoEmbed.playerURL(for: url) == nil, "should not rewrite \(source)")
		}
	}

	@Test("Anything that is not a bare id is refused")
	func rejectsSmuggledInput() throws {
		// The id goes straight into a URL we build, so it has to be an id and nothing else.
		let url = try #require(URL(string: "https://www.youtube.com/watch?v=abc%26evil%3D1"))
		#expect(VideoEmbed.playerURL(for: url) == nil)
	}
}

/**
Which part of a page fills the wallpaper.

The reason this is a centre and a magnification rather than a rectangle is the second display: a
region framed on one screen has to come out the shape of whichever screen it is shown on. These check
that it does, and that a region near an edge stays on the page rather than hanging off it.
*/
@Suite("Zoom")
struct ZoomTests {
	private let page = CGSize(width: 1600, height: 1000)

	@Test("The region is always the shape of the page it is asked about")
	func followsTheDisplay() {
		// Chosen on a 16:10 screen, shown on a 16:9 one.
		let zoom = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2)
		let otherPage = CGSize(width: 1920, height: 1080)
		let region = zoom.region(inPageOfSize: otherPage)

		#expect(abs(region.width / region.height - otherPage.width / otherPage.height) < 0.001)
		#expect(abs(region.width - otherPage.width / zoom.scale) < 0.001)
	}

	@Test("A region near an edge is pushed back onto the page")
	func staysOnThePage() {
		// A corner on one screen, asked about on a much wider one, wants to hang off two edges.
		let zoom = Zoom(center: CGPoint(x: 0.02, y: 0.98), scale: 2)

		for size in [page, CGSize(width: 3840, height: 1080), CGSize(width: 1080, height: 1920)] {
			let region = zoom.region(inPageOfSize: size)

			#expect(region.minX >= 0, "left edge off the page at \(size)")
			#expect(region.minY >= 0, "top edge off the page at \(size)")
			#expect(region.maxX <= size.width + 0.001, "right edge off the page at \(size)")
			#expect(region.maxY <= size.height + 0.001, "bottom edge off the page at \(size)")
		}
	}

	@Test("Dragging moves the frame with the drag, not against it")
	func movingTheFrame() {
		let zoom = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 4)

		// The page stays where it is; the rectangle picking a part of it is what moves.
		let right = zoom.movedFrame(byViewDelta: CGSize(width: 160, height: 0), inPageOfSize: page)
		#expect(right.center.x > zoom.center.x)
		#expect(abs((right.center.x - zoom.center.x) * page.width - 160) < 0.001)

		// View coordinates run up, page coordinates run down.
		let up = zoom.movedFrame(byViewDelta: CGSize(width: 0, height: 100), inPageOfSize: page)
		#expect(up.center.y < zoom.center.y)
	}

	@Test("A drag cannot push the frame off the page, or bank an offset while it looks stuck")
	func movingStops() {
		let zoom = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2)
		var far = zoom

		for _ in 0..<20 {
			far = far.movedFrame(byViewDelta: CGSize(width: 400, height: 0), inPageOfSize: page)
		}

		// Hard against the right edge, and no further — a centre that had wandered past would have to
		// be dragged all the way back before the frame moved again.
		#expect(abs(far.center.x - 0.75) < 0.001)

		let back = far.movedFrame(byViewDelta: CGSize(width: -40, height: 0), inPageOfSize: page)
		#expect(back.center.x < far.center.x)
	}

	@Test("Growing the frame lowers the magnification, and does not move it")
	func resizingHoldsTheCentre() {
		let zoom = Zoom(center: CGPoint(x: 0.3, y: 0.7), scale: 4)
		let bigger = zoom.resizedFrame(byGrowing: 2)

		// A frame twice as wide shows twice as much, which is half the magnification. Spreading two
		// fingers makes the frame bigger; writing this the other way round is what shipped backwards.
		#expect(bigger.scale == 2)
		#expect(bigger.center == zoom.center)

		let smaller = zoom.resizedFrame(byGrowing: 0.5)
		#expect(smaller.scale == 8)
	}

	@Test("The frame stops at both ends")
	func sizeIsBounded() {
		let out = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2).resizedFrame(byGrowing: 1000)
		#expect(out.scale == 1)
		// The whole page has only one possible centre.
		#expect(out.center == CGPoint(x: 0.5, y: 0.5))

		let deepIn = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2).resizedFrame(byGrowing: 0.001)
		#expect(deepIn.scale == Zoom.maximumScale)
	}

	@Test("Zooming out below the whole page is not a thing")
	func neverSmallerThanThePage() {
		// A page-sized region magnified less than once would be a window with nothing along two edges.
		let region = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 0.25).region(inPageOfSize: page)

		#expect(region == CGRect(origin: .zero, size: page))
	}
}

extension VideoEmbedTests {
	@Test("A YouTube player address gets a page to be framed by")
	func youTubeNeedsAHost() throws {
		let watch = try #require(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw"))
		let url = try #require(VideoEmbed.playerURL(for: watch))
		let host = try #require(VideoEmbed.hostPage(for: url))

		#expect(host.html.contains("<iframe"))
		#expect(host.html.contains("/embed/jNQXAC9IVRw"))
		// Framed by youtube.com it fails the same way as not being framed at all.
		#expect(host.baseURL.host()?.hasSuffix("youtube.com") != true)
	}

	@Test("Anything that can be opened on its own is left alone")
	func othersLoadDirectly() throws {
		for source in [
			"https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=1",
			"https://www.youtube.com/@NASA/live",
			"https://example.com"
		] {
			let url = try #require(URL(string: source))
			#expect(VideoEmbed.hostPage(for: url) == nil, "\(source) should not be wrapped")
		}
	}

	@Test("The framed address cannot break out of the attribute it sits in")
	func hostEscapesTheAddress() throws {
		let url = try #require(URL(string: #"https://www.youtube.com/embed/x?a="><script>alert(1)</script>"#))
		let host = try #require(VideoEmbed.hostPage(for: url))

		#expect(!host.html.contains("<script"))
	}
}

extension VideoEmbedTests {
	@Test("A website shown through a host page has no address worth saving")
	func hostPagesHaveNothingToOffer() throws {
		// "Update Website to Current" asks whether the page has ended up somewhere the user found.
		// For a framed player the document is scaffolding this app built, so the answer is no — and
		// answering yes replaced the website with the scaffolding's address.
		let embed = try #require(URL(string: "https://www.youtube.com/embed/jNQXAC9IVRw?autoplay=1"))
		#expect(VideoEmbed.hostPage(for: embed) != nil)
	}
}

/**
How much of a screen the menu bar takes.

Worth its own tests because the previous answer was a guess checked against a constant — "33 points
on a notched display, 24 otherwise, plus one" — and on a real machine the true value was 33 against a
constant of 34. Being one point out flipped the conclusion to "the menu bar hides itself", so the page
was laid out over the menu bar and the colour band was never built.
*/
@Suite("Menu bar strip")
struct MenuBarStripTests {
	@Test("The strip is the gap between the two top edges, wherever the Dock is")
	func dockDoesNotMatter() {
		let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)

		// Dock on the left: it takes width, and the top edge is untouched.
		#expect(menuBarStripHeight(frame: frame, visibleFrame: CGRect(x: 55, y: 0, width: 1415, height: 923)) == 33)
		// Dock at the bottom: it moves the origin up, and the top edge is still untouched.
		#expect(menuBarStripHeight(frame: frame, visibleFrame: CGRect(x: 0, y: 70, width: 1470, height: 853)) == 33)
	}

	@Test("A menu bar that hides itself takes nothing")
	func hiddenMenuBarTakesNothing() {
		let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)

		#expect(menuBarStripHeight(frame: frame, visibleFrame: frame) == 0)
	}

	@Test("A screen with no menu bar at all takes nothing")
	func secondaryScreensCanHaveNone() {
		// A secondary screen's frame does not start at zero.
		let frame = CGRect(x: 1470, y: 200, width: 1920, height: 1080)

		#expect(menuBarStripHeight(frame: frame, visibleFrame: frame) == 0)
	}
}


/**
Which website is the current one, on a Mac with more than one display.

Every part of this was written and shipped on a one-display machine, where a list-wide answer and a
per-display answer are the same answer. They are not the same on two, and the difference is not
visible by reading: it shows as one screen quietly refusing to rotate. These are the cheapest way to
have the two-display case checked at all.
*/
@Suite("Current website per display")
struct CurrentWebsiteTests {
	@Test("Making one current leaves the other display's mark alone")
	func otherDisplaysKeepTheirMark() {
		// Two websites on display A, two on display B, one marked on each.
		let displays = ["A", "A", "B", "B"]
		let wasCurrent = [true, false, true, false]

		// Display A advances to its second website.
		let flags = currentFlags(displays: displays, wasCurrent: wasCurrent, makingCurrent: 1)

		#expect(flags == [false, true, true, false])
	}

	@Test("A display never ends up with two marked websites")
	func oneMarkPerDisplay() {
		let displays = ["A", "A", "A"]

		let flags = currentFlags(displays: displays, wasCurrent: [true, true, false], makingCurrent: 2)

		#expect(flags == [false, false, true])
	}

	@Test("Websites following the main display are one display, not none")
	func nilDisplaysGroupTogether() {
		// `effectiveDisplay` is optional and `nil` means the main display, so two of those are on the
		// same screen and have to fight over one mark like any other pair.
		let displays: [String?] = [nil, nil, "B"]

		let flags = currentFlags(displays: displays, wasCurrent: [true, false, true], makingCurrent: 1)

		#expect(flags == [false, true, true])
	}

	@Test("Rotation goes round its own display and wraps")
	func rotationWraps() {
		#expect(nextRotationIndex(count: 3, after: 0) == 1)
		#expect(nextRotationIndex(count: 3, after: 2) == 0)
	}

	@Test("A display that has lost its mark starts again rather than stopping")
	func unmarkedDisplayStartsOver() {
		#expect(nextRotationIndex(count: 3, after: nil) == 0)
		#expect(nextRotationIndex(count: 0, after: nil) == nil)
	}

	@Test("Two displays can each advance without disturbing the other")
	func twoDisplaysRotateIndependently() {
		// The exact sequence that used to pin display A to its first website. A advances, then B
		// advances; if B's advance clears A's mark, A's next advance starts from the beginning and A
		// never gets past index 0.
		let displays = ["A", "A", "B", "B"]

		var flags = currentFlags(displays: displays, wasCurrent: [true, false, true, false], makingCurrent: 1)
		flags = currentFlags(displays: displays, wasCurrent: flags, makingCurrent: 3)

		// A is still on its second website.
		#expect(flags == [false, true, false, true])

		// So A's next tick moves it on rather than back to the start.
		let aFlags = [flags[0], flags[1]]
		#expect(nextRotationIndex(count: 2, after: aFlags.firstIndex(of: true)) == 0)
		#expect(aFlags.firstIndex(of: true) == 1)
	}
}

/**
How long a display waits between websites.

Two things that only look simple. The fallback is what an upgrading user lands on — the interval was
one number for the whole machine until now, and nobody's setting is allowed to vanish because the
shape it is stored in changed. The clamp is the other end of a text field, where "0" and a nine-digit
number are each one keystroke away and both mean a wallpaper that has stopped.
*/
@Suite("Rotation interval")
struct RotationIntervalTests {
	@Test("A display with a number of its own uses it")
	func stored() {
		#expect(rotationInterval(stored: 12, legacySeconds: 60 * 45) == 12)
	}

	@Test("A display with nothing of its own inherits the machine-wide number it replaced")
	func legacyFallback() {
		#expect(rotationInterval(stored: nil, legacySeconds: 60 * 45) == 45)
	}

	@Test("A machine that never set one gets the default")
	func noSettingAtAll() {
		#expect(rotationInterval(stored: nil, legacySeconds: nil) == defaultRotationIntervalMinutes)
	}

	@Test("Rotation being off is not stored as a missing interval any more")
	func offIsNotAbsence() {
		// Up to 0.1.3 a nil interval meant "do not rotate", and that meaning moved to `RotationMode`.
		// So nil now has to mean a length rather than a refusal, or a display switched to Loop would
		// come up with no interval and never move.
		#expect(rotationInterval(stored: nil, legacySeconds: nil) >= rotationIntervalRange.lowerBound)
	}

	@Test("A stored number outside the range is brought back into it")
	func storedIsClamped() {
		#expect(rotationInterval(stored: 0, legacySeconds: nil) == rotationIntervalRange.lowerBound)
		#expect(rotationInterval(stored: 99_999, legacySeconds: nil) == rotationIntervalRange.upperBound)
		#expect(rotationInterval(stored: .nan, legacySeconds: nil) == defaultRotationIntervalMinutes)
	}

	@Test("A number typed in is taken as it is when it makes sense")
	func enteredIsKept() {
		#expect(rotationInterval(entered: 90, current: 30) == 90)
	}

	@Test("Nothing typed in leaves the display where it was")
	func enteredEmpty() {
		#expect(rotationInterval(entered: nil, current: 30) == 30)
		#expect(rotationInterval(entered: .nan, current: 30) == 30)
		#expect(rotationInterval(entered: .infinity, current: 30) == 30)
	}

	@Test("Zero and below become the shortest wait on offer, not a display that never moves")
	func enteredTooSmall() {
		#expect(rotationInterval(entered: 0, current: 30) == 1)
		#expect(rotationInterval(entered: -5, current: 30) == 1)
	}

	@Test("A number too big to be a rotation stops at a day")
	func enteredTooLarge() {
		#expect(rotationInterval(entered: 100_000, current: 30) == 60 * 24)
	}

	@Test("The field is whole minutes, so what it takes is too")
	func enteredIsWholeMinutes() {
		#expect(rotationInterval(entered: 4.6, current: 30) == 5)
	}
}

/**
The strip of page the menu bar band takes its colour from.

The band stands in for whatever is drawn behind the menu bar. With a region framed, that is not the
top of the page — it is somewhere in the middle of it, magnified — and the version that shipped took
the colour off the top of the page regardless, so a framed wallpaper tinted the menu bar with a part
of the page that is usually not on screen at all.
*/
@Suite("Menu bar band sampling")
struct MenuBarBandSamplingTests {
	private let pageSize = CGSize(width: 1470, height: 896)
	private let height = 33.0

	@Test("With no magnification the strip is the top of the page")
	func unzoomedIsTheTop() {
		let strip = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 1).topStrip(inPageOfSize: pageSize, height: height)

		#expect(strip == CGRect(x: 0, y: 0, width: pageSize.width, height: height))
	}

	@Test("The strip is as wide as the window, not as wide as the region")
	func widthIsNotScaled() {
		let strip = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2).topStrip(inPageOfSize: pageSize, height: height)

		// Half the page across, centred, magnified twice: the top-left of the region is a quarter of
		// the page in and down, and that lands at half the page's dimensions once magnified.
		#expect(strip.origin.x == pageSize.width / 2)
		#expect(strip.origin.y == pageSize.height / 2)

		// Not `region.width`, and not `pageSize.width * scale`. Both are plausible and both are wrong:
		// the view's coordinates are already magnified, so the strip stays the width of the window.
		// Literals rather than the properties above: a rectangle's members are `CGFloat` and these are
		// `Double`, and `#expect` reports the mixed comparison as failed even when both sides print the
		// same number.
		#expect(strip.width == pageSize.width)
		#expect(strip.height == 33)
	}

	@Test("A region at the top-left samples the view's own corner")
	func topLeftRegionSamplesTheCorner() {
		let strip = Zoom(center: .zero, scale: 4).topStrip(inPageOfSize: pageSize, height: height)

		#expect(strip.origin == .zero)
	}

	@Test("A region at the bottom-right stays inside the magnified page")
	func bottomRightRegionStaysInBounds() {
		let strip = Zoom(center: CGPoint(x: 1, y: 1), scale: 4).topStrip(inPageOfSize: pageSize, height: height)

		// The region is clamped to the page's far corner, so its origin is three quarters of the way
		// along, and magnified that is the far edge of the view minus one window's width.
		#expect(strip.origin.x == pageSize.width * 3)
		#expect(strip.maxX == pageSize.width * 4)
	}

	@Test("Magnification follows the clamped region, not the raw scale")
	func magnificationFollowsTheClampedRegion() {
		// Below 1 there is nothing left to frame, so the region is the whole page and the page is
		// drawn at its own size.
		#expect(Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 0.5).magnification(inPageOfSize: pageSize) == 1)
		#expect(Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 3).magnification(inPageOfSize: pageSize) == 3)
	}
}

/**
How a `nifro:` URL says which command it means.

A URL scheme is a public interface, and this one has two spellings that parse differently. Only one
of them worked, and the other failed with a message that named nothing — so the failure looked like
"no such command" rather than "wrong number of slashes". These pin both, because the whole reason the
bug survived is that nothing said which spelling was the real one.
*/
@Suite("URL commands")
struct URLCommandTests {
	private func command(_ string: String) -> String {
		urlCommand(from: URLComponents(string: string)!)
	}

	@Test("The documented spelling puts the command in the path")
	func withoutSlashes() {
		#expect(command("nifro:reload") == "reload")
	}

	@Test("The spelling people actually type puts it in the host")
	func withSlashes() {
		// This is the one that used to answer "The command “” is not supported".
		#expect(command("nifro://reload") == "reload")
		#expect(command("nifro://next") == "next")
	}

	@Test("A third slash puts it back in the path, with a leading slash to drop")
	func withThreeSlashes() {
		#expect(command("nifro:///reload") == "reload")
	}

	@Test("Parameters belong to the query, whichever spelling carries the command")
	func parametersSurvive() {
		#expect(command("nifro:add?url=https://example.com") == "add")
		#expect(command("nifro://add?url=https://example.com") == "add")
	}

	@Test("A URL with no command at all is empty rather than something")
	func noCommand() {
		#expect(command("nifro:").isEmpty)
	}
}

/**
The one thing the cache sweep can get wrong that nobody would notice until a user complains they were signed out of their own dashboard: dropping a data type the network cannot hand back.
*/
@Suite("Disk budget")
struct DiskBudgetTests {
	@Test("The sweep only drops types the network can hand back")
	func dropsNothingTheUserPutThere() {
		// Named one by one rather than checked against a "keep these" set, because such a set has no
		// caller outside this test and the unused-code scan is right to say so.
		#expect(!DiskBudget.refetchableTypes.contains(WKWebsiteDataTypeCookies))
		#expect(!DiskBudget.refetchableTypes.contains(WKWebsiteDataTypeLocalStorage))
		#expect(!DiskBudget.refetchableTypes.contains(WKWebsiteDataTypeSessionStorage))
		#expect(!DiskBudget.refetchableTypes.contains(WKWebsiteDataTypeIndexedDBDatabases))
		#expect(!DiskBudget.refetchableTypes.contains(WKWebsiteDataTypeServiceWorkerRegistrations))
		#expect(!DiskBudget.refetchableTypes.isEmpty)
	}

	@Test("A store whose website is gone is collected")
	func collectsWhatNoWebsiteOwns() {
		let kept = UUID()
		let deleted = UUID()

		#expect(DiskBudget.orphans(among: [kept, deleted], keeping: [kept]) == [deleted])
	}

	@Test("An empty website list collects nothing, rather than everything")
	func emptyListIsNotAMandateToDeleteEverything() {
		// Nothing can put a store back. A reading of "no websites at all" is the one that has to be
		// distrusted, because acting on it wrongly signs the user out of every page they had.
		#expect(DiskBudget.orphans(among: [UUID(), UUID()], keeping: []).isEmpty)
	}

	@Test("The budget is small enough to be worth enforcing")
	func budgetIsBelowWhatOrdinaryUseReached() {
		// 151 MB was measured on a container nobody had asked to fill. A limit above that would never fire.
		#expect(DiskBudget.limit < 151_000_000)
	}
}

/**
Two spellings of one value, from two places that never agreed. The catalogue's spelling is what `sites/schema.json` requires; the array spelling is what every installed copy already has on disk. Reading only one of them is how a catalogue entry with a `zoom` came to cost the whole live gallery.
*/
@Suite("Zoom decoding")
struct ZoomDecodingTests {
	private func decode(_ json: String) throws -> Zoom {
		try JSONDecoder().decode(Zoom.self, from: Data(json.utf8))
	}

	@Test("The catalogue's spelling decodes")
	func catalogueSpelling() throws {
		// The shape `Tools/generate-site-catalog.py` writes and `sites/schema.json` requires.
		let zoom = try decode(#"{"centerX": 0.25, "centerY": 0.75, "scale": 3}"#)

		#expect(zoom.center == CGPoint(x: 0.25, y: 0.75))
		#expect(zoom.scale == 3)
	}

	@Test("What is already saved on disk still decodes")
	func savedSpelling() throws {
		// Synthesised `Codable` writes `CGPoint` unkeyed. Taken from a real preferences file.
		let zoom = try decode(#"{"center": [0.418, 0.526], "scale": 1.2039}"#)

		#expect(zoom.center == CGPoint(x: 0.418, y: 0.526))
		#expect(zoom.scale == 1.2039)
	}

	@Test("Encoding still writes the spelling already on disk")
	func encodingIsUnchanged() throws {
		// Not a style preference: writing the other spelling would make every saved zoom unreadable
		// by the version that saved it, and unreadable by this one too if the reader were ever
		// narrowed to match.
		let encoded = try JSONEncoder().encode(Zoom(center: CGPoint(x: 0.25, y: 0.75), scale: 3))
		let asObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

		#expect(asObject?["center"] is [Any])
		#expect(asObject?["centerX"] == nil)
	}
}

/**
Version comparison, which goes wrong quietly: compared as text, 0.1.10 is older than 0.1.9, so the project that has shipped ten patches is the one that stops telling anybody about them.
*/
@Suite("Update check")
struct UpdateCheckTests {
	@Test("A later version is newer")
	func laterIsNewer() {
		#expect(UpdateCheck.isNewer("0.1.4", than: "0.1.3"))
		#expect(UpdateCheck.isNewer("0.2.0", than: "0.1.9"))
		#expect(UpdateCheck.isNewer("1.0.0", than: "0.9.9"))
	}

	@Test("Ten is not less than nine")
	func doubleDigitsAreNotText() {
		#expect(UpdateCheck.isNewer("0.1.10", than: "0.1.9"))
		#expect(!UpdateCheck.isNewer("0.1.9", than: "0.1.10"))
	}

	@Test("The same version is not newer, however it is spelled")
	func sameIsNotNewer() {
		#expect(!UpdateCheck.isNewer("0.1.3", than: "0.1.3"))
		// A missing component is zero, so these are the same version.
		#expect(!UpdateCheck.isNewer("0.2", than: "0.2.0"))
		#expect(!UpdateCheck.isNewer("0.2.0", than: "0.2"))
	}

	@Test("An older version is not newer")
	func olderIsNotNewer() {
		#expect(!UpdateCheck.isNewer("0.1.2", than: "0.1.3"))
		#expect(!UpdateCheck.isNewer("0.9.9", than: "1.0.0"))
	}

	@Test("Anything unparseable is not newer")
	func rubbishIsNotNewer() {
		// This drives a menu item that sends people to a download page. Being wrong in the direction of
		// silence is the cheap mistake.
		#expect(!UpdateCheck.isNewer("", than: "0.1.3"))
		#expect(!UpdateCheck.isNewer("nightly", than: "0.1.3"))
		#expect(!UpdateCheck.isNewer("0.1.3-beta", than: "0.1.3"))
		#expect(!UpdateCheck.isNewer("0.1.4", than: "not-a-version"))
	}
}

extension UpdateCheckTests {
	@Test("A failed check is not the same answer as being up to date")
	func unreachableIsItsOwnAnswer() {
		// Told apart by the type, not inferred afterwards. Inferring gets it wrong in one specific
		// case: a fetch that fails while an older version is already on record looks identical to a
		// fetch that succeeded and found nothing newer.
		#expect(UpdateCheck.Result.unreachable != UpdateCheck.Result.upToDate)
		#expect(UpdateCheck.Result.newer("0.1.4") != UpdateCheck.Result.upToDate)
	}
}

/**
`sites/index.json` as published, read the way the app reads it.

The file is served from `main` and fetched at runtime, so it ships without a build and without
anything on the way out that compiles it. `SiteCatalog` used to need SwiftUI, `Defaults` and the
websites controller to compile, which kept it out of this target and left the published file with no
reader in the repository at all; the parts of it that turn an entry into a website now live in
`Nifro/Sites/WebsitesController.swift` so that the decoding can be listed in `Package.swift` and
tested here. That is the whole point of the split — see the note on `SiteCatalog`.
*/
@Suite("Published site catalogue")
struct SiteCatalogTests {
	/**
	The committed file, decoded by the type the app decodes it with. Throwing, deliberately: the
	failure this exists to catch is a decode failure, and `XCTest`'s report of the thrown
	`DecodingError` names the key and the entry, which is more than any assertion here could say.
	*/
	static func published() throws -> [SiteCatalog.Entry] {
		let root = URL(filePath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()

		let data = try Data(contentsOf: root.appending(path: "sites/index.json"))

		return try JSONDecoder().decode([SiteCatalog.Entry].self, from: data)
	}

	/**
	The published list decodes, all of it, through `SiteCatalog.Entry`.

	This is the check that was missing for the whole life of the fetched gallery. `sites/index.json`
	is generated by `Tools/generate-site-catalog.py`, served from `main`, and read back as `Entry` —
	and the two had never agreed, because the JSON carried the YAML's `audio: "muted" | "unmuted"`
	where `Entry` declares `playsSound: Bool`. Every entry threw, `SkippableEntry` skipped every one,
	and `fetchLatest` returned the compiled-in snapshot exactly as it does when there is no network.
	A feature whose only purpose is to deliver entries between releases had delivered none, ever, and
	looked fine doing it.

	Decoded as `[Entry]` rather than through `fetchLatest`, which would need the network and would
	hand back the snapshot on any failure — the same shrug that hid this. Nothing here is skippable:
	one entry that will not decode fails the test, because on the way out of the repository there is
	no reason to tolerate one.
	*/
	@Test("Every published entry decodes")
	func everyEntryDecodes() throws {
		#expect(try Self.published().count == 38)
	}

	/**
	One entry, checked field by field.

	A count alone passes on a file of 38 entries whose optional fields all silently arrived as `nil`
	— which is most of the ways this could break, since almost everything on `Entry` is optional.
	Floor796 is the rank-1 entry, so it is also the wallpaper somebody sees before they have chosen
	anything.
	*/
	@Test("A known entry arrives with its fields intact")
	func knownEntry() throws {
		let entry = try #require(try Self.published().first { $0.name == "Floor796" })

		#expect(entry.url == "https://floor796.com/")
		#expect(entry.featuredRank == 1)
		#expect(!entry.playsSound)
		#expect(entry.tags == ["art", "ambient"])
		#expect(!entry.requiresLogin)
	}

	/**
	And an entry on the other side of the mapping, because `false` everywhere is what the bug looked
	like and a list of 38 `false`s would pass a test that only ever asked for `false`. Lofi Girl is
	the one site here whose sound is the point of it.
	*/
	@Test("The one entry that plays sound says so")
	func soundingEntry() throws {
		let entry = try #require(try Self.published().first { $0.name == "Lofi Girl" })

		#expect(entry.playsSound)
		#expect(try Self.published().filter(\.playsSound).count == 1)
	}

	/**
	An entry that carries a region, in both spellings, through the whole `Entry` decode.

	`Zoom` reading both spellings is covered on its own in `ZoomDecodingTests`, and that is not this.
	The fault this stands in for was never in `Zoom` alone: an entry's `zoom` reaches `Zoom` through
	`Entry`'s synthesised `Codable`, one bad key there throws the whole entry, and `SkippableEntry`
	then drops it without a word. So the check has to start where the published file starts — an
	array of index.json-shaped objects — and end at a region with the right numbers in it.

	Synthetic, because no shipped entry sets a `zoom`: 38 published entries, none of them with one,
	which is exactly why this path went years without ever running against real data and why the fix
	for it is otherwise unverified. Not fixed by adding a `zoom` to a shipped entry — the catalogue is
	what users get, not a fixture — so the fixture is here, written in the shape
	`Tools/generate-site-catalog.py` emits, field for field.

	Both entries in one array on purpose. Decoded separately, a spelling that threw would look like a
	failed test; decoded together, it also shows what the failure costs the entry beside it.
	*/
	@Test("An entry carrying a region decodes, in either spelling")
	func entryWithZoom() throws {
		// The generator's spelling first — what `sites/schema.json` requires and what a contributor
		// writes — then the one synthesised `Codable` writes, which is what an entry copied back out of
		// a preferences file would carry.
		let json = """
			[
			 {
			  "css": null,
			  "description": "The generator's spelling, as sites/schema.json requires it.",
			  "featuredRank": null,
			  "javaScript": null,
			  "name": "Framed",
			  "playsSound": false,
			  "reloadInterval": null,
			  "requiresLogin": false,
			  "tags": ["test"],
			  "url": "https://example.com/framed",
			  "zoom": {"centerX": 0.25, "centerY": 0.75, "scale": 3}
			 },
			 {
			  "css": null,
			  "description": "The spelling every saved region on disk already has.",
			  "featuredRank": null,
			  "javaScript": null,
			  "name": "Framed As Saved",
			  "playsSound": false,
			  "reloadInterval": null,
			  "requiresLogin": false,
			  "tags": ["test"],
			  "url": "https://example.com/framed-as-saved",
			  "zoom": {"center": [0.25, 0.75], "scale": 3}
			 }
			]
			"""

		let entries = try JSONDecoder().decode([SiteCatalog.Entry].self, from: Data(json.utf8))

		#expect(entries.count == 2)

		for entry in entries {
			let zoom = try #require(entry.zoom)

			#expect(zoom.center == CGPoint(x: 0.25, y: 0.75))
			#expect(zoom.scale == 3)

			// Through to the thing the region is for, because a centre and a magnification that decode
			// and then pick out the wrong part of the page would pass every assertion above. A quarter
			// across and three quarters down, at three times, on a 1200x900 page.
			#expect(zoom.region(inPageOfSize: CGSize(width: 1200, height: 900)) == CGRect(x: 100, y: 525, width: 400, height: 300))
		}
	}
}

/**
What the app installs on a first launch: which websites, in what order, and on which screen.

The order is a decision — the entry ranked 1 is the wallpaper a stranger sees before they have chosen
anything — and it is carried in the entries' own YAML files rather than anywhere in Swift. That makes
it data nothing compiles, which is exactly the kind of answer that goes wrong quietly: it used to be
file-name order, so renaming a file changed the first thing a new user saw and nothing said so.

Read through the decode above rather than by picking fields out of the JSON by hand. Both of the
generator's outputs come out of one run, field by field in the same loop, so the JSON is the same
answer the app compiles in — and reading it as `Entry` means these tests throw rather than quietly
agreeing with an empty list, which is how the last version of this suite would have greeted a file
that no longer decoded.
*/
@Suite("Shipped websites")
struct ShippedWebsitesTests {
	private static func featured() throws -> [SiteCatalog.Entry] {
		try SiteCatalogTests.published()
			.compactMap { entry in entry.featuredRank.map { (rank: $0, entry: entry) } }
			.sorted { $0.rank < $1.rank }
			.map(\.entry)
	}

	@Test("The shipped websites install in the order they are ranked")
	func featuredOrder() throws {
		#expect(try Self.featured().map(\.name) == [
			"Floor796",
			"Svalbard — A Journey to the North Pole",
			"Calculating Empires",
			"WindowSwap",
			"World Monitor",
			"Windy",
			"Flightradar24",
			"Faroe Islands in 4K HDR"
		])
	}

	/**
	Contiguous from 1, and therefore unique.

	Uniqueness is what the order rests on: `sorted(by:)` does not promise to keep the input order for a
	tie, so two entries claiming rank 3 would make the first wallpaper a coin toss between them.
	`Tools/validate-sites.py` rejects the duplicate; this is the same check from the other end.
	*/
	@Test("Every shipped website has its own rank")
	func featuredRanksAreUnique() throws {
		#expect(try Self.featured().compactMap(\.featuredRank) == Array(1...8))
	}

	/**
	A wallpaper that starts talking is a bad surprise, and this is a list of eight nobody chose.
	*/
	@Test("Every shipped website starts muted")
	func featuredStartMuted() throws {
		let featured = try Self.featured()

		#expect(featured.allSatisfy { !$0.playsSound })
		#expect(!featured.isEmpty)
	}

	@Test("One display shows the first shipped website")
	func onePlacement() {
		let placements = firstLaunchPlacements(displayCount: 1, websiteCount: 8)

		#expect(placements.map(\.website) == [0])
		#expect(placements.map(\.display) == [nil])
	}

	/**
	The case the user asked for, and the one that was broken: the second screen started empty because
	every installed website was on the main display.
	*/
	@Test("Two displays show the first and the second")
	func twoPlacements() {
		let placements = firstLaunchPlacements(displayCount: 2, websiteCount: 8)

		#expect(placements.map(\.website) == [0, 1])

		// The first is left following the main display rather than pinned to a display of its own, so
		// it moves with the menu bar; the second has to be pinned, or nothing names that screen and it
		// gets no wallpaper.
		#expect(placements.map(\.display) == [nil, 1])
	}

	@Test("The rule keeps going past two displays")
	func threePlacements() {
		let placements = firstLaunchPlacements(displayCount: 3, websiteCount: 8)

		#expect(placements.map(\.website) == [0, 1, 2])
		#expect(placements.map(\.display) == [nil, 1, 2])
	}

	/**
	Both ends of the count. There is always one wallpaper — `displaysInUse` falls back to the main
	display — so a moment with no display attached still places the first website rather than none.
	*/
	@Test("More displays than websites, and no displays at all")
	func lopsidedPlacements() {
		#expect(firstLaunchPlacements(displayCount: 9, websiteCount: 8).count == 8)
		#expect(firstLaunchPlacements(displayCount: 0, websiteCount: 8).map(\.display) == [nil])
		#expect(firstLaunchPlacements(displayCount: 2, websiteCount: 0).isEmpty)
	}
}
