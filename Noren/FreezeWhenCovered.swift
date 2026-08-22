import AppKit

/**
Stops rendering the wallpaper while other windows cover it.

The web view keeps painting every frame no matter what is stacked on top of it, and for the kind of page people actually use as a wallpaper — a clock, a calendar, a dashboard — almost all of that work lands under a maximized window where nobody can see it.

Freezing swaps the web view out for a still of its last frame rather than blanking the window. Two reasons: the coverage check has a worst-case lag of one poll interval, and a wallpaper that vanishes for two seconds when you drag a window aside is worse than one that is briefly out of date. The still also means the unfreeze path never has to race a first paint.

Browsing mode never freezes — the user is looking at it.
*/
extension AppState {
	/**
	Whether the wallpaper should currently be showing a still instead of a live page.
	*/
	var shouldFreeze: Bool {
		Defaults[.freezeWhenCovered]
			&& isCovered
			&& isEnabled
			&& !isBrowsingMode
			&& WebsitesController.shared.current != nil
	}

	func applyFreezeState() {
		if shouldFreeze {
			freeze()
		} else {
			unfreeze()
		}
	}

	private func freeze() {
		let webView = webViewController.webView

		guard
			frozenView == nil,
			webView.window != nil
		else {
			return
		}

		// Suspending is not the same as muting. Muted video still decodes every frame.
		webView.setAllMediaPlaybackSuspended(true) {}

		webView.takeSnapshot(with: nil) { [weak self] image, _ in
			guard let self else {
				return
			}

			// The coverage state can flip while the snapshot is being taken.
			guard shouldFreeze, frozenView == nil else {
				return
			}

			installFrozenView(showing: image)
		}

		resetTimer()
	}

	private func installFrozenView(showing image: NSImage?) {
		let view = NSImageView(frame: desktopWindow.contentLayoutRect)
		view.imageScaling = .scaleAxesIndependently
		view.image = image
		view.autoresizingMask = [.width, .height]

		frozenView = view
		desktopWindow.contentView = view
	}

	private func unfreeze() {
		guard frozenView != nil else {
			return
		}

		frozenView = nil
		desktopWindow.contentView = webViewController.webView
		webViewController.webView.setAllMediaPlaybackSuspended(false) {}

		if isReloadPending {
			isReloadPending = false
			reloadWebsite()
		}

		resetTimer()
	}
}
