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
	Called once with the region to keep, or `nil` if the mode ended without one — the user backed out,
	or this view was taken out of the window and the mode went with it. Cleared as it is called, so
	there is exactly one ending however the mode reaches it.
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

	/**
	Take the keyboard, every time this view is put into a window rather than once when it is installed
	— and end the mode when it is taken out of one for good.

	This sits inside the wallpaper window's content view, and that slot is rewritten by every load,
	every reload and every edit to the website list — `installContentView` runs from all of them, and
	the page under the frame goes on loading for the whole time the mode is up. Rewriting it pulls this
	view out of the window and puts it back, and AppKit hands the keyboard back to the window when the
	first responder leaves the view hierarchy. Drawing and dragging survived that, because neither
	needs the keyboard, which is why the frame went on moving under the mouse while Return and Escape
	did nothing.

	The rewrites that do not put it back are the other half, and they are the reason this mode could be
	entered and never left. `installContentView` refuses to touch the slot while a region is being
	framed, but it is not the only writer: `releaseWebView` builds a fresh web view and installs it —
	which every screen lock, every battery transition, every Disable and every display switched off
	reaches through `suspend()` — and `tearDown` empties the slot when the framed display is unplugged.
	Neither can leave this view where it was, and this view is the only thing that can call `onFinish`,
	so what was left behind was a window still at `.floating` and full opacity with `isSelectingCrop`
	still true: a wallpaper pinned above every other window, framing refused for the rest of the
	session, and nothing but quitting to get out of it.

	Ending here rather than guarding there is the difference between the two. A guard is a thing the
	next writer of that slot has to remember, and this is the third time that list has been found one
	short. Leaving the window is not a route, it is every route — including the ones nothing has
	written yet — and it is the same fact the mode is already defined by: `isSelectingCrop` *is* this
	view existing.

	On the next turn of the run loop rather than now, because this runs *inside* the assignment to
	`window.contentView`, and finishing installs a content view of its own — reassigning the slot that
	is mid-assignment. The window is read again after the hop, so a view taken out and put straight
	back in one turn keeps its mode, which is what `installContentView` used to do before it learned to
	refuse.
	*/
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		guard let window else {
			Task { @MainActor [weak self] in
				guard
					let self,
					self.window == nil
				else {
					return
				}

				finish(with: nil)
			}

			return
		}

		window.makeFirstResponder(self)
	}

	/**
	Report the outcome, once.

	`onFinish` takes this view out of the window, which comes straight back through
	`viewDidMoveToWindow` as a second ending — and a second ending arrives after the scene has already
	been put back, so it would either frame a region against a restored window or undo a region that
	had just been stored. Cleared before the call rather than after, so the re-entry finds nothing left
	to do. Return pressed twice on a slow frame is the same shape and is covered by the same line.
	*/
	private func finish(with zoom: Zoom?) {
		guard let onFinish else {
			return
		}

		self.onFinish = nil
		onFinish(zoom)
	}

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
			finish(with: nil)
		case 36, 76: // Return, Enter
			finish(with: zoom)
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
