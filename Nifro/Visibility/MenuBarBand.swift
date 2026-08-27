import AppKit
import CoreImage.CIFilterBuiltins
import WebKit

/**
A strip of solid colour behind the menu bar, in the average colour of the top of the page.

macOS tints the menu bar from whatever is rendered behind it, so a wallpaper that stops below the
menu bar leaves the menu bar tinted by the desktop picture underneath — a different colour from the
wallpaper the user is actually looking at. Extending the page up there fixes the colour and creates a
worse problem: the page's own headings, buttons and borders sit under the menu bar where they cannot
be read and cannot be clicked.

The band takes the tint and drops the content. It is its own window rather than a view inside the
wallpaper: the wallpaper window moves and resizes — a zoomed page, a window shrunk to whatever the
covering windows left visible — and the tint should not come and go with it.
*/
final class MenuBarBandWindow: NSWindow {
	private let bandView = MenuBarBandView()

	/**
	Whether a colour has ever been taken off a page for this band.

	Until one has, the band has nothing to say. It is built as soon as a scene exists, which is before
	anything has loaded, and showing it then means the menu bar takes a colour off a blank page — a
	menu bar that changes before the wallpaper it is supposed to be matching.
	*/
	private(set) var hasSampledColor = false

	var color: NSColor {
		get { bandView.color }
		set {
			bandView.color = newValue
			hasSampledColor = true
		}
	}

	init(screen: NSScreen) {
		super.init(
			contentRect: Self.frame(on: screen),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)

		isReleasedWhenClosed = false
		level = .desktop
		collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
		ignoresMouseEvents = true
		isOpaque = true
		hasShadow = false
		backgroundColor = .clear
		contentView = bandView
	}

	/**
	Put it on screen, or take it off.

	Not ordered in on creation. The band is built as soon as a scene exists, which is a second or so
	before the first page is visible, and a band on screen ahead of the page meant the menu bar
	changed colour on its own and the wallpaper arrived afterwards. It appears with the page instead.
	*/
	func setVisible(_ isVisible: Bool) {
		if isVisible {
			orderBack(nil)
		} else {
			orderOut(nil)
		}
	}

	func follow(_ screen: NSScreen) {
		setFrame(Self.frame(on: screen), display: true)
	}

	static func frame(on screen: NSScreen) -> CGRect {
		let height = screen.statusBarThickness

		return CGRect(
			x: screen.frame.minX,
			y: screen.frame.maxY - height,
			width: screen.frame.width,
			height: height
		)
	}
}

private final class MenuBarBandView: NSView {
	var color: NSColor = .clear {
		didSet {
			needsDisplay = true
		}
	}

	override var isOpaque: Bool { color.alphaComponent >= 1 }

	override func draw(_ dirtyRect: CGRect) {
		color.setFill()
		dirtyRect.fill()
	}

	// Decoration sitting over the desktop. It must never take a click that belongs there.
	override func hitTest(_ point: CGPoint) -> NSView? { nil }
}

extension WallpaperScene {
	/**
	Add or remove the band to match the screen the scene is on.
	*/
	func installMenuBarBandIfNeeded() {
		guard
			// Off means nothing of this app is on screen for this display, and the band is on screen.
			// Checked here rather than by whoever takes it down, because installing runs from every
			// content change — taking it down and then letting one of those put it back is how it
			// survived being disabled in the first place.
			//
			// `isSwitchedOff` rather than the app-wide switch this used to name. The argument above is
			// about a display having nothing on it, and there are two ways for that to be true; only
			// one of them was ever asked, so a display switched off on its own kept a band wearing the
			// colour of the page it was no longer showing. The predicate is where a third way would
			// join, so this line does not have to be found again.
			!isSwitchedOff,
			let screen,
			screen.statusBarThickness > 0
		else {
			menuBarBand?.close()
			menuBarBand = nil
			return
		}

		if let band = menuBarBand {
			band.follow(screen)
		} else {
			menuBarBand = MenuBarBandWindow(screen: screen)
		}

		refreshMenuBarBandColor()
		updateMenuBarBandVisibility()
	}

	/**
	The band is on screen exactly while the page is.

	One rule rather than two moments to keep in step. Anything that shows or hides the page calls
	this, and the colour is sampled from the page it is standing in for — which is only worth looking
	at once there is a page to sample.
	*/
	func updateMenuBarBandVisibility() {
		guard let band = menuBarBand else {
			return
		}

		band.setVisible(!webViewController.webView.isHidden && band.hasSampledColor)
	}

