import AppKit
import WebKit

/**
Puts a page in the wallpaper window, magnified to the part of it the user framed.

The page always lays out at the full size of the screen. The site has to believe it has the whole
screen, or its layout changes and the region the user framed is no longer the region they get.

Magnification is the web view's own rather than a transform on the finished picture. A transform
scales up pixels that were already drawn and the result is soft; `magnification` makes WebKit draw
the page again at that size, so text stays text.
*/
final class PageView: NSView {
	private let zoom: Zoom
	private let content: WKWebView

	init(content: WKWebView, zoom: Zoom, pageSize: CGSize) {
		self.content = content
		self.zoom = zoom

		super.init(frame: CGRect(origin: .zero, size: pageSize))

		clipsToBounds = true
		addSubview(content)
		layOutContent()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layout() {
		super.layout()
		layOutContent()
	}

	private func layOutContent() {
		// Worked out from the current bounds rather than from the size passed in at birth. The two are
		// the same until the view is resized, and then the stored copy is a layout for a display this
		// page is no longer on. Nothing was observed going wrong — a display change rebuilds this view
		// through `installContentView` before `layout()` gets a chance to run on the old numbers — but
		// a cached copy of a value the view is handed the live version of is a trap set for whoever
		// adds the next reason to resize.
		let pageSize = bounds.size
		let region = zoom.region(inPageOfSize: pageSize)
		let scale = zoom.magnification(inPageOfSize: pageSize)

		// Order matters. The frame is worked out in the magnified space, so the magnification has to
		// be the one it was worked out for before the frame is set.
		content.magnification = scale
		content.frame = region.contentFrame(pageSize: pageSize, scale: scale)
	}
}
