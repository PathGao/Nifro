import AppKit

/**
Drag a rectangle over the wallpaper to choose what fills it.

Asked for upstream and answered with a snippet of JavaScript instead (Plash#138). Typing numbers in works, but nobody knows where the part they want sits in page pixels.

The rectangle is locked to the shape of the screen. What is drawn becomes the whole wallpaper, so a
rectangle of any other shape could only be delivered by letterboxing it or by quietly showing more
than was framed. Refusing to draw the wrong shape is the honest version of both.
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

		let magnification = selection.width > 0 ? bounds.width / selection.width : 1
		drawLabel(String(format: "%.1f×", magnification), near: selection)
	}

	private func drawHint() {
		let text = String(localized: "Drag to choose the part of the page to fill the screen with.  Esc to cancel.")
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

		selection = rectangle(from: anchor, to: point)
		needsDisplay = true
	}

	/**
	The screen-shaped rectangle between the two points, kept inside the view.

	Grown to whichever of the two dimensions the pointer went further in, so the rectangle follows the
	drag rather than only its narrower half. Then shrunk, in proportion, by however much it overran
	the edge — clipping it to the edge instead would leave a rectangle that is no longer the shape of
	the screen.
	*/
	private func rectangle(from anchor: CGPoint, to point: CGPoint) -> CGRect {
		let aspectRatio = bounds.height > 0 ? bounds.width / bounds.height : 1

		var width = abs(point.x - anchor.x)
		var height = abs(point.y - anchor.y)

		if height > 0, width / height > aspectRatio {
			height = width / aspectRatio
		} else {
			width = height * aspectRatio
		}

		let room = CGSize(
			width: point.x < anchor.x ? anchor.x - bounds.minX : bounds.maxX - anchor.x,
			height: point.y < anchor.y ? anchor.y - bounds.minY : bounds.maxY - anchor.y
		)

		let fit = min(
			1,
			width > 0 ? room.width / width : 1,
			height > 0 ? room.height / height : 1
		)

		width *= fit
		height *= fit

		return CGRect(
			x: point.x < anchor.x ? anchor.x - width : anchor.x,
			y: point.y < anchor.y ? anchor.y - height : anchor.y,
			width: width,
			height: height
		)
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
			// A stray click means carry on selecting, not cancel. Losing the drag to a mis-click is worse than making the user press Escape.
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
