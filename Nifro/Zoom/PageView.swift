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
	private let pageSize: CGSize
	private let region: CGRect
	private let scale: Double
	private let content: WKWebView

	init(content: WKWebView, zoom: Zoom, pageSize: CGSize) {
		self.content = content
		self.pageSize = pageSize

		region = zoom.region(inPageOfSize: pageSize)
		scale = region.width > 0 ? pageSize.width / region.width : 1

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
		// Order matters. The frame is worked out in the magnified space, so the magnification has to
		// be the one it was worked out for before the frame is set.
		content.magnification = scale
		content.frame = region.contentFrame(pageSize: pageSize, scale: scale)
	}
}
