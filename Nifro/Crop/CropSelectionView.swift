import AppKit

/**
Drag a rectangle over the wallpaper to choose what to keep.

The request this answers asked for exactly this and got a snippet of JavaScript instead: "I wish there was a way to visually select (by specifying the pixel range) and show only that part of the website" (Plash#138). Typing four numbers works, but nobody knows where the interesting part of a page is in page pixels — you know it when you see it.
*/
final class CropSelectionView: NSView {
	/**
	Called with the chosen rectangle in this view's coordinates, or `nil` if the user cancelled.
	*/
	var onFinish: ((CGRect?) -> Void)?

	private var anchor: CGPoint?
	private var selection: CGRect?

	/**
	Smaller than this and it was a stray click, not a selection.
	*/
	private static let minimumSide = 20.0

	override var acceptsFirstResponder: Bool { true }

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func draw(_ dirtyRect: CGRect) {
		NSColor.black.withAlphaComponent(0.55).setFill()
		dirtyRect.fill()

		guard let selection else {
			drawHint()
			return
		}

		// Punch the selection out of the dimming so the user sees the actual page underneath.
		NSColor.clear.set()
		selection.fill(using: .copy)

		NSColor.white.setStroke()
		let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
		outline.lineWidth = 1
		outline.stroke()

		drawLabel("\(Int(selection.width)) × \(Int(selection.height))", near: selection)
	}

	private func drawHint() {
		let text = "Drag to choose the part of the page to keep.  Esc to cancel."
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 15, weight: .medium),
			.foregroundColor: NSColor.white
		]
		let size = (text as NSString).size(withAttributes: attributes)

		(text as NSString).draw(
			at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
			withAttributes: attributes
		)
	}

	private func drawLabel(_ text: String, near rect: CGRect) {
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
			.foregroundColor: NSColor.white
		]
		let size = (text as NSString).size(withAttributes: attributes)
		let padding = 6.0

		// Above the selection normally, inside it when there is no room above.
		let originY = rect.maxY + padding + size.height > bounds.maxY
			? rect.maxY - size.height - padding
			: rect.maxY + padding

		let box = CGRect(
			x: rect.minX,
			y: originY,
			width: size.width + padding * 2,
			height: size.height + padding
		)

		NSColor.black.withAlphaComponent(0.7).setFill()
		NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()

		(text as NSString).draw(
			at: CGPoint(x: box.minX + padding, y: box.minY + padding / 2),
			withAttributes: attributes
		)
	}

	override func mouseDown(with event: NSEvent) {
		anchor = convert(event.locationInWindow, from: nil)
		selection = nil
		needsDisplay = true
	}

	override func mouseDragged(with event: NSEvent) {
		guard let anchor else {
			return
		}

		let point = convert(event.locationInWindow, from: nil)

		selection = CGRect(
			x: min(anchor.x, point.x),
			y: min(anchor.y, point.y),
			width: abs(point.x - anchor.x),
			height: abs(point.y - anchor.y)
		)
		.intersection(bounds)

		needsDisplay = true
	}

	override func mouseUp(with event: NSEvent) {
		defer {
			anchor = nil
		}

		guard
			let selection,
			selection.width >= Self.minimumSide,
			selection.height >= Self.minimumSide
		else {
			// Treat a stray click as "carry on selecting" rather than a cancel: cancelling on a mis-click would be infuriating.
			self.selection = nil
			needsDisplay = true
			return
		}

		onFinish?(selection.integral)
	}

	override func keyDown(with event: NSEvent) {
		guard event.keyCode == 53 else { // Escape
			super.keyDown(with: event)
			return
		}

		onFinish?(nil)
	}
}
