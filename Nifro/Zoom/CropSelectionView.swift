import AppKit

/**
Move and resize a frame over the page to choose what fills the wallpaper.

**The page does not move.** That was tried the other way round — the wallpaper panned and zoomed
under a fixed frame, the way Photos' crop works — and it is wrong here for a reason that does not
apply to a photograph: a web page can pan and zoom itself. On floor796 or a map, a moving picture is
ambiguous. You cannot tell whether the page moved or the frame did, and the page's own magnification
multiplies with the frame's, so the same gesture appears to do two different amounts of the same
thing. A still page and a moving frame has exactly one interpretation.

What the mode reads from and writes to is still the stored value itself — a centre and a
magnification — rather than a rectangle converted at the end. The frame drawn here *is*
`zoom.region(inPageOfSize:)`, so what is on screen and what will be saved cannot drift apart, which
is the part of the earlier attempt worth keeping. It also starts from the region the website already
has, so adjusting one is the same gesture as making one.
*/
final class CropSelectionView: NSView {
	/**
	Called with the region to keep, or `nil` if the user backed out.
	*/
	var onFinish: ((Zoom?) -> Void)?

	private var zoom: Zoom {
		didSet {
			needsDisplay = true
		}
	}

	/**
	How far one arrow key press moves the region, in view points.
	*/
	private static let keyboardStep = 40.0

	/**
	How much one key press grows the frame. `+` bigger, `-` smaller, like everything else here.
	*/
	private static let keyboardGrowthStep = 1.1

	/**
	A wheel notch is a bigger, coarser thing than a trackpad's continuous scroll, so it maps to a step
	rather than to a distance.
	*/
	private static let wheelGrowthPerLine = 1.06

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
		move(x: event.deltaX, y: -event.deltaY)
	}

	/**
	Two-finger scroll on a trackpad moves the frame; a wheel resizes it.

	`hasPreciseScrollingDeltas` is what tells the two apart. A trackpad has a pinch for resizing and
	nothing else for moving, so scrolling has to move. A wheel mouse has no pinch at all, and dragging
	already moves, so the wheel is the only way it can reach the size.
	*/
	override func scrollWheel(with event: NSEvent) {
		guard event.hasPreciseScrollingDeltas else {
			zoom = zoom.resizedFrame(byGrowing: pow(Self.wheelGrowthPerLine, event.scrollingDeltaY))
			return
		}

		move(x: -event.scrollingDeltaX, y: -event.scrollingDeltaY)
	}

	/**
	Pinch resizes the frame.

	Swallowed here on purpose. The web view has `allowsMagnification` on, and the page may have its
	own zoom besides — a pinch that reached either would change the thing being framed while it is
	being framed, and neither is something this mode records or can put back.
	*/
	override func magnify(with event: NSEvent) {
		// `magnification` is positive when the fingers spread, and spreading makes the thing under
		// them bigger. The frame is the thing under them.
		zoom = zoom.resizedFrame(byGrowing: 1 + event.magnification)
	}

	override func keyDown(with event: NSEvent) {
		switch event.keyCode {
		case 53: // Escape
			onFinish?(nil)
		case 36, 76: // Return, Enter
			onFinish?(zoom)
		case 123: // Left
			move(x: -Self.keyboardStep)
		case 124: // Right
			move(x: Self.keyboardStep)
		case 125: // Down
			move(y: -Self.keyboardStep)
		case 126: // Up
			move(y: Self.keyboardStep)
		default:
			switch event.charactersIgnoringModifiers {
			case "+", "=":
				zoom = zoom.resizedFrame(byGrowing: Self.keyboardGrowthStep)
			case "-", "_":
				zoom = zoom.resizedFrame(byGrowing: 1 / Self.keyboardGrowthStep)
			default:
				super.keyDown(with: event)
			}
		}
	}

	private func move(x: Double = 0, y: Double = 0) {
		zoom = zoom.movedFrame(byViewDelta: CGSize(width: x, height: y), inPageOfSize: pageSize)
	}

	// MARK: - Drawing

	/**
	Where the region sits in this view.

	Page coordinates run down from the top and view coordinates run up from the bottom, which is the
	whole of the conversion — the view is the size of the page area, so nothing is scaled.
	*/
	private func frame(inView bounds: CGRect) -> CGRect {
		let region = zoom.region(inPageOfSize: bounds.size)

		return CGRect(
			x: region.minX,
			y: bounds.height - region.maxY,
			width: region.width,
			height: region.height
		)
	}

	override func draw(_ dirtyRect: CGRect) {
		let frame = frame(inView: bounds)

		// Dimmed outside, untouched inside. What is being framed has to be visible at full strength;
		// what is being thrown away should look thrown away.
		NSColor.black.withAlphaComponent(0.5).setFill()
		dirtyRect.fill()
		NSColor.clear.set()
		frame.fill(using: .copy)

		NSColor.white.setStroke()
		let outline = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
		outline.lineWidth = 1
		outline.stroke()

		drawPanel()
	}

	private func drawPanel() {
		let magnification = String(format: "%.1f×", max(zoom.scale, 1))
		let hint = String(localized: "Drag or scroll to move the frame · pinch to resize · Return to keep · Esc to cancel")

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
