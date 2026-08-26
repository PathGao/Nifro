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

	@Test("Websites following the default display are one display, not none")
	func nilDisplaysGroupTogether() {
		// `effectiveDisplay` is optional and `nil` means "whatever Settings says", so two of those are
		// on the same screen and have to fight over one mark like any other pair.
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
