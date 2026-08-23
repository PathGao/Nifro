import AppKit

/**
Move the wallpaper to choose what fills it.

A region is stored as a centre and a magnification. It used to be *chosen* as a rectangle dragged
over the page, and converting one shape into the other is where three problems came from: you were
drawing on the thing you were framing rather than looking at the result, a rectangle drawn slightly
wrong meant starting over, and what somebody drew and what they got did not agree to the pixel.

Moving the page is the stored model rather than a conversion of it. Drag moves the centre, scroll or
pinch changes the magnification, and there is nothing to convert at the end. Apple's own
aspect-locked crops work this way — Photos, the iOS photo crop, every avatar picker: the frame stays
still and the content moves underneath. Here the frame is the screen, so it could not move anyway.

The overlay is transparent. Dimming the page would hide the one thing this mode exists to show.
*/
final class CropSelectionView: NSView {
	/**
	Called on every change, so the wallpaper behind can show it.
	*/
	var onChange: ((Zoom) -> Void)?

	/**
	Called with the region to keep, or `nil` if the user backed out.
	*/
	var onFinish: ((Zoom?) -> Void)?

	private var zoom: Zoom {
		didSet {
			onChange?(zoom)
			needsDisplay = true
		}
	}

	/**
	How far one arrow key press moves the region, in view points.
	*/
	private static let keyboardStep = 40.0

	/**
	How much one key press changes the magnification.
	*/
	private static let keyboardZoomStep = 1.1

	/**
	A wheel notch is a bigger, coarser thing than a trackpad's continuous scroll, so it maps to a step
	rather than to a distance.
	*/
	private static let wheelZoomPerLine = 1.06

	init(frame: CGRect, zoom: Zoom) {
		self.zoom = zoom
		super.init(frame: frame)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	override var acceptsFirstResponder: Bool { true }

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	private var pageSize: CGSize { bounds.size }

	// MARK: - Gestures

	override func mouseDragged(with event: NSEvent) {
		zoom = zoom.panned(
			byViewDelta: CGSize(width: event.deltaX, height: -event.deltaY),
			inPageOfSize: pageSize
		)
	}

	/**
	Two-finger scroll on a trackpad moves the page; a wheel changes the magnification.

	`hasPreciseScrollingDeltas` is what tells the two apart. A trackpad has a pinch for magnifying and
	nothing else for panning, so scrolling has to pan. A wheel mouse has no pinch at all, and dragging
	already pans, so the wheel is the only way it can reach the magnification.
	*/
	override func scrollWheel(with event: NSEvent) {
		guard event.hasPreciseScrollingDeltas else {
			let steps = event.scrollingDeltaY
			zoom = zoom.magnified(
				by: pow(Self.wheelZoomPerLine, steps),
				around: convert(event.locationInWindow, from: nil),
				inPageOfSize: pageSize
			)
			return
		}

		zoom = zoom.panned(
			byViewDelta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
			inPageOfSize: pageSize
		)
	}

	/**
	Pinch.

	Swallowed here on purpose: the web view has `allowsMagnification` on, so a pinch that reached the
	page would zoom the page instead of the frame — and the page's own magnification is not something
	this mode records or can put back.
	*/
	override func magnify(with event: NSEvent) {
		zoom = zoom.magnified(
			by: 1 + event.magnification,
			around: convert(event.locationInWindow, from: nil),
			inPageOfSize: pageSize
		)
	}

	override func keyDown(with event: NSEvent) {
		let pointer = CGPoint(x: bounds.midX, y: bounds.midY)

		switch event.keyCode {
		case 53: // Escape
			onFinish?(nil)
		case 36, 76: // Return, Enter
			onFinish?(zoom)
		case 123: // Left
			pan(x: Self.keyboardStep)
		case 124: // Right
			pan(x: -Self.keyboardStep)
		case 125: // Down
			pan(y: -Self.keyboardStep)
		case 126: // Up
			pan(y: Self.keyboardStep)
		default:
			switch event.charactersIgnoringModifiers {
			case "+", "=":
				zoom = zoom.magnified(by: Self.keyboardZoomStep, around: pointer, inPageOfSize: pageSize)
			case "-", "_":
				zoom = zoom.magnified(by: 1 / Self.keyboardZoomStep, around: pointer, inPageOfSize: pageSize)
			default:
				super.keyDown(with: event)
			}
		}
	}

	private func pan(x: Double = 0, y: Double = 0) {
		zoom = zoom.panned(byViewDelta: CGSize(width: x, height: y), inPageOfSize: pageSize)
	}

	// MARK: - The panel

	override func draw(_ dirtyRect: CGRect) {
		let magnification = String(format: "%.1f×", max(zoom.scale, 1))
		let hint = String(localized: "Drag or scroll to move · pinch to zoom · Return to keep · Esc to cancel")

		let numberAttributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
			.foregroundColor: NSColor.white
		]
		let hintAttributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 12, weight: .regular),
			.foregroundColor: NSColor.white.withAlphaComponent(0.75)
		]

		let numberSize = (magnification as NSString).size(withAttributes: numberAttributes)
		let hintSize = (hint as NSString).size(withAttributes: hintAttributes)
		let padding = 16.0
		let gap = 6.0

		let box = CGRect(
			x: bounds.midX - (max(numberSize.width, hintSize.width) / 2 + padding),
			y: bounds.minY + 64,
			width: max(numberSize.width, hintSize.width) + padding * 2,
			height: numberSize.height + hintSize.height + gap + padding * 2
		)

		NSColor.black.withAlphaComponent(0.72).setFill()
		NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()

		(hint as NSString).draw(
			at: CGPoint(x: box.midX - hintSize.width / 2, y: box.minY + padding),
			withAttributes: hintAttributes
		)
		(magnification as NSString).draw(
			at: CGPoint(x: box.midX - numberSize.width / 2, y: box.minY + padding + hintSize.height + gap),
			withAttributes: numberAttributes
		)
	}
}
