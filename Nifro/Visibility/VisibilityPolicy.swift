import AppKit
import WebKit

/**
Decides how much of the wallpaper is worth rendering right now.

The first version of this froze the whole wallpaper the moment other windows covered it. On a real desktop that turns out to be both too blunt and almost never correct, for one reason: **the wallpaper is hardly ever completely hidden.** The Dock is translucent and the menu bar samples what is behind it, so with a window maximized you still see the page moving along whichever edge the Dock lives on. That sliver is not an accident — it is one of the nicer things about running a live page as a wallpaper, and freezing it away to save power is a bad trade.

So the rule is not "visible or not", it is "how much, and where":

```
largest patch of wallpaper still on show
  ├─ most of the screen   → render normally
  ├─ a strip or a corner  → keep rendering, but only that strip
  └─ nothing at all       → freeze on the last frame
```

The middle case is the one that matters in practice. The web view keeps its full-screen layout — the page must still believe it has the whole screen or it reflows and the strip shows different content — and only the part on show gets painted. WebKit paints by tile against the exposed rectangle, so a window the width of the Dock paints a fraction of what a full-screen one does.
*/
extension WallpaperScene {
	/**
	How much of the screen has to stay on show before rendering the whole thing is worth it.

	Above this, shrinking the window would save little and risk a visible gap when the user reveals the desktop again.
	*/
	private static let fullRenderFraction = 0.6

	/**
	How big a patch has to be, in square points, to be worth rendering at all — roughly 200×200pt.
	*/
	private static let minimumMeaningfulPatchArea = 40_000.0

	var isVisibilityManagementEnabled: Bool {
		Defaults[.freezeWhenCovered]
			&& AppState.shared.isEnabled
			&& !AppState.shared.isBrowsingMode
			&& website != nil
			// A website with its own crop already decides what is shown and how big the window is. Two things moving the same window would fight.
			&& website?.crop == nil
	}

	func applyVisibilityState() {
		guard
			isVisibilityManagementEnabled,
			let screen
		else {
			restoreFullRendering()
			return
		}

		let screenArea = screen.frame.width * screen.frame.height

		guard screenArea > 0 else {
			return
		}

		let visible = occlusionMonitor.largestVisibleRegion

		if visible.area >= screenArea * Self.fullRenderFraction {
			restoreFullRendering()
			return
		}

		if visible.area >= Self.minimumMeaningfulPatchArea {
			renderOnly(visible.rect, on: screen)
			return
		}

		freeze()
	}

	// MARK: - The three states

	private func restoreFullRendering() {
		guard frozenView != nil || renderedRegion != nil else {
			return
		}

		frozenView = nil
		renderedRegion = nil
		window.cropRect = nil
		installContentView()

		// Belt and braces: the launch-time hide is cleared on a timer, and this path can run before that timer fires.
		if webViewController.webView.url != nil {
			webViewController.webView.isHidden = false
		}
		webViewController.webView.setAllMediaPlaybackSuspended(false) {}
		settlePendingReload()
	}

	private func renderOnly(_ region: CGRect, on screen: NSScreen) {
		// Snapping to whole points keeps a one-pixel jitter in the coverage grid from rebuilding the view every poll.
		let snapped = region.integral

		guard snapped != renderedRegion else {
			return
		}

		renderedRegion = snapped
		frozenView = nil

		let pageRegion = snapped.pageFrame(inScreen: screen.frame)

		window.cropRect = pageRegion
		window.contentView = CropView(
			content: webViewController.webView,
			crop: pageRegion,
			pageSize: screen.frame.size
		)

		// Still playing, still animating — just in a smaller window.
		webViewController.webView.setAllMediaPlaybackSuspended(false) {}
		settlePendingReload()
	}

	private func freeze() {
		guard frozenView == nil else {
			return
		}

		let webView = webViewController.webView

		guard
			webView.window != nil,
			// Before the first load there is nothing to hold on to; a still taken now is a blank one, and installing it takes the web view out of the window in the middle of its first load.
			webView.url != nil
		else {
			return
		}

		// Suspending is not the same as muting. Muted video still decodes every frame.
		webView.setAllMediaPlaybackSuspended(true) {}

		webView.takeSnapshot(with: nil) { [weak self] image, _ in
			guard
				let self,
				isVisibilityManagementEnabled,
				occlusionMonitor.largestVisibleRegion.area < Self.minimumMeaningfulPatchArea,
				frozenView == nil
			else {
				return
			}

			// Installed even when the snapshot came back empty. Nothing of the wallpaper is on show, so there is nothing to look wrong — and not installing it would leave the web view in the window painting frames nobody sees, which is the whole thing we are trying to avoid.
			installFrozenView(showing: image)
		}

		resetTimer()
	}

	private func installFrozenView(showing image: NSImage?) {
		let view = NSImageView(frame: window.contentLayoutRect)
		view.imageScaling = .scaleAxesIndependently
		view.image = image
		view.autoresizingMask = [.width, .height]

		renderedRegion = nil
		frozenView = view
		window.cropRect = nil
		window.contentView = view
	}

	private func settlePendingReload() {
		guard isReloadPending else {
			resetTimer()
			return
		}

		isReloadPending = false
		reload()
	}
}
