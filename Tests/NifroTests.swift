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

	@Test("Fullscreen controls follow Nifro's running mode, not the saved address")
	func fullscreenPresentationIsDerivedAtLoadTime() throws {
		let oldPlayer = try #require(URL(string: "https://www.youtube.com/embed/jNQXAC9IVRw?autoplay=1&fs=0&fs=1&playsinline=1"))
		let wallpaper = VideoEmbed.presentationURL(for: oldPlayer, fullscreenCompatibility: .wallpaper)
		let compatibility = VideoEmbed.presentationURL(for: oldPlayer, fullscreenCompatibility: .compatibility)

		#expect(URLComponents(url: wallpaper, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "fs" }.map(\.value) == ["0"])
		#expect(URLComponents(url: compatibility, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "fs" } == false)
		#expect(VideoEmbed.presentationURL(for: try #require(URL(string: "https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=1")), fullscreenCompatibility: .wallpaper).absoluteString == "https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=1")
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
	@Test("A YouTube player is loaded directly with Nifro's Referer")
	func youTubeNeedsAReferer() throws {
		let watch = try #require(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw"))
		let url = try #require(VideoEmbed.playerURL(for: watch))
		#expect(VideoEmbed.referrer(for: url) == "https://github.com/PathGao/Nifro")
	}

	@Test("Anything that can be opened on its own is left alone")
	func othersLoadDirectly() throws {
		for source in [
			"https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=1",
			"https://www.youtube.com/@NASA/live",
			"https://example.com"
		] {
			let url = try #require(URL(string: source))
			#expect(VideoEmbed.referrer(for: url) == nil, "\(source) should not need a Referer")
		}
	}

}

/**
Finding a video's cover for the row icon in the websites list.

The address is asked for in one place and read out of the reply in another, so that both halves can
be checked without a network. What they are guarding is that the app now talks to a site's API at
all: the request must carry an id and nothing else, and the reply is somebody else's text.
*/
extension VideoEmbedTests {
	@Test("A Bilibili entry has somewhere to ask, in either form")
	func bilibiliCoverIsAskedFor() throws {
		for source in [
			"https://www.bilibili.com/video/BV1xx411c7mD?p=2",
			"https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=1&danmaku=0"
		] {
			let url = try #require(URL(string: source))
			let api = try #require(VideoEmbed.previewImageAPIURL(for: url))

			#expect(api.absoluteString == "https://api.bilibili.com/x/web-interface/view?bvid=BV1xx411c7mD")
		}
	}

	@Test("Nothing else is asked about")
	func othersAreNotAskedAbout() throws {
		// YouTube's cover needs no call, and a page that is not a video has no cover to want.
		for source in [
			"https://www.youtube.com/watch?v=jNQXAC9IVRw",
			"https://www.youtube.com/embed/jNQXAC9IVRw?autoplay=1",
			"https://live.bilibili.com/1234",
			"https://example.com"
		] {
			let url = try #require(URL(string: source))
			#expect(VideoEmbed.previewImageAPIURL(for: url) == nil, "should not call an API for \(source)")
		}
	}

