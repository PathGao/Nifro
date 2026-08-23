import AppKit
import CoreImage
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

	var color: NSColor {
		get { bandView.color }
		set { bandView.color = newValue }
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

		orderBack(nil)
	}

	func follow(_ screen: NSScreen) {
		setFrame(Self.frame(on: screen), display: true)
	}

	static func frame(on screen: NSScreen) -> CGRect {
		let height = screen.menuBarHeight

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

extension NSScreen {
	/**
	Height of the strip the menu bar occupies on this screen, or 0 when it has none.
	*/
	var menuBarHeight: Double { frame.height - frameWithoutStatusBar.height }
}

extension WallpaperScene {
	/**
	Add or remove the band to match the screen the scene is on.
	*/
	func installMenuBarBandIfNeeded() {
		guard
			// Disabled means nothing of this app is on screen but the menu bar icon, and the band is
			// on screen. Checked here rather than by whoever takes it down, because installing runs
			// from every content change — taking it down and then letting one of those put it back is
			// how it survived being disabled in the first place.
			AppState.shared.isEnabled,
			let screen,
			screen.menuBarHeight > 0
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
	}

	/**
	Sample the top strip of the page and paint the band with its average colour.

	Re-sampled on every load rather than once, because the wallpaper changes and the menu bar has to
	keep matching it.
	*/
	func refreshMenuBarBandColor() {
		guard
			let band = menuBarBand,
			let screen
		else {
			return
		}

		let webView = webViewController.webView
		let configuration = WKSnapshotConfiguration()
		configuration.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: screen.menuBarHeight)

		guard
			configuration.rect.width > 0,
			configuration.rect.height > 0
		else {
			return
		}

		webView.takeSnapshot(with: configuration) { image, _ in
			guard let color = image?.averageColor else {
				return
			}

			band.color = color
		}
	}
}

extension NSImage {
	/**
	The average colour of the whole image, or `nil` if it cannot be read.
	*/
	fileprivate var averageColor: NSColor? {
		guard
			let tiff = tiffRepresentation,
			let input = CIImage(data: tiff),
			let filter = CIFilter(name: "CIAreaAverage", parameters: [
				kCIInputImageKey: input,
				kCIInputExtentKey: CIVector(cgRect: input.extent)
			]),
			let output = filter.outputImage
		else {
			return nil
		}

		var pixel = [UInt8](repeating: 0, count: 4)

		CIContext(options: [.workingColorSpace: NSNull()]).render(
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