	/**
	Sample the top strip of the wallpaper and paint the band with its average colour.

	Re-sampled on every load rather than once, because the wallpaper changes and the menu bar has to
	keep matching it.
	*/
	func refreshMenuBarBandColor() {
		guard
			let band = menuBarBand,
			let screen,
			// Measured: sampling ran twice before the page was ever shown, off a hidden blank web view,
			// and that colour is what let the band on screen early. There is nothing worth taking a
			// colour off until the page is up.
			hasRevealedPage
		else {
			return
		}

		let webView = webViewController.webView
		let configuration = WKSnapshotConfiguration()

		// No `snapshotWidth`, unlike `WallpaperScene.snapshot()` next door, and that is measured rather
		// than an oversight. WebKit keeps the rectangle's aspect ratio, and this rectangle is a strip:
		// 1470 by 33 points is 44:1, so a width small enough to be worth asking for rounds the height
		// to nothing. Asking for 8 produced an image 0 pixels high, and the average came out of the
		// full-size pixels anyway — the cheap-looking snapshot was a snapshot that had not been scaled
		// at all. The panel's thumbnail is 260 points of a whole screen and has no such shape.
		//
		// Clipped rather than trusted. The rectangle is worked out from the size the page was laid out
		// at, and a display change moves that before the view holding the page has been rebuilt for it.
		configuration.rect = topStripOfWallpaper(height: screen.statusBarThickness).intersection(webView.bounds)

		guard
			configuration.rect.width > 0,
			configuration.rect.height > 0
		else {
			return
		}

		webView.takeSnapshot(with: configuration) { [weak self] image, _ in
			guard let color = image?.averageColor else {
				return
			}

			band.color = color

			// The first colour is also what lets the band on screen, so this is the moment to ask
			// again. Sampling is asynchronous, and it is the later of the two things the band waits
			// for — a page can be on screen a frame before there is a colour taken off it.
			self?.updateMenuBarBandVisibility()
		}
	}

	/**
	The `height` points of web view that end up along the top of the display, in the web view's own
	coordinates.

	With no region framed that is the web view's own top strip: the page fills the window at its own
	size, so the two tops are the same place. With one it is somewhere in the middle of the page, and
	`Zoom.topStrip(inPageOfSize:height:)` is where that is worked out — the same place `PageView` gets
	its magnification from, so the band cannot drift away from the thing it is standing in for.

	Reads `content` rather than `website?.zoom`, so it mirrors what is on screen rather than what the
	website asks for. The two differ for as long as a new website takes to load out of sight, and
	during that the old page is still up wearing the old region.
	*/
	private func topStripOfWallpaper(height: Double) -> CGRect {
		guard
			case .live(let zoom?) = content,
			let pageSize = pageLayoutSize
		else {
			return CGRect(x: 0, y: 0, width: webViewController.webView.bounds.width, height: height)
		}

		return zoom.topStrip(inPageOfSize: pageSize, height: height)
	}
}

extension NSImage {
	/**
	One rendering context for every sample.

	A `CIContext` is a renderer, not a value: building one per call stood up a fresh one on every page
	load on every scene, to produce a single pixel. It holds nothing belonging to a particular image,
	so there is nothing for the callers to disagree about.
	*/
	private static let averageColorContext = CIContext(options: [.workingColorSpace: NSNull()])

	/**
	The average colour of the whole image, or `nil` if it cannot be read.

	The pixels are asked for, not re-encoded. This used to go out through `tiffRepresentation` and
	back in through `CIImage(data:)`, which is a full TIFF written and parsed to hand Core Image
	something it can already be handed directly. Measured on the strip this samples — 1470 points
	wide on a 2× display, so 2940×66 pixels: the round trip allocated 779,614 bytes and cost 0.44ms,
	`cgImage(forProposedRect:context:hints:)` costs 0.004ms and allocates nothing, and both produce
	the same colour to the bit. End to end the sample went from 0.83ms to 0.52ms.

	`CIFilter.areaAverage()` rather than the filter's name in a string, so a typo in the name or in a
	parameter key is a build failure instead of a band that silently never changes colour: the string
	form returns an optional filter and takes `Any` values, and neither is checked until it runs.
	*/
	fileprivate var averageColor: NSColor? {
		var proposed = CGRect(origin: .zero, size: size)

		guard let cgImage = cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
			return nil
		}

		let input = CIImage(cgImage: cgImage)
		let filter = CIFilter.areaAverage()
		filter.inputImage = input
		filter.extent = input.extent

		guard let output = filter.outputImage else {
			return nil
		}

		var pixel = [UInt8](repeating: 0, count: 4)

		Self.averageColorContext.render(
			output,
			toBitmap: &pixel,
			rowBytes: 4,
			bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
			format: .RGBA8,
			colorSpace: nil
		)

		return NSColor(
			srgbRed: Double(pixel[0]) / 255,
			green: Double(pixel[1]) / 255,
			blue: Double(pixel[2]) / 255,
			alpha: 1
		)
	}
}