	@Test("The cover in the reply is taken over TLS and at the size a row can show")
	func coverIsReadFromTheReply() throws {
		// `pic` really does come back as http, and really is the full-size cover: 651 KB measured
		// against 7 KB for the same file with the CDN's resize suffix.
		let reply = Data(#"{"code":0,"data":{"pic":"http://i1.hdslb.com/bfs/archive/abc.jpg"}}"#.utf8)
		let cover = try #require(VideoEmbed.previewImageURL(inAPIResponse: reply))

		#expect(cover.absoluteString == "https://i1.hdslb.com/bfs/archive/abc.jpg@320w_180h.jpg")
	}

	@Test("A reply that is not an answer is not a cover")
	func repliesAreNotTrusted() {
		for source in [
			// The video is gone; `data` is null and `code` says so.
			#"{"code":-404,"message":"啥都木有","data":null}"#,
			// An answer, but pointing somewhere this app has no reason to fetch.
			#"{"code":0,"data":{"pic":"http://example.com/tracker.gif"}}"#,
			#"{"code":0,"data":{}}"#,
			"not json at all"
		] {
			#expect(VideoEmbed.previewImageURL(inAPIResponse: Data(source.utf8)) == nil, "should refuse \(source)")
		}
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
Where a display's rotation goes next.

Which website a display is showing is `Defaults[.currentWebsites]`, one entry per display, so "exactly
one per display" is the shape of the storage and there is nothing left here to check it with — see
`ScopeTests` for the two things about it that can still be got wrong, and that a `swift test` can
reach: that nothing reads the flag it replaced, and that the key is the display.

What is left is the arithmetic the mark is fed into. It was written and shipped on a one-display
machine, where a list-wide answer and a per-display answer are the same answer, and the difference is
not visible by reading: it shows as one screen quietly refusing to rotate.
*/
@Suite("Current website per display")
struct CurrentWebsiteTests {
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

	/**
	And the same answer from the other function, which is the one a display reads on every rebuild.

	These two cases arrived here from a suite about unplugging a display. That suite existed because a
	website was pinned to a screen, so pulling a cable pushed a second wallpaper onto the screen it
	landed on and something had to decide between two claims on one desktop. Nothing is pushed onto a
	screen any more — a display picks a playlist — so the tie-break is gone and these are what is left
	of it: the marked one wins, and an unmarked display shows the top of its list rather than nothing.

	The second is the case with teeth. "Nothing is marked" is the ordinary state of a display nobody
	has picked for, and of one whose website was deleted, so answering it with `nil` is a blank screen
	on a fresh install rather than an edge case.
	*/
	@Test("A display shows the marked website, and the top of its list when nothing is marked")
	func theMarkedWebsiteIsTheOneOnScreen() {
		#expect(showingIndex(isCurrent: [false, true]) == 1)
		#expect(showingIndex(isCurrent: [false, false]) == 0)
		#expect(showingIndex(isCurrent: []) == nil)
	}
}

/**
How long a display waits between websites.

Not as simple as it looks, in one place: the clamp. It is the far end of a text field where "0" and a
nine-digit number are each one keystroke away and both mean a wallpaper that has stopped.

There used to be a second: a fallback to the machine-wide interval every version up to 0.1.3 stored,
so that an upgrading user's number survived the move to one per display. That key is deleted and so
is the test for it.
*/
@Suite("Rotation interval")
struct RotationIntervalTests {
	@Test("A display with a number of its own uses it")
	func stored() {
		#expect(rotationInterval(stored: 12) == 12)
	}

	@Test("A machine that never set one gets the default")
	func noSettingAtAll() {
		#expect(rotationInterval(stored: nil) == defaultRotationIntervalMinutes)
	}

	@Test("Rotation being off is not stored as a missing interval any more")
	func offIsNotAbsence() {
		// Up to 0.1.3 a nil interval meant "do not rotate", and that meaning moved to `RotationMode`.
		// So nil now has to mean a length rather than a refusal, or a display switched to Loop would
		// come up with no interval and never move.
		#expect(rotationInterval(stored: nil) >= rotationIntervalRange.lowerBound)
	}

	@Test("A stored number outside the range is brought back into it")
	func storedIsClamped() {
		#expect(rotationInterval(stored: 0) == rotationIntervalRange.lowerBound)
		#expect(rotationInterval(stored: 99_999) == rotationIntervalRange.upperBound)
		#expect(rotationInterval(stored: .nan) == defaultRotationIntervalMinutes)
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
Which part of the web view the display is actually showing.

Two things photograph the wallpaper's own web view: the menu bar band, which takes a strip off the
top to tint the menu bar with, and the panel's thumbnail, which takes all of it. With a region framed
neither of them wants the view's bounds — `PageView` lays the page out as the whole thing, several
times larger than the window, and clips it — so what is on screen is a window into those bounds, and
that window is what this works out.

Both readers got it wrong in the same direction and for the same reason, which is that they each
answered it separately. The band took its colour off the top of the whole page, usually a part of it
not on screen at all. The thumbnail asked for nothing, which `WKSnapshotConfiguration` reads as the
bounds, so the panel drew an entire website shrunk into 260 points beside a display showing one
paragraph of it.
*/
@Suite("What of the page is on screen")
struct OnScreenRegionTests {
	private let pageSize = CGSize(width: 1470, height: 896)

	@Test("With no magnification it is the whole page")
	func unzoomedIsEverything() {
		let region = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 1).onScreenRegion(inPageOfSize: pageSize)

		#expect(region == CGRect(origin: .zero, size: pageSize))
	}

	@Test("It is the size of the window, not the size of the region")
	func sizeIsNotScaled() {
		let region = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2).onScreenRegion(inPageOfSize: pageSize)

		// Half the page across, centred, magnified twice: the top-left of the region is a quarter of
		// the page in and down, and that lands at half the page's dimensions once magnified.
		#expect(region.origin.x == pageSize.width / 2)
		#expect(region.origin.y == pageSize.height / 2)

		// Not the region's own size, and not the page magnified. Both are plausible and both are
		// wrong: the view's coordinates are already magnified, so what is on screen stays one window
		// across and one window down. Literals rather than the property above: a rectangle's members
		// are `CGFloat` and these are `Double`, and `#expect` reports the mixed comparison as failed
		// even when both sides print the same number.
		#expect(region.width == 1470)
		#expect(region.height == 896)
	}

	@Test("A region at the top-left is the view's own corner")
	func topLeftRegionIsTheCorner() {
		let region = Zoom(center: .zero, scale: 4).onScreenRegion(inPageOfSize: pageSize)

		#expect(region.origin == .zero)
	}

	@Test("A region at the bottom-right stays inside the magnified page")
	func bottomRightRegionStaysInBounds() {
		let region = Zoom(center: CGPoint(x: 1, y: 1), scale: 4).onScreenRegion(inPageOfSize: pageSize)

		// The region is clamped to the page's far corner, so its origin is three quarters of the way
		// along, and magnified that is the far edge of the view minus one window's width.
		#expect(region.origin.x == pageSize.width * 3)
		#expect(region.maxX == pageSize.width * 4)

		// The far corner exactly, which is what makes this safe to hand to `takeSnapshot`: a rectangle
		// that ran past the end of the magnified page would be asking for pixels that do not exist.
		#expect(region.maxY == pageSize.height * 4)
	}

	@Test("The menu bar strip is the top of it")
	func theBandTakesTheTopOfIt() {
		let zoom = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2)
		var strip = zoom.onScreenRegion(inPageOfSize: pageSize)
		strip.size.height = 33

		// The shortening `MenuBarBand.topStripOfWallpaper` does, kept here so the two readers' one
		// difference is written down: the origin is shared and only the height is the band's own.
		#expect(strip.origin == zoom.onScreenRegion(inPageOfSize: pageSize).origin)
		#expect(strip.width == 1470)
		#expect(strip.height == 33)
	}

	/**
	Asking with the wrong page size is not a rounding error, and the error has a law.

	The band and the view that lays the page out used to work the page's size out separately — one from
	the screen, one from the window, which `DesktopWindow.setFrame` makes a point taller on purpose. A
	point of page is `scale` points of view, so what the band sampled sat below what was on screen by
	`scale - 1` points: nothing at 1x, 19 at the maximum. Against a 33-point menu bar that is 58% of the
	strip's own height, so most of what was sampled was not what was behind the menu bar.

	Both readers go through `onScreenRegion` now and `pageLayoutSize` is read off the window, so there
	is one page size and one rectangle. This is what the disagreement cost while there were two.

	Independent of the screen's size, which is why it is worth pinning: it is a property of the
	disagreement, not of one Mac. Nothing in the package target can hold `pageLayoutSize` to the window
	it now reads — that reaches `NSWindow` — so this says what a disagreement costs rather than that
	there is not one.
	*/
	@Test("A point of disagreement about the page height moves the sampled strip by a magnification, less one")
	func aPointOfPageIsAMagnificationOfView() {
		for scale in [2.0, 5.0, 10.0, Zoom.maximumScale] {
			// Pushed to the bottom of the page, where the clamp holds the region against the far edge and
			// the whole of the extra point lands in the offset.
			let zoom = Zoom(center: CGPoint(x: 0.5, y: 1), scale: scale)

			let asLaidOut = zoom.onScreenRegion(inPageOfSize: CGSize(width: pageSize.width, height: pageSize.height + 1))
			let asTheScreenWouldSay = zoom.onScreenRegion(inPageOfSize: pageSize)

			// Compared as `Double` against a `Double`. A `CGRect`'s members are `CGFloat`, and the test
			// next door records why that matters: a mixed comparison reports as failed with both sides
			// printing the same number.
			let drift = Double(asLaidOut.origin.y) - Double(asTheScreenWouldSay.origin.y)

			#expect(drift == scale - 1)
		}
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
		// Through `URL` and back out, because that is the trip the real one makes: the system hands
		// the app delegate a `URL`, not the string it was typed as. The two routes do not agree on
		// everything — `nifro:///reload` has no host built from the string and an empty one built
		// from the `URL` — so testing the shorter route would be testing a path nothing takes.
		urlCommand(from: URLComponents(url: URL(string: string)!, resolvingAgainstBaseURL: false)!)
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

	// The three tests below run the thumbnail sweep against real files, because `DiskBudget` compiles
	// into the SwiftPM target and the sweep is pure Foundation — and the only thing worth knowing
	// about a function that deletes files is which files it deleted.
	//
	// The names are arbitrary strings on purpose. What the app passes is the SHA-256 of a website's
	// address, and applying that mapping belongs to `SimpleImageCache`, which is the only thing that
	// knows it. The sweep is told which names are live and nothing else.

	/**
	A throwaway directory holding one file per name.
	*/
	private static func directoryWithFiles(_ names: [String]) throws -> URL {
		let directory = URL.temporaryDirectory.appending(path: "DiskBudgetTests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		for name in names {
			try Data("thumbnail".utf8).write(to: directory.appending(path: name))
		}

		return directory
	}

	@Test("A thumbnail no website claims is deleted, and a live one is left alone")
	func collectsThumbnailsNoWebsiteClaims() throws {
		// The two ways a file is orphaned: the website was deleted, or its address was edited and the
		// file is still named for the old one. Both look identical from here, which is the point of
		// sweeping by what is live rather than by what happened.
		let directory = try Self.directoryWithFiles(["live", "deletedWebsite", "oldAddress"])

		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		DiskBudget.removeOrphanedFiles(in: directory, keeping: ["live"])

		#expect(FileManager.default.fileExists(atPath: directory.appending(path: "live").path))
		#expect(!FileManager.default.fileExists(atPath: directory.appending(path: "deletedWebsite").path))
		#expect(!FileManager.default.fileExists(atPath: directory.appending(path: "oldAddress").path))
	}

	@Test("An empty website list leaves the thumbnails alone, rather than deleting all of them")
	func emptyListIsNotAMandateToEmptyTheThumbnailCache() throws {
		// The same distrust `orphans` above states, and for consistency rather than for the same
		// stakes: a thumbnail costs a refetch, not a login. Two sweeps reading one list should not
		// disagree about what an empty reading of it means.
		let directory = try Self.directoryWithFiles(["one", "two"])

		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		DiskBudget.removeOrphanedFiles(in: directory, keeping: [])

		#expect(FileManager.default.fileExists(atPath: directory.appending(path: "one").path))
		#expect(FileManager.default.fileExists(atPath: directory.appending(path: "two").path))
	}

	@Test("A cache directory that was never created is not an error")
	func missingDirectoryIsNotAnError() {
		// `removeAllImages` deletes the directory itself and it is recreated lazily on the next write,
		// so the sweep can arrive at a path that does not exist. It has to be a no-op rather than a
		// crash: it runs on a background queue with nothing above it to catch anything.
		DiskBudget.removeOrphanedFiles(
			in: URL.temporaryDirectory.appending(path: "DiskBudgetTests-\(UUID().uuidString)"),
			keeping: ["live"]
		)
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
What the app installs on a first launch: which websites, and in what order.

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
			"Calculating Empires",
			"Svalbard — A Journey to the North Pole",
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
	The placement half of the order above: ranking the list decides nothing if every screen is dealt
	the same page off the top of it.

	`firstLaunchDisplayOrder` rather than the install, because the install writes `Defaults`, asks
	`NSScreen` and needs a running app — the arithmetic is the part that can be wrong, so it is the
	part that was pulled out where it can be called. What it hands back is zipped against the ranked
	websites, so its Nth entry is the screen the Nth website lands on.
	*/
	@Test("The Nth screen is dealt the Nth shipped website, main screen first")
	func firstLaunchPlacement() {
		#expect(firstLaunchDisplayOrder(main: "main", attached: ["main", "side"]) == ["main", "side"])

		// The arrangement puts the main screen second; the first website still belongs on it.
		#expect(firstLaunchDisplayOrder(main: "main", attached: ["side", "main"]) == ["main", "side"])

		// More screens than websites: `zip` stops at the eighth, and the ninth screen starts at the top
		// of the list on its own. More websites than screens: the rest stay in the list, unshown.
		#expect(firstLaunchDisplayOrder(main: "a", attached: ["a", "b", "c"]) == ["a", "b", "c"])
		#expect(Array(zip(firstLaunchDisplayOrder(main: "a", attached: ["a", "b"]), 1...8)).count == 2)

		// A Mac with the lid shut and nothing plugged in still gets one wallpaper, under the key a
		// screen that arrives later reads from.
		#expect(firstLaunchDisplayOrder(main: String?.none, attached: []) == [nil])
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
}
