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

	/**
	Frame a region on `scene`, or on the one the pointer is over when none is named.

	The scene is passed rather than looked up. It used to find one by matching the list-wide current
	website, which on two displays meant framing whichever screen last held the mark — the overlay
	would appear on a page the user was not looking at.

	`hasLoadedItsWebsite` is the same mistake one layer down, and the guard is here rather than on the
	panel's Crop button because the button is one of three ways in — the keyboard shortcut and
	`Action.chooseRegion` are the others, and neither of them can see a disabled button.
	`WallpaperScene.toggleSound` is the other control that writes what the user chose against a website
	and guards itself for the same reason. The region is
	dragged out over whatever the web view is showing and stored on `scene.website`, so those two have
	to be the same website or the user frames one page and adjusts another. Refusing is the whole
	response: there is nothing to say, the state clears itself the moment a load succeeds, and the
	panel already draws the failure that caused it.
	*/
	func beginCropSelection(on scene: WallpaperScene? = nil) {
		guard
			!isSelectingCrop,
			let scene = scene ?? actingScene,
			let website = scene.website,
			scene.hasLoadedItsWebsite,
			scene.screen != nil
		else {
			return
		}

		croppingScene = scene
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

		// The window is normally click-through and behind everything. Neither helps while the user aims a
		// rectangle at it. Said as its own mode rather than by borrowing Browsing Mode's flag, because
		// everything that writes that flag goes on writing it while the mode is up — see
		// `DesktopWindow.isFramingRegion`.
		scene.window.isFramingRegion = true
		scene.window.alphaValue = 1
		SSApp.forceActivate()

		let view = CropSelectionView(frame: scene.window.contentLayoutRect, zoom: starting)
		view.autoresizingMask = [.width, .height]
		view.onFinish = { [weak self] zoom in
			self?.finishCropSelection(with: zoom)
		}

		cropSelectionView = view

		// The view claims the keyboard itself, on every move into a window rather than once here — the
		// page under it goes on loading and reloading, and each of those replaces the window's content
		// view out from under the overlay.
		scene.window.contentView?.addSubview(view)
	}

	private func finishCropSelection(with zoom: Zoom?) {
		// Optional and not substituted for: a scene that went away with its display has taken its window
		// with it, so there is nothing to put back and nothing else that should be put back in its place.
		let croppedScene = croppingScene
		croppingScene = nil

		cropSelectionView?.removeFromSuperview()
		cropSelectionView = nil

		// The level and the click-through follow from these two, so neither is set here. Browsing Mode
		// is read again rather than remembered: it is reachable while the overlay is up.
		croppedScene?.window.isFramingRegion = false
		croppedScene?.window.isInteractive = isBrowsingMode(on: croppedScene?.display)

		// The framed scene only. Framing forced this one window to full strength and set this one
		// window's content to the unmagnified page; no other display was touched on the way in, so no
		// other display has anything to put back. Undoing on every scene is how framing one display
		// reached the others.
		croppedScene?.applyOpacity(animated: false)

		let websiteID = croppingWebsiteID
		croppingWebsiteID = nil

		guard
			let zoom,
			let websiteID,
			let website = WebsitesController.shared.all[id: websiteID]
		else {
			// Cancelled, interrupted by something that took the overlay out of the window, or the
			// website went away while the overlay was up. The stored region was never touched, so
			// putting the page back is the whole of undoing this.
			croppedScene?.installContentView()
			return
		}

		// Straight through, because the thing being adjusted is the thing being stored. The rectangle
		// this used to convert from is where the region came back a point out from where it was drawn.
		WebsitesController.shared.update(website.id) {
			$0.zoom = zoom.scale > 1 ? zoom : nil
		}

		croppedScene?.installContentView()
	}
}
