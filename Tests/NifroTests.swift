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

	@Test("Page and screen coordinates are exact inverses")
	func roundTrip() {
		// What the drag-to-select mode relies on: you draw on screen, it stores page pixels,
		// and putting the window back has to land on the same rectangle you drew.
		let screen = CGRect(x: 1600, y: 200, width: 1600, height: 1000)

		for crop in [
			CGRect(x: 0, y: 0, width: 100, height: 100),
			CGRect(x: 250, y: 700, width: 400, height: 300),
			CGRect(x: 0, y: 900, width: 1600, height: 100)
		] {
			let there = crop.screenFrame(inScreen: screen)
			let back = there.pageFrame(inScreen: screen)

			#expect(back == crop)
		}
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
Coverage detection. What it has to get right is the difference between "one patch you would actually notice" and "slivers that add up to a number".
*/
@Suite("Coverage detection")
struct CoverageTests {
	private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

	/// The same constant the app checks against, not a copy of it.
	private let meaningful = minimumMeaningfulPatchArea

	@Test("Nothing on screen leaves the whole screen visible")
	func noWindows() {
		#expect(largestUncoveredRegion(of: screen, covering: []).area == 1600 * 1000)
	}

	@Test("A window filling the screen leaves nothing")
	func fullCover() {
		#expect(largestUncoveredRegion(of: screen, covering: [screen]).area == 0)
	}

	@Test("A window covering half the screen leaves the other half")
	func halfCover() {
		let half = CGRect(x: 0, y: 0, width: 800, height: 1000)
		let patch = largestUncoveredRegion(of: screen, covering: [half]).area

		#expect(abs(patch - 800 * 1000) < 1000)
		#expect(patch > meaningful)
	}

	@Test("Overlapping windows are not double counted")
	func overlappingWindows() {
		let left = CGRect(x: 0, y: 0, width: 1000, height: 1000)
		let right = CGRect(x: 600, y: 0, width: 1000, height: 1000)

		#expect(largestUncoveredRegion(of: screen, covering: [left, right]).area == 0)
	}

	@Test("A window off to the side covers nothing")
	func windowOnAnotherDisplay() {
		let elsewhere = CGRect(x: 2000, y: 0, width: 800, height: 600)
		#expect(largestUncoveredRegion(of: screen, covering: [elsewhere]).area == 1600 * 1000)
	}

	@Test("The case this whole mechanism exists for: everything covered but a thin strip")
	func onlyAStripShowing() {
		// One maximized window on the desktop. What survives is a band too shallow to read as wallpaper.
		let almostEverything = CGRect(x: 0, y: 0, width: 1600, height: 985)

		#expect(largestUncoveredRegion(of: screen, covering: [almostEverything]).area < meaningful)
	}

	@Test("Thin margins on all four sides do not add up to something visible")
	func scatteredSlivers() {
		// The case a percentage rule gets wrong: four 10pt margins are 3.6% of the screen,
		// comfortably past a 2% threshold, while showing nothing anybody would call a wallpaper.
		let window = CGRect(x: 10, y: 10, width: 1580, height: 980)

		let totalUncovered = (1600.0 * 1000) - (1580.0 * 980)
		#expect(totalUncovered / (1600 * 1000) > 0.02)

		// Each margin is its own patch, and every one of them is too thin to matter.
		#expect(largestUncoveredRegion(of: screen, covering: [window]).area < meaningful)
	}

	@Test("The threshold sits between a patch you would notice and one you would not")
	func thresholdBracket() {
		// The assertions about thin strips pass for any positive threshold: the grid rounds a 15pt
		// band to zero area on its own, so they test the grid, not the number. These two bracket the
		// number itself. On this screen a grid cell is 25 by 25, so the threshold is 64 cells.
		func corner(_ side: Double) -> [CGRect] {
			[
				CGRect(x: side, y: 0, width: 1600 - side, height: 1000),
				CGRect(x: 0, y: side, width: 1600, height: 1000 - side)
			]
		}

		// 12 by 12 cells.
		#expect(largestUncoveredRegion(of: screen, covering: corner(300)).area > meaningful)

		// 6 by 6 cells.
		#expect(largestUncoveredRegion(of: screen, covering: corner(150)).area < meaningful)
	}

	@Test("A genuinely visible desktop stays above the threshold")
	func visibleDesktop() {
		let window = CGRect(x: 200, y: 200, width: 900, height: 600)

		#expect(largestUncoveredRegion(of: screen, covering: [window]).area > meaningful)
	}

	@Test("Two patches touching only at a corner are two patches")
	func diagonalPatchesDoNotJoin() {
		// Windows meeting at the centre leave four quadrants that touch only at one point.
		let vertical = CGRect(x: 700, y: 0, width: 200, height: 1000)
		let horizontal = CGRect(x: 0, y: 400, width: 1600, height: 200)

		let patch = largestUncoveredRegion(of: screen, covering: [vertical, horizontal]).area

		// One quadrant, not the sum of four.
		#expect(patch < 1600 * 1000 / 2)
		#expect(patch > meaningful)
	}

	@Test("A degenerate region reports nothing visible rather than dividing by zero")
	func emptyRegion() {
		#expect(largestUncoveredRegion(of: .zero, covering: [screen]).area == 0)
	}

	@Test("Window-server rectangles flip into AppKit coordinates")
	func flipping() {
		// A menu-bar-height band at the top of a 1000pt arrangement.
		let fromWindowServer = CGRect(x: 0, y: 0, width: 1600, height: 25)
		let flipped = flippingFromWindowServer(fromWindowServer, arrangementHeight: 1000)

		#expect(flipped.minY == 975)
		#expect(flipped.maxY == 1000)
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

	@Test("The address says nothing about sound")
	func soundIsNotBakedIn() throws {
		// Muting is a per-website setting that outlives this URL. A `mute` parameter here would be a
		// second answer to the same question, and the one the user cannot change.
		for source in [
			"https://www.youtube.com/watch?v=jNQXAC9IVRw",
			"https://www.bilibili.com/video/BV1xx411c7mD"
		] {
			let url = try #require(URL(string: source))
			let player = try #require(VideoEmbed.playerURL(for: url))
			#expect(!player.absoluteString.contains("mute"), "\(source) still carries a mute parameter")
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
}

/**
Deciding what a page is from what it reports about itself.

The classifier is deliberately biased towards `animated`. Calling a moving page still freezes
something the user put there because it moves, which they notice immediately; calling a still page
animated costs a rendering process they would not have noticed either way.
*/
@Suite("Page activity")
struct PageActivityTests {
	private func sample(
		frames: Int = 0,
		animations: Int = 0,
		media: Bool = false,
		mutations: Int = 0
	) -> ActivitySample {
		.init(
			animationFrames: frames,
			runningAnimations: animations,
			isPlayingMedia: media,
			mutations: mutations,
			seconds: 10
		)
	}

	@Test("A document that does nothing is still")
	func staticDocument() {
		#expect(classify(Array(repeating: sample(), count: 6)) == .still)
	}

	@Test("A page drawing every frame is animated")
	func animating() {
		#expect(classify(Array(repeating: sample(frames: 600), count: 6)) == .animated)
	}

	@Test("CSS animation counts even though it requests no frames")
	func cssAnimation() {
		// The trap this guards: a page animated entirely in CSS runs on the compositor and never
		// calls requestAnimationFrame, so the frame counter reads zero while the page visibly moves.
		#expect(classify(Array(repeating: sample(animations: 1), count: 6)) == .animated)
	}

	@Test("Playing media counts, however quiet the rest of the page is")
	func media() {
		#expect(classify(Array(repeating: sample(media: true), count: 6)) == .animated)
	}

	@Test("One burst of movement is enough to call the whole page animated")
	func oneBusyWindow() {
		var samples = Array(repeating: sample(), count: 5)
		samples.append(sample(animations: 1))

		#expect(classify(samples) == .animated)
	}

	@Test("A clock ticking seconds is animated, not something to photograph")
	func secondsClock() {
		#expect(classify(Array(repeating: sample(mutations: 12), count: 6)) == .animated)
	}

	@Test("A page that changes a few times a minute is periodic")
	func slowFeed() {
		#expect(classify(Array(repeating: sample(mutations: 1), count: 6)) == .periodic)
	}

	@Test("With nothing to go on, assume it moves")
	func noSamples() {
		#expect(classify([]) == .animated)
	}

	@Test("Refresh interval is at least a minute and never over an hour")
	func refreshBounds() {
		#expect(refreshInterval(forMutationRate: 0) == 60 * 30)
		#expect(refreshInterval(forMutationRate: 10) == 60)
		#expect(refreshInterval(forMutationRate: 0.0001) == 60 * 60)

		// Twice the observed period, so a page seen changing every five minutes is not reloaded
		// every five minutes to find it has not changed yet.
		#expect(refreshInterval(forMutationRate: 1.0 / 300) == 600)
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

	@Test("A framed region comes back as the region that was framed")
	func roundTrip() {
		let framed = CGRect(x: 400, y: 250, width: 800, height: 500)
		let zoom = Zoom(region: framed, inPageOfSize: page)

		#expect(zoom.region(inPageOfSize: page) == framed)
	}

	@Test("The region is always the shape of the page it is asked about")
	func followsTheDisplay() {
		// Framed on a 16:10 screen, shown on a 16:9 one.
		let zoom = Zoom(region: CGRect(x: 400, y: 250, width: 800, height: 500), inPageOfSize: page)
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

	@Test("Zooming out below the whole page is not a thing")
	func neverSmallerThanThePage() {
		// A page-sized region magnified less than once would be a window with nothing along two edges.
		let region = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 0.25).region(inPageOfSize: page)

		#expect(region == CGRect(origin: .zero, size: page))
	}

	@Test("The identity zoom is the whole page")
	func identityIsEverything() {
		#expect(Zoom.identity.region(inPageOfSize: page) == CGRect(origin: .zero, size: page))
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

/**
Which windows count as hiding the wallpaper.

The first version of this matched the system windows by the name the window list reports, which is
the localised application name. On an English Mac it worked. On a Chinese one "Dock" never matched
程序坞, so the Dock's full-screen window counted as coverage and every wallpaper was judged
completely hidden from the moment it appeared. These tests are the reason that cannot come back.
*/
@Suite("Window coverage")
struct WindowCoverageTests {
	@Test("The Dock does not hide the wallpaper, whatever its name is in")
	func dockIsIgnoredInEveryLanguage() {
		for name in ["Dock", "程序坞", "Anclaje", "ドック"] {
			#expect(
				!Coverage.hidesWallpaper(
					layer: 0,
					alpha: 1,
					bundleIdentifier: "com.apple.dock",
					processName: name,
					isOwnWindow: false
				),
				"the Dock counted as coverage when it reports itself as \(name)"
			)
		}
	}

	@Test("An ordinary application window hides the wallpaper")
	func ordinaryWindowsCover() {
		#expect(
			Coverage.hidesWallpaper(
				layer: 0,
				alpha: 1,
				bundleIdentifier: "com.google.Chrome",
				processName: "Google Chrome",
				isOwnWindow: false
			)
		)
	}

	@Test("Nothing below the desktop, see-through, or ours counts")
	func theThreeExemptions() {
		let chrome = (bundle: "com.google.Chrome", name: "Google Chrome")

		// Desktop icons and the wallpaper itself live below zero.
		#expect(!Coverage.hidesWallpaper(layer: -1, alpha: 1, bundleIdentifier: chrome.bundle, processName: chrome.name, isOwnWindow: false))
		// You can see the page through it.
		#expect(!Coverage.hidesWallpaper(layer: 0, alpha: 0.5, bundleIdentifier: chrome.bundle, processName: chrome.name, isOwnWindow: false))
		// The wallpaper cannot hide itself.
		#expect(!Coverage.hidesWallpaper(layer: 0, alpha: 1, bundleIdentifier: chrome.bundle, processName: chrome.name, isOwnWindow: true))
	}

	@Test("A process with no bundle identifier is matched by name")
	func processesWithoutABundle() {
		// WindowServer is not an application, so it has no bundle identifier and no localised name.
		#expect(!Coverage.hidesWallpaper(layer: 0, alpha: 1, bundleIdentifier: nil, processName: "Window Server", isOwnWindow: false))
		#expect(Coverage.hidesWallpaper(layer: 0, alpha: 1, bundleIdentifier: nil, processName: "something else", isOwnWindow: false))
	}
}
