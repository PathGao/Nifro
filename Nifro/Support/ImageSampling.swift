import AppKit
import CoreImage.CIFilterBuiltins

/**
The two questions anything asks of a snapshot, and the one renderer they share.

A `CIContext` is a renderer, not a value: building one per call stood up a fresh one on every page
load on every scene, to produce a single pixel. It holds nothing belonging to a particular image, so
there is nothing for its callers to disagree about — which is why one lives here rather than one per
file that samples.

This file is listed in `Package.swift`, and that is the point of it existing rather than the answers
sitting beside their callers. `isFlatColour` decides when the desktop puts a page on screen, and it
is exactly the kind of rule that fails silently: the first version rendered the filter's output as
one pixel wide and two tall, which is the wrong way round, so every image compared equal to itself
and every page read as "not drawn yet". It built, it shipped nothing to a test, and the only symptom
would have been a reveal that never fired early. Nothing in `Wallpaper` or `Visibility` can be
reached by `swift test`; this can.
*/
enum ImageSampling {
	static let context = CIContext(options: [.workingColorSpace: NSNull()])
}

extension NSImage {
	/**
	Whether every pixel of this image is the same colour.

	Which is what a page that has not drawn anything looks like: `takeSnapshot` on a web view whose
	document has not painted comes back as one flat field, and a page that has drawn is not flat
	anywhere across a whole-screen rectangle. `WallpaperScene.watchForFirstPaint` is the reader — this
	is the difference between "there is something worth putting on the desktop" and "there is not
	yet".

	`areaMinMax` rather than a loop over the pixels: the comparison happens where the pixels already
	are, and the answer comes back as two — the per-channel minimum and maximum of the whole region.
	A loop over `NSBitmapImageRep.colorAt` measured 4–14ms on a 260-point thumbnail, and this is paid
	on every tick of a poll.

	**The output is two pixels side by side, not one above the other.** `areaMinMax`'s extent is
	2×1. Rendering it as 1×2 reads the minimum twice, every image is then flat, and the caller quietly
	does nothing for ever. That is what `FlatColourTests` is for.

	The alpha channel is not compared, but it is not ignored either, and the difference matters enough
	to write down: `RGBA8` is premultiplied, so a transparent pixel is `0,0,0` in the three channels
	this does compare. An image that is transparent in one place and opaque in another therefore reads
	as drawn. That is not a case a snapshot produces — a page that has not painted comes back uniform
	in both — so it is left alone rather than corrected into a rule nothing exercises.

	The failure is one-directional on purpose. A page whose first paint really is one flat colour —
	a video player showing black before it boots — reads as "not drawn yet" and waits for `didFinish`,
	which is exactly where the desktop was before this existed. A page that has drawn cannot read as
	flat.
	*/
	var isFlatColour: Bool {
		var proposed = CGRect(origin: .zero, size: size)

		guard let cgImage = cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
			// Nothing to look at is not the same as one colour, but both mean "do not reveal on this
			// tick", and the caller has no third thing to do about it.
			return true
		}

		let input = CIImage(cgImage: cgImage)
		let filter = CIFilter.areaMinMax()
		filter.inputImage = input
		filter.extent = input.extent

		guard let output = filter.outputImage else {
			return true
		}

		// Minimum in the first four bytes, maximum in the second four.
		var pixels = [UInt8](repeating: 0, count: 8)

		ImageSampling.context.render(
			output,
			toBitmap: &pixels,
			rowBytes: 8,
			bounds: CGRect(x: 0, y: 0, width: 2, height: 1),
			format: .RGBA8,
			colorSpace: nil
		)

		return pixels[0] == pixels[4] && pixels[1] == pixels[5] && pixels[2] == pixels[6]
	}
}
