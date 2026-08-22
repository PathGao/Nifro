import AppKit
import CoreImage
import WebKit

/**
An opaque band filling the strip of the wallpaper that sits behind the menu bar.

macOS tints the menu bar from whatever is behind it, so extending the wallpaper up there is the only way to get a menu bar that matches. The catch is that it tints from the *content*: text, borders and whatever else happens to be along the top edge of the page show through as visual noise.

The band keeps the tint and drops the noise. It is filled with the average colour of the strip it covers, so the menu bar picks up the same colour it would have picked up anyway, and the page underneath stops showing through.
*/
final class MenuBarBandView: NSView {
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

	// The band is decoration sitting on top of a wallpaper. It must never take a click that belongs to the desktop.
	override func hitTest(_ point: CGPoint) -> NSView? { nil }
}

extension WallpaperScene {
	/**
	Height of the strip the menu bar occupies on the wallpaper's screen, or 0 when there is none.
	*/
	var menuBarHeight: CGFloat {
		guard let screen else {
			return 0
		}

		return screen.frame.height - screen.frameWithoutStatusBar.height
	}

	var shouldShowMenuBarBand: Bool {
		Defaults[.extendBelowMenuBar]
			&& Defaults[.solidColorUnderMenuBar]
			&& menuBarHeight > 0
	}

	/**
	Add or remove the band to match the current setting.
	*/
	func installMenuBarBandIfNeeded() {
		guard shouldShowMenuBarBand else {
			menuBarBand?.removeFromSuperview()
			menuBarBand = nil
			return
		}

		guard let contentView = window.contentView else {
			return
		}

		let band = menuBarBand ?? MenuBarBandView()
		menuBarBand = band

		band.frame = CGRect(
			x: 0,
			y: contentView.bounds.maxY - menuBarHeight,
			width: contentView.bounds.width,
			height: menuBarHeight
		)
		band.autoresizingMask = [.width, .minYMargin]

		if band.superview !== contentView {
			band.removeFromSuperview()
			contentView.addSubview(band)
		}

		refreshMenuBarBandColor()
	}

	/**
	Sample the top strip of the page and paint the band with its average colour.

	Re-sampled on every load rather than once: the whole point is that the menu bar keeps matching the wallpaper, and the wallpaper changes.
	*/
	func refreshMenuBarBandColor() {
		guard
			let band = menuBarBand,
			shouldShowMenuBarBand
		else {
			return
		}

		let webView = webViewController.webView
		let configuration = WKSnapshotConfiguration()
		configuration.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: menuBarHeight)

		guard configuration.rect.width > 0, configuration.rect.height > 0 else {
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
	var averageColor: NSColor? {
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
