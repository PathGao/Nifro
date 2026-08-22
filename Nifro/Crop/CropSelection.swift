import AppKit

/**
Runs the "choose a region" mode. Takes over the wallpaper window, lets the user drag, turns what they drew into the website's crop.

Selection always happens against the whole page. If the website is already cropped, the crop comes off for the duration. Otherwise you would be choosing a region of a region, and the numbers coming back would not match the numbers you set.
*/
extension AppState {
	var isSelectingCrop: Bool { cropSelectionView != nil }

	func beginCropSelection() {
		guard
			!isSelectingCrop,
			let website = WebsitesController.shared.current,
			let screen = desktopWindow.targetDisplay?.screen ?? .main
		else {
			return
		}

		cropSelectionPreviousCrop = website.crop

		if website.crop != nil {
			WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
				$0.crop = nil
			}
		}

		// Put the live page back before the overlay goes on. The wallpaper may currently be a frozen
		// still or a shrunk region, and framing a rectangle against a stale picture would record a
		// crop of something the page no longer shows.
		primaryScene.content = .live(crop: nil)

		// The window is normally click-through and behind everything. Neither helps while the user aims a rectangle at it.
		desktopWindow.isInteractive = true
		desktopWindow.level = .floating
		desktopWindow.alphaValue = 1
		SSApp.forceActivate()

		let view = CropSelectionView(frame: desktopWindow.contentLayoutRect)
		view.autoresizingMask = [.width, .height]
		view.onFinish = { [weak self] selection in
			self?.finishCropSelection(with: selection, on: screen)
		}

		cropSelectionView = view
		desktopWindow.contentView?.addSubview(view)
		desktopWindow.makeFirstResponder(view)
	}

	private func finishCropSelection(with selection: CGRect?, on screen: NSScreen) {
		cropSelectionView?.removeFromSuperview()
		cropSelectionView = nil

		desktopWindow.level = .desktop
		desktopWindow.isInteractive = Defaults[.isBrowsingMode]
		for scene in scenes {
			scene.applyOpacity(animated: false)
		}

		guard
			let selection,
			let website = WebsitesController.shared.current
		else {
			// Cancelled: put back whatever crop was there before.
			restoreCropAfterCancelledSelection()
			return
		}

		// View coordinates → screen coordinates → page coordinates.
		let inWindow = desktopWindow.contentView?.convert(selection, to: nil) ?? selection
		let onScreen = desktopWindow.convertToScreen(inWindow)
		let page = onScreen.pageFrame(inScreen: screen.pageFrame).integral

		WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
			$0.crop = page
		}

		cropSelectionPreviousCrop = nil
		installContentView()
	}

	private func restoreCropAfterCancelledSelection() {
		guard
			let previous = cropSelectionPreviousCrop,
			let website = WebsitesController.shared.current
		else {
			installContentView()
			return
		}

		WebsitesController.shared.all = WebsitesController.shared.all.modifying(elementWithID: website.id) {
			$0.crop = previous
		}

		cropSelectionPreviousCrop = nil
		installContentView()
	}
}
