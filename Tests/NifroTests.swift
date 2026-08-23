import CoreGraphics
import Foundation
import Testing

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
Wrapping text for the menu.

The version this replaces shipped a bug for years: a word longer than the line was written out, then
written again on the next line. Text with no spaces in it came out doubled — which is every sentence
in Chinese, so the menu showed each error twice. It lived in a file nothing tests, and that is the
whole reason it survived.
*/
@Suite("Word wrapping")
struct WordWrappingTests {
	@Test("A word longer than the line appears once, not twice")
	func longWordIsNotDoubled() {
		// The shape that broke it: no spaces at all, longer than the limit.
		let sentence = "未能完成操作。（Swift.CancellationError错误1。）"
		let wrapped = sentence.wordWrapped(atLength: 20)

		#expect(wrapped == sentence)
		#expect(!wrapped.contains("\n"))
	}

	@Test("Wrapping happens at spaces, and every word survives once")
	func wrapsAtSpaces() {
		let wrapped = "the quick brown fox jumps over the lazy dog".wordWrapped(atLength: 16)
		let lines = wrapped.components(separatedBy: "\n")

		#expect(lines.allSatisfy { $0.count <= 16 })
		#expect(wrapped.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count == 9)
	}

	@Test("A short string is left exactly as it was")
	func shortStringIsUntouched() {
		#expect("no wrap here".wordWrapped(atLength: 40) == "no wrap here")
	}

	@Test("Cancellation is recognised however it is reported")
	func cancellationIsRecognised() {
		#expect(isCancellation(CancellationError()))
		#expect(isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
		#expect(isCancellation(CocoaError(.userCancelled)))
		#expect(!isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
	}
}
