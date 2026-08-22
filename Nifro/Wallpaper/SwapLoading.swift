import AppKit
import WebKit

/**
Loads the next page out of sight and only shows it once it has arrived.

Loading in place has three failure modes that upstream tracked as five separate issues, all of them the same mechanism:

- the wallpaper goes white while the new page is on its way (Plash#21)
- a load that fails leaves the desktop showing nothing, most visibly when the Mac wakes before the network does (Plash#41, Plash#11)
- switching between images cuts rather than fades (Plash#47, Plash#9)

Loading into a second web view fixes all three at once. The current page stays up, untouched, until the replacement has finished. A failure then changes nothing on screen. The old page stays, and the error goes to the menu bar tooltip instead of the desktop.

Scoped to replacing a page. The first load of the session still goes straight into the window, because there is nothing to protect yet and no reason to put the one path that has to work behind new machinery.
*/
extension WallpaperScene {
	/**
	How long to let a replacement load before giving up on it and keeping what is already on screen.
	*/
	private static let swapTimeout = Duration.seconds(30)

	/**
	Load `url`, keeping the current page visible until the new one is ready.

	Falls back to loading in place when there is nothing on screen worth protecting.
	*/
	func loadBySwapping(_ url: URL?) {
		guard
			let url,
			webViewController.webView.url != nil,
			!isFrozen
		else {
			load(url)
			return
		}

		pendingLoad?.cancel()

		pendingLoad = Task { [weak self] in
			guard let self else {
				return
			}

			let replacement = webViewController.makeReplacementWebView()

			defer {
				if pendingWebView === replacement {
					pendingWebView = nil
				}
			}

			pendingWebView = replacement

			do {
				try await replacement.loadAndWait(url, timeout: Self.swapTimeout)
			} catch {
				// The page on screen is still the last one that worked. Leaving it there is the whole point, so the error goes to the tooltip rather than the desktop.
				guard !Task.isCancelled else {
					return
				}

				AppState.shared.webViewError = error
				return
			}

			guard !Task.isCancelled else {
				return
			}

			AppState.shared.webViewError = nil
			adopt(replacement)
		}
	}

	/**
	Put the finished replacement on screen, fading it in over the page it replaces.
	*/
	private func adopt(_ replacement: SSWebView) {
		replacement.isHidden = false
		webViewController.adopt(replacement)
		installContentView()

		guard let contentView = window.contentView else {
			return
		}

		contentView.alphaValue = 0

		NSAnimationContext.runAnimationGroup {
			$0.duration = 0.35
			$0.allowsImplicitAnimation = true
			contentView.animator().alphaValue = 1
		}

		restoreScrollPosition(in: replacement)
		refreshMenuBarBandColor()
		resetTimer()
	}
}

extension SSWebView {
	/**
	Load `url` and return once the page has finished, or throw if it fails.
	*/
	@MainActor
	func loadAndWait(_ url: URL, timeout: Duration) async throws {
		if url.isFileURL {
			loadFileURL(url.appendingPathComponent("index.html", isDirectory: false), allowingReadAccessTo: url)
		} else {
			var request = URLRequest(url: url)
			request.cachePolicy = .reloadIgnoringLocalCacheData
			load(request)
		}

		// Polling rather than racing the navigation delegate against a timer. The delegate belongs to the shared controller and reports for whichever web view is live, so a replacement loading out of sight cannot use it. `isLoading` flips false on both success and failure, and the URL check below tells them apart.
		let step = Duration.milliseconds(100)
		var waited = Duration.zero

		while isLoading {
			guard waited < timeout else {
				stopLoading()
				throw CocoaError(.userCancelled)
			}

			try await Task.sleep(for: step)
			waited += step
		}

		guard self.url != nil else {
			throw CocoaError(.fileNoSuchFile)
		}
	}
}
