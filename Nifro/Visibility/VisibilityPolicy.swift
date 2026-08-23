import AppKit
import WebKit

/**
Decides how much of the wallpaper is worth rendering right now.

The first version froze the whole wallpaper the moment other windows covered it. That is wrong on a real desktop, because the wallpaper is hardly ever completely hidden. The Dock is translucent and the menu bar samples what is behind it, so with a window maximized you still see the page moving along whichever edge the Dock lives on. Freezing that sliver away to save power is a bad trade.

So the question is how much is on show, and where:

```
largest patch of wallpaper still on show
  ├─ most of the screen   → render normally
  ├─ a strip or a corner  → keep rendering, but only that strip
  └─ nothing at all       → freeze on the last frame
```

The middle case is the one that matters in practice. The web view keeps the layout it has uncropped, since the page has to believe it still has the whole window or it reflows and the strip shows different content. Only the part on show gets painted. WebKit paints by tile against the exposed rectangle, so a window the width of the Dock paints a fraction of what a full-screen one does.
*/
extension WallpaperScene {
	/**
	How much of the screen has to stay on show before rendering the whole thing is worth it.

	Above this, shrinking the window would save little and risk a visible gap when the user reveals the desktop again.
	*/
	private static let fullRenderFraction = 0.6

		func applyVisibilityState() {
		guard
			renderingMode == .managed,
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

		if visible.area >= minimumMeaningfulPatchArea {
			renderOnly(visible.rect, on: screen)
			return
		}

		freeze()
	}

	// MARK: - The three states

	private func restoreFullRendering() {
		switch content {
		case .reduced, .frozen:
			break
		default:
			return
		}

		installContentView()

		// The launch-time hide is cleared on a timer, and this path can run before that timer fires.
		if webViewController.webView.url != nil {
			webViewController.webView.isHidden = false
		}
		webViewController.webView.setAllMediaPlaybackSuspended(false) {}
		settlePendingReload()
	}

	private func renderOnly(_ region: CGRect, on screen: NSScreen) {
		// Snapping to whole points keeps a one-pixel jitter in the coverage grid from rebuilding the view every poll.
		let pageRegion = region.integral.pageFrame(inScreen: screen.pageFrame)

		if case .reduced(let current) = content, current == pageRegion {
			return
		}

		content = .reduced(to: pageRegion)

		// Still playing, still animating, just in a smaller window.
		webViewController.webView.setAllMediaPlaybackSuspended(false) {}
		settlePendingReload()
	}

	private func freeze() {
		guard !isFrozen else {
			return
		}

		let webView = webViewController.webView

		guard
			webView.window != nil,
			// Before the first load there is nothing to hold on to. A still taken now would be blank, and installing it would pull the web view out of the window mid-load.
			webView.url != nil
		else {
			return
		}

		// Suspending is not the same as muting. Muted video still decodes every frame.
		webView.setAllMediaPlaybackSuspended(true) {}

		webView.takeSnapshot(with: nil) { [weak self] image, _ in
			guard
				let self,
				renderingMode == .managed,
				occlusionMonitor.largestVisibleRegion.area < minimumMeaningfulPatchArea,
				!isFrozen
			else {
				return
			}

			// Held even when the snapshot came back empty. Nothing of the wallpaper is on show, so nothing can look wrong. Skipping it would leave the web view in the window painting frames nobody sees, which is what this avoids.
			content = .frozen(image)
		}

		resetTimer()
	}

	private func settlePendingReload() {
		guard
			isReloadPending,
			// Not while the user is on the page. A reload that came due while the wallpaper was frozen
			// has waited this long; it can wait until they are finished, rather than pulling the page
			// out from under someone who just asked to interact with it.
			!AppState.shared.isBrowsingMode
		else {
			resetTimer()
			return
		}

		isReloadPending = false
		reload()
	}
}
