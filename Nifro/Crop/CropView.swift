import AppKit

/**
Shows one rectangle of a page and nothing else.

Cropping takes two steps. Clipping hides the rest of the page. Shrinking the window is what frees the desktop underneath. A full-screen window showing a small crop still covers everything behind it and still swallows clicks in browsing mode. Upstream documented only the CSS half, so people who followed that advice got a shrunken page that kept blocking their desktop (Plash#162).

The page still lays out at full viewport size. The site has to believe it has the whole screen, or its layout changes and the region you framed is no longer the region you get.
*/
final class CropView: NSView {
	/**
	The region of the page to show, in page coordinates with the origin at the top-left.
	*/
	private let crop: CGRect

	/**
	The size the page lays out at, normally the whole screen.
	*/
	private let pageSize: CGSize

	private let content: NSView

	init(content: NSView, crop: CGRect, pageSize: CGSize) {
		self.content = content
		self.crop = crop
		self.pageSize = pageSize

		super.init(frame: CGRect(origin: .zero, size: crop.size))

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
		content.frame = crop.contentFrame(pageSize: pageSize)
	}
}
