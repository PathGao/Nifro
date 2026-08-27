import AppKit
import WebKit

/**
Loads the next page out of sight and only shows it once it has arrived.

Loading in place has three failure modes, all of them the same mechanism:

- the wallpaper goes white while the new page is on its way
- a load that fails leaves the desktop showing nothing, most visibly when the Mac wakes before the network does
- switching between images cuts rather than fades

Loading into a second web view fixes all three at once. The current page stays up, untouched, until the replacement has finished. A failure then changes nothing on screen. The old page stays, and the error goes to the menu bar tooltip instead of the desktop.

Scoped to replacing a page. The first load of the session still goes straight into the window, because there is nothing to protect yet and no reason to put the one path that has to work behind new machinery.
*/
extension WallpaperScene {
	/**
	Whether there is anything on the wallpaper worth keeping while the next page loads.

	A still counts. It used to be only a live page with a URL, which is why entering Browsing Mode on
	a website drawn from stills showed the desktop: the still was on screen, the live page behind it
	had been dropped, and "no live page" was read as "nothing to protect".
	*/
	private var hasSomethingOnScreen: Bool {
		switch content {
		case .empty:
			false
		case .live:
			webViewController.webView.url != nil
		}
	}

	/**
	Load `url`, keeping the current page visible until the new one is ready.

	Falls back to loading in place when there is nothing on screen worth protecting.
	*/
	func loadBySwapping(_ url: URL?) {
		// The other half of the gate in `load`. A suspended scene has nothing on screen, so this would
		// fall through to `load` and be refused there anyway — but "anyway" is the word that stops
		// being true the first time something switches a display off without suspending it, and the
		// swap path is the one that spends a whole page fetch before it finds out.
		guard !isSwitchedOff else {
			return
		}

		guard
			let url,
			hasSomethingOnScreen
		else {
			load(url)
			return
		}

		pendingLoad?.cancel()

		// Built and recorded here rather than as the task's first statement, because `pendingWebView`
		// is what tells the panel this display is busy — and a task body does not run until the next
		// hop, which is long enough for the panel to draw one frame of a column that has not noticed
		// the click yet.
		let replacement = webViewController.createWebView()
		pendingWebView = replacement

		pendingLoad = Task { [weak self] in
			guard let self else {
				return
			}

			defer {
				// Only if it is still ours. A load started while this one was in flight has already put
				// its own replacement here, and clearing that would tell the panel the newer load had
				// finished.
				if pendingWebView === replacement {
					pendingWebView = nil
				}
			}

			do {
				try await replacement.loadAndWait(url, timeout: Self.loadTimeout)
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
	Put the finished replacement on screen.

	Straight swap, no fade. The fade that used to be here took the new content from transparent to
	opaque — and the page it was replacing had already been taken out by then, so what showed through
	for a third of a second was the desktop. Two pages that have both finished loading can just change
	places; there is nothing to cover up.

	// ponytail: a real cross-fade would need both pages in the window at once, which means a
	// container view and a second answer to what `window.contentView` holds. Worth it only if a plain
	// change turns out to read as abrupt.
	*/
	private func adopt(_ replacement: SSWebView) {
		// Before adopting, while the outgoing page is still the live one.
		captureNavigatedAddress()

		replacement.isHidden = false
		webViewController.adopt(replacement)

		// The observer was watching the web view that just went away.
		observeAddressChanges()

		// Before `installContentView`, which refuses to touch a page belonging to another website.
		// This is the moment the page on screen becomes this one.
		adoptLoadedWebsite()
		installContentView()

		restorePageState(in: replacement)
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
		loadWallpaper(url)

		// Not the navigation delegate: it belongs to the shared controller and reports for whichever web view is live, so a replacement loading out of sight would never hear from it. That rules out the delegate, not the web view — `isLoading` is KVO-observable and observation is per instance, so this one can be watched directly. It flips false on both success and failure, and the URL check below tells them apart.
		let started = ContinuousClock.now

		// The timeout has to end the load, not merely stop waiting for it: an address that never answers leaves `isLoading` true forever, and `stopLoading` is what makes it flip.
		let deadline = Task {
			try await Task.sleep(for: timeout)
			stopLoading()
		}

		defer {
			deadline.cancel()
		}

		for await isLoading in publisher(for: \.isLoading).values where !isLoading {
			break
		}

		guard ContinuousClock.now - started < timeout else {
			throw CocoaError(.userCancelled)
		}

		guard self.url != nil else {
			throw CocoaError(.fileNoSuchFile)
		}
	}
}

extension WKWebView {
	/**
	Start loading `url` the way that address has to be loaded.

	Three addresses, three ways in. A local folder needs the sandbox opened for it first, or the read
	is refused and a local website silently stops updating. A YouTube player has to be framed by a
	page rather than be one. Everything else is a request.
	*/
	func loadWallpaper(_ url: URL) {
		if url.isFileURL {
			_ = url.accessSandboxedURLByPromptingIfNeeded()
			loadFileURL(url.appendingPathComponent("index.html", isDirectory: false), allowingReadAccessTo: url)
			return
		}

		if let host = VideoEmbed.hostPage(for: url) {
			loadHTMLString(host.html, baseURL: host.baseURL)
			return
		}

		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		load(request)
	}
}
