import AppKit
import WebKit

/**
Loads the next page out of sight and only shows it once it has arrived.

Loading in place has three failure modes, all of them the same mechanism:

- the wallpaper goes white while the new page is on its way
- a load that fails leaves the desktop showing nothing, most visibly when the Mac wakes before the network does
- switching between images cuts rather than fades

Loading into a second web view fixes all three at once. The current page stays up, untouched, until the replacement has finished. A failure then changes nothing on screen. The old page stays, and the error goes to the menu bar tooltip instead of the desktop.

Scoped to replacing a page with a different one. Two loads are not that and do not come through here. The first load of the session goes straight into the window, because there is nothing to protect yet and no reason to put the one path that has to work behind new machinery. And a reload of the page already on screen goes back into the web view it is already in — `reloadInPlace` below argues that one, because a swap there pays the whole cost of the mechanism for a page it is replacing with itself.
*/
extension WallpaperScene {
	/**
	Whether there is anything on the wallpaper worth keeping while the next page loads.

	Two questions, because `.empty` is not the only way to be showing nothing. Content only ever goes
	`.empty` in `tearDown`, where the display has gone and the window with it — a case this path can
	barely reach. The one it does reach is `releaseWebView`: a suspend, a battery cut, the app being
	switched off, all of which drop the page and hand the controller a web view built from scratch, and
	every one of them leaves content at `.live`. A scene that has never loaded at all is the same shape.
	So the URL is the half that does the work, and reading the case alone would have the swap spend a
	second web view, a WebContent process and a network session protecting a window with nothing in it.
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
	Reload the page that is already on screen, in the web view it is already in. Answers whether it did.

	A swap builds a whole web view to load into: a `WKWebViewConfiguration`, every user script the
	website carries, the content-blocking rule list, and a `WKWebsiteDataStore(forIdentifier:)` — a new
	WebContent process and a new network session, with the previous pair dropped once the new page
	arrives. That is the price of the isolation above, and it is worth paying to *change* the page.
	A timed reload does not change the page. It asks for the same address, in the same website, into a
	view configured identically to the one already showing it, and then throws that view away. Two
	displays on a fifteen-minute interval spend about 192 process launches a day doing it.

	So the fast path, and the four conditions are what make it the timed reload and nothing else:

	- `pendingWebView == nil`, so a swap already in flight is not raced by a reload of the page it is
	about to replace. The swap path cancels its predecessor; this one has nothing to cancel with.
	- `loadedWebsite == website`, the whole struct as `isUpToDate` compares it. The website's CSS,
	JavaScript and zoom are compiled into the web view when the web view is made, so a page loaded from
	an older version of this website has to be built again rather than fetched again — which is exactly
	what `applyWebsiteChanges` reloads for.
	- `webViewController.webView.url == url`, so a page that redirected somewhere else, or that was
	clicked away from in Browsing Mode, is put back rather than reloaded where it drifted to. A file
	URL and an embedded video also fail this on their own: one loads `index.html` inside the folder and
	the other a host page around the address, so neither web view is ever showing the URL it was given.
	- `hasSomethingOnScreen`, the same question the swap asks, so a display whose web view was dropped
	and not loaded into again is not told to reload a page it does not have.

	`reloadFromOrigin` rather than `reload`, because `loadWallpaper` sends the request with
	`.reloadIgnoringLocalCacheData` and this path has to be as fresh as the one it replaces. Plain
	`reload` revalidates the document and takes its subresources from the cache, which on a dashboard
	is where the numbers are. `reloadFromOrigin` revalidates end to end, document and subresources
	both, so nothing stale survives it — with conditionals where the server offers them, so some of it
	comes back as a 304 rather than as bytes. Freshness unchanged, and a little less of the network.

	**What it gives up:** the failure isolation this file exists for, on this path only. A swap that
	fails leaves the last good page up and puts the error in the menu bar tooltip; here WebKit is
	reloading the live view, and if the new document commits and then fails, what commits is what shows.
	Most of the isolation survives anyway, because the case the header names — the Mac waking before the
	network does — fails provisionally, and a provisional failure never commits: `WKWebView` has no
	error page of its own, so the document already up stays up and the error still reaches the tooltip
	through `didFailProvisionalNavigation`. Deliberate, and narrow: the paths with something real to
	lose — waking, a website edited, the Reload command, the first load — all still swap, because none
	of them passes `inPlace`.
	*/
	func reloadInPlace(_ url: URL?) -> Bool {
		guard
			!isSwitchedOff,
			let url,
			hasSomethingOnScreen,
			pendingWebView == nil,
			loadedWebsite == website,
			webViewController.webView.url == url
		else {
			return false
		}

		// Optimistically, exactly as `load` clears it at the top: a reload that fails reports through
		// the navigation delegate and stores its error again, and leaving the last failure in the
		// tooltip through every successful reload after it is the alternative.
		AppState.shared.setWebViewError(nil, on: display)

		// Everything `adopt` does by hand for a replacement is already wired for the live view.
		// `didFinish` reveals the page, re-samples the menu bar band, records the title, applies the
		// mute setting and restores the scroll position and zoom — all of it keyed on the web view the
		// delegate reports for, which on this path is the one that was already live. The repeating
		// timer needs no rearming either; it is the thing that fired.
		webViewController.webView.reloadFromOrigin()

		return true
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

			// A load started while this one was still waiting for its first hop has already cancelled
			// us. Starting the fetch anyway spends a WebContent process and a page load on a
			// replacement nothing will adopt. The `defer` above is the whole of the cleanup, exactly
			// as it is for the two early returns below.
			guard !Task.isCancelled else {
				return
			}

			do {
				try await replacement.loadAndWait(url, timeout: Self.loadTimeout)
			} catch {
				// The page on screen is still the last one that worked. Leaving it there is the whole point, so the error goes to the tooltip rather than the desktop.
				guard !Task.isCancelled else {
					return
				}

				AppState.shared.setWebViewError(error, on: display)
				return
			}

			guard !Task.isCancelled else {
				return
			}

			AppState.shared.setWebViewError(nil, on: display)
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

		// The page being adopted has finished loading — that is what `loadAndWait` above waited for —
		// but nothing has said so. `pageDidSettle` is the usual route and it refuses this one on
		// purpose: it guards on the web view being the live one, and a replacement finishes while it
		// is still the pending one, seconds before this line makes it live. Nothing navigates
		// afterwards, so it never fires again.
		//
		// A swap got away with that for as long as `hasRevealedPage` was already true from the page
		// being replaced. It is false exactly when the previous load had not settled yet — and then the
		// swap inherits it, and everything gated on the flag reads the display as still waiting for a
		// page that is already up. `isLoading` is one of them, so the chooser and the menu bar icon go
		// on pulsing at a wallpaper that has finished. `refreshMenuBarBandColor` is the other, and it
		// is the one that shows: it refuses to sample a page it does not believe is on screen, so the
		// band keeps the colour it took off the page before this one — or, on a display that has never
		// sampled one, stays off the menu bar entirely, because `updateMenuBarBandVisibility` waits for
		// `hasSampledColor`. The re-sample at the bottom of this method is behind the same flag and
		// rescues neither. Both symptoms are one missing call, and both clear themselves eventually,
		// when the backstop `load` scheduled for the *previous* page fires up to thirty seconds later.
		//
		// Not the page itself, which is on screen by then either way: `replacement.isHidden = false`
		// above is what shows it and `installContentView` is what puts it in the window. The reason
		// written here before was that reveal is also the only thing that unhides `window.contentView`,
		// and that slot's flag is one nothing in the app has ever set — the single hide anywhere is in
		// `createWebView`, on the web view, which is the thing reveal unhides. The line that wrote the
		// slot has been deleted; what a swap needs from reveal is the flag and what hangs off it.
		//
		// After `installContentView`, not before it. `applyContent` is what installs the menu bar band,
		// and everything reveal does past the flag needs a band to exist — both `refreshMenuBarBandColor`
		// and `updateMenuBarBandVisibility` return on a missing one, and reveal runs once by design. It
		// also reads the website for the band, and `adoptLoadedWebsite` above is what makes that this one.
		revealPage()

		restorePageState(in: replacement)

		// Framing only, and the condition reads backwards on purpose: the call is kept for the one
		// case where it is the *only* sample. Everywhere else `installContentView` above has already
		// taken one — it assigns `content`, and `applyContent` under that observer installs the band,
		// which samples — so this line bought a second `takeSnapshot` into the web content process
		// and a second `areaAverage` render for the same colour, on every website switch, every
		// rotation tick, every wake and every website edit.
		//
		// While framing, `installContentView` refuses and never writes `content`, so that first
		// sample does not happen; and the page being framed was put up long before, so the reveal
		// above returns at its own guard rather than sampling. Delete this and a framed display keeps
		// the colour it took off the page before this one.
		//
		// The earlier sample is the better one to keep, not merely the cheaper one. `restorePageState`
		// on the line above dispatches the scroll restoration as JavaScript and does not wait for it,
		// so anything sampled after it sees a page that may or may not have moved yet, depending on
		// which message the web content process answers first. The plain load path settles the same
		// question the same way: `didFinish` puts the page up, and samples, before it restores.
		if window.isFramingRegion {
			refreshMenuBarBandColor()
		}

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

		// `first(where:)` rather than a `where` clause on the loop, because `.values` is not a stream
		// of every value the property takes. Measured on macOS 26.6.2 with a standalone WebKit
		// harness: a `for await` over `publisher(for: \.isLoading).values` receives exactly one
		// element — whichever value KVO reports at subscription, which after `loadWallpaper` is
		// `true` — and then nothing, ever, while a plain `sink` on the same publisher and the same
		// web view receives all three of `false`, `true`, `false`. The flip this loop exists to see
		// is the one it could never be handed. Filtering upstream means the single element that does
		// arrive is the one worth waiting for, and `first` completes the publisher so the sequence
		// ends by itself.
		for await _ in publisher(for: \.isLoading).first(where: { !$0 }).values {}

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
