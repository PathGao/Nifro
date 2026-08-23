import AppKit

/**
Runs the "choose a region" mode. Takes over the wallpaper window, lets the user drag, turns what they drew into the website's zoom.

Selection always happens against the whole page. If the website is already zoomed, the zoom comes off for the duration. Otherwise you would be choosing a region of a region, and what came back would not match what was framed.
*/
extension AppState {
	var isSelectingCrop: Bool { cropSelectionView != nil }

	func beginCropSelection() {
		guard
			!isSelectingCrop,
			let website = WebsitesController.shared.current,
			// The website being cropped may live on a second display. Framing it on the primary one
			// would put the overlay on the wrong screen and record a rectangle measured against it.
			let scene = scenes.first(where: { $0.website?.id == website.id }) ?? scenes.first,
			let screen = scene.screen
		else {
			return
		}

		croppingSceneDisplay = scene.display

		cropSelectionPreviousZoom = website.zoom

		if website.zoom != nil {
			WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
				$0.zoom = nil
			}
		}

		// Put the live page back before the overlay goes on. The wallpaper may currently be a frozen
		// still or a shrunk region, and framing a rectangle against a stale picture would record a
		// region of something the page no longer shows.
		scene.content = .live(zoom: nil)

		// The window is normally click-through and behind everything. Neither helps while the user aims a rectangle at it.
		scene.window.isInteractive = true
		scene.window.level = .floating
		scene.window.alphaValue = 1
		SSApp.forceActivate()

		let view = CropSelectionView(frame: scene.window.contentLayoutRect)
		view.autoresizingMask = [.width, .height]
		view.onFinish = { [weak self] selection in
			self?.finishCropSelection(with: selection, on: screen)
		}

		cropSelectionView = view
		scene.window.contentView?.addSubview(view)
		scene.window.makeFirstResponder(view)
	}

	private func finishCropSelection(with selection: CGRect?, on screen: NSScreen) {
		let scene = scenes.first { $0.display == croppingSceneDisplay } ?? primaryScene
		croppingSceneDisplay = nil

		cropSelectionView?.removeFromSuperview()
		cropSelectionView = nil

		scene.window.level = .desktop
		scene.window.isInteractive = Defaults[.isBrowsingMode]
		for scene in scenes {
			scene.applyOpacity(animated: false)
		}

		guard
			let selection,
			let website = WebsitesController.shared.current
		else {
			// Cancelled: put back whatever zoom was there before.
			restoreZoomAfterCancelledSelection()
			return
		}

		// View coordinates → screen coordinates → page coordinates → a zoom, which is what survives
		// the website being shown on a display of a different size later.
		let inWindow = scene.window.contentView?.convert(selection, to: nil) ?? selection
		let onScreen = scene.window.convertToScreen(inWindow)
		let page = onScreen.pageFrame(inScreen: screen.pageFrame)

		WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
			$0.zoom = Zoom(region: page, inPageOfSize: screen.pageFrame.size)
		}

		cropSelectionPreviousZoom = nil
		applyRenderingMode()
	}

	private func restoreZoomAfterCancelledSelection() {
		guard
			let previous = cropSelectionPreviousZoom,
			let website = WebsitesController.shared.current
		else {
			applyRenderingMode()
			return
		}

		WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
			$0.zoom = previous
		}

		cropSelectionPreviousZoom = nil
		applyRenderingMode()
	}
}
