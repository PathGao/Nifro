import AppKit
import Testing
@testable import NifroLogic

/**
The rule that decides when a page reaches the desktop.

`WallpaperScene` used to put the page on screen when `didFinish` fired, which waits for everything a
page asks for. Measured on a hidden web view: the page is drawn 0.6–3.2s before that. So a plain load
now asks, on a slow cadence, whether the snapshot it can already take shows anything — and
`isFlatColour` is the whole of "anything".

It is here rather than beside its caller because it is the kind of rule that fails silently. The
first version rendered `areaMinMax`'s output as one pixel wide and two tall; the extent is 2×1, so it
read the minimum twice, every image compared equal to itself, and every page in the world read as
"has not drawn". Nothing would have crashed and nothing would have looked wrong — the desktop would
simply have gone on waiting for `didFinish`, which is where it started. That bug survived a build and
a `swift test` run with no test to hit it. This is that test.
*/
@Suite("A snapshot of a page that has not drawn is one flat colour")
struct FlatColourTests {
	private static func filled(with colours: [NSColor], size: CGSize = CGSize(width: 64, height: 64)) -> NSImage {
		let image = NSImage(size: size)
		image.lockFocus()

		let bandHeight = size.height / Double(colours.count)

		for (index, colour) in colours.enumerated() {
			colour.setFill()
			NSRect(x: 0, y: Double(index) * bandHeight, width: size.width, height: bandHeight).fill()
		}

		image.unlockFocus()
		return image
	}

	@Test("One colour reads as flat, whichever colour it is")
	func oneColourIsFlat() {
		for colour in [NSColor.white, .black, .clear, .systemBlue] {
			#expect(
				Self.filled(with: [colour]).isFlatColour,
				"A snapshot that is entirely one colour is a page that has not drawn, and reading it as drawn puts a blank rectangle on the desktop."
			)
		}
	}

	@Test("Two colours read as drawn")
	func twoColoursAreNotFlat() {
		#expect(
			!Self.filled(with: [.white, .black]).isFlatColour,
			"A snapshot with more than one colour in it reads as blank, so the desktop goes on waiting for `didFinish` and nothing reveals early."
		)
	}

	/**
	The regression itself, in the axis it happened in.

	The bug read the filter's output as 1×2 instead of 2×1, which samples one pixel twice. An image
	that differs only across its *width* is the case that distinguishes the two: the vertical bands
	above would also have caught it, but this says out loud which axis the mistake was in.
	*/
	@Test("A difference across the width is a difference")
	func differenceAcrossTheWidth() {
		let image = NSImage(size: CGSize(width: 64, height: 64))
		image.lockFocus()
		NSColor.white.setFill()
		NSRect(x: 0, y: 0, width: 32, height: 64).fill()
		NSColor.black.setFill()
		NSRect(x: 32, y: 0, width: 32, height: 64).fill()
		image.unlockFocus()

		#expect(!image.isFlatColour)
	}

	/**
	Transparency is a difference, and that is written down rather than fixed.

	`RGBA8` is premultiplied, so a transparent pixel is `0,0,0` in the three channels the rule
	compares — an image transparent in one half and opaque in the other reads as drawn. A snapshot
	never produces that shape: a page that has not painted comes back uniform in both. Asserted so the
	next person to read the "alpha is not compared" line does not conclude the opposite.
	*/
	@Test("A half-transparent image reads as drawn, because the channels are premultiplied")
	func transparencyIsADifference() {
		let opaque = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
		let transparent = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)

		#expect(!Self.filled(with: [opaque, transparent]).isFlatColour)
	}
}
