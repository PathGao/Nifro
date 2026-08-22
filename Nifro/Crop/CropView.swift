import AppKit

/**
Shows one rectangle of a page and nothing else.

Cropping has to happen in two places at once, and the second one is the one people miss. Clipping hides the rest of the page; shrinking the window is what actually frees the desktop underneath. A full-screen window showing a small crop still covers everything behind it and still swallows clicks in browsing mode. Upstream only ever documented the CSS half of this, which is why the people who followed that advice ended up with a shrunken page that kept blocking their desktop anyway (Plash#162).

The page still lays out at full viewport size — that is the point. Cropping is not zooming: the site must believe it has the whole screen, or its layout changes and the region you framed is no longer the region you get.
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
