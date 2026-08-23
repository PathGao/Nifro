import AppKit

/**
Runs the "choose a region" mode. Takes over the wallpaper window and lets the user move the page
around until it shows what they want, which is the region.

It starts from the region the website already has rather than from the whole page, so this adjusts as
well as creates. That was not possible while a region was chosen by drawing a rectangle: framing a
rectangle inside an already-framed region would have been framing a region of a region.
*/
extension AppState {
	var isSelectingCrop: Bool { cropSelectionView != nil }

	func beginCropSelection() {
		guard
			!isSelectingCrop,
			let website = currentWebsite,
			// The website being adjusted may live on a second display. Putting the overlay on the primary
			// one would move a region on a page the user is not looking at.
			let scene = scenes.first(where: { $0.website?.id == website.id }) ?? scenes.first,
			scene.screen != nil
		else {
			return
		}

		croppingSceneDisplay = scene.display
		croppingWebsiteID = website.id

		// The stored region is left alone for the whole of this. Writing to it, which is what this used
		// to do, destroyed the region the moment framing began; Escape put it back from a copy held in
		// memory, and quitting or crashing in between did not. What the wallpaper shows while the mode
		// is up is set directly on the scene instead, which is where a preview belongs.
		// The whole page, unmoved, for the whole of this. The frame is drawn on top of it: a still page
		// and a moving frame has one interpretation, where a moving page has two — its own movement and
		// ours — and pages that pan and zoom themselves are exactly the ones worth framing.
		let starting = website.zoom ?? Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 1)
		scene.content = .live(zoom: nil)

		// The window is normally click-through and behind everything. Neither helps while the user aims a rectangle at it.
		scene.window.isInteractive = true
		scene.window.level = .floating
		scene.window.alphaValue = 1
		SSApp.forceActivate()

		let view = CropSelectionView(frame: scene.window.contentLayoutRect, zoom: starting)
		view.autoresizingMask = [.width, .height]
		view.onFinish = { [weak self] zoom in
			self?.finishCropSelection(with: zoom)
		}

		cropSelectionView = view
		scene.window.contentView?.addSubview(view)
		scene.window.makeFirstResponder(view)
	}

	private func finishCropSelection(with zoom: Zoom?) {
		let croppedScene = scenes.first { $0.display == croppingSceneDisplay } ?? primaryScene
		croppingSceneDisplay = nil

		cropSelectionView?.removeFromSuperview()
		cropSelectionView = nil

		croppedScene.window.level = .desktop
		croppedScene.window.isInteractive = Defaults[.isBrowsingMode]

		for scene in scenes {
			scene.applyOpacity(animated: false)
		}

		let websiteID = croppingWebsiteID
		croppingWebsiteID = nil

		guard
			let zoom,
			let websiteID,
			let website = WebsitesController.shared.all[id: websiteID]
		else {
			// Cancelled, or the website went away while the overlay was up. The stored region was never
			// touched, so putting the page back is the whole of undoing this.
			installContentView()
			return
		}

		// Straight through, because the thing being adjusted is the thing being stored. The rectangle
		// this used to convert from is where the region came back a point out from where it was drawn.
		WebsitesController.shared.update(website.id) {
			$0.zoom = zoom.scale > 1 ? zoom : nil
		}

		installContentView()
	}
}
