import AppKit
import WebKit

/**
Puts a page in the wallpaper window, showing the part of it that should be showing.

Two separate things want to narrow what is on screen, and they narrow it for different reasons:

```
zoom   the user framed a part of the page and wants it filling the screen
       → magnify that region, window stays the size of the screen

clip   other windows cover everything but a strip, so only the strip is worth painting
       → cut the picture down to the strip, window shrinks to it
```

Either can be absent and both can apply at once, which is why they are one view rather than two
nested ones. A zoomed page whose wallpaper is down to the strip behind the Dock still has to show the
zoomed picture in that strip, not the unzoomed one.

The page always lays out at the full size of the screen. The site has to believe it has the whole
screen, or its layout changes and the region the user framed is no longer the region they get.

Magnification is the web view's own rather than a transform on the finished picture. A transform
scales up pixels that were already drawn and the result is soft; `magnification` makes WebKit draw
the page again at that size, so text stays text.
*/
final class PageView: NSView {
	private let pageSize: CGSize
	private let clip: CGRect?
	private let region: CGRect
	private let scale: Double
	private let content: WKWebView

	init(content: WKWebView, zoom: Zoom?, clip: CGRect?, pageSize: CGSize) {
		self.content = content
		self.pageSize = pageSize
		self.clip = clip

		region = (zoom ?? .identity).region(inPageOfSize: pageSize)
		scale = region.width > 0 ? pageSize.width / region.width : 1

		super.init(frame: CGRect(origin: .zero, size: clip?.size ?? pageSize))

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

		var frame = region.contentFrame(pageSize: pageSize, scale: scale)

		if let clip {
			frame.origin.x -= clip.minX
			frame.origin.y -= pageSize.height - clip.maxY
		}

		content.frame = frame
	}
}
