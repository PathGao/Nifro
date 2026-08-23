import AppKit
import WebKit

/**
Puts the page back where it was.

Two things, because pages keep their position in two places. A long page keeps it in the document's
scroll, and that is captured before a reload and put back after. A page that draws its own world —
floor796, a map — keeps it in the address, after the `#`, and that is remembered here too so a
relaunch does not drop the user back at the middle of the map.

The third place, `localStorage`, needs nothing: the web view uses the persistent data store, so a
site that saves its own position gets it back on its own.

A wallpaper often shows one region of a long page, a particular day in a calendar or a section of a dashboard, and every automatic reload used to drop the user back at the top. Upstream tracked this for six years without landing it (Plash#39).

The position is captured just before a reload rather than polled, so nothing runs in the background to support it. That covers the reload case, which is the one people hit. A hard quit loses at most the last scroll.

`WKWebView.interactionState` would restore history, form state and scroll in one property, and it is the fuller answer. It goes unused here because applying it drives a navigation, and a stale or rejected blob leaves a blank wallpaper with no obvious way back. Scrolling fails safe. If it does not work, the page is merely at the top.
*/
extension AppState {
	/**
	Drop every remembered scroll position and page address.

	Part of clearing website data, because that is what these are: where somebody had scrolled to and
	what part of a map they were looking at. A button offered as a way to leave no trace should not
	leave the most legible one.
	*/
	func forgetWherePagesWere() {
		for key in UserDefaults.standard.dictionaryRepresentation().keys
		where key.hasPrefix(WallpaperScene.scrollPositionKeyPrefix) || key.hasPrefix(WallpaperScene.lastAddressKeyPrefix) {
			UserDefaults.standard.removeObject(forKey: key)
		}
	}
}

extension WallpaperScene {
	static let scrollPositionKeyPrefix = "scrollPosition_"

	// Optional rather than an empty array on purpose: `nil` means no position was ever stored for this
	// page, and an empty array would have to stand in for that as well as for a position, which the
	// restore path already has to tell apart from [0, 0].
	// swiftlint:disable:next discouraged_optional_collection
	private func scrollPositionKey(for url: URL) -> Defaults.Key<[Double]?> {
		let identifier = url
			.normalized(removeFragment: true, removeQuery: false)
			.absoluteString
			.removingSchemeAndWWWFromURL
			.toData
			.base64EncodedString()

		return .init("\(Self.scrollPositionKeyPrefix)\(identifier)")
	}

	// MARK: - The address after the #

	static let lastAddressKeyPrefix = "lastAddress_"

	/**
	Keyed on the address with the fragment taken off, which is the page, so the fragment is what is
	being remembered about it.
	*/
	private func lastAddressKey(for url: URL) -> Defaults.Key<String?> {
		let identifier = url
			.normalized(removeFragment: true, removeQuery: false)
			.absoluteString
			.removingSchemeAndWWWFromURL
			.toData
			.base64EncodedString()

		return .init("\(Self.lastAddressKeyPrefix)\(identifier)")
	}

	/**
	Remember where the page has moved itself to, when that shows in the address.

	Only the fragment. A different path or query is a different page, and loading a page nobody asked
	for is exactly how "Update Website to Current" once turned a website into a GitHub 404 by firing
	on its own — so the remembered address is kept *beside* the website's own rather than over it, and
	is only ever used when the two differ in nothing else.
	*/
	func captureNavigatedAddress() {
		guard
			Defaults[.restoreScrollPosition],
			// The website whose page is on screen, not the one the scene is heading for. Switching
			// website reassigns `website` before the old page has gone, so recording against it would
			// file one site's position under another — and then reject it, because the addresses do not
			// match, which is how the position was lost rather than misplaced.
			let onScreen = loadedWebsiteID.flatMap({ WebsitesController.shared.all[id: $0] }),
			let current = webViewController.webView.navigatedURL(for: onScreen),
			current.fragment?.isEmpty == false,
			current.normalized(removeFragment: true) == onScreen.url.normalized(removeFragment: true)
		else {
			return
		}

		Defaults[lastAddressKey(for: onScreen.url)] = current.absoluteString
	}

	/**
	The address to load: the website's, moved to where the page last was, if it said where that is.
	*/
	var addressToLoad: URL? {
		guard
			let website,
			Defaults[.restoreScrollPosition],
			let stored = Defaults[lastAddressKey(for: website.url)],
			let remembered = URL(string: stored),
			remembered.normalized(removeFragment: true) == website.url.normalized(removeFragment: true)
		else {
			return website?.url
		}

		return remembered
	}

	/**
	Remember where the page is, so the next load can put it back.
	*/
	func captureScrollPosition() {
		guard
			Defaults[.restoreScrollPosition],
			let url = webViewController.webView.url
		else {
			return
		}

		let key = scrollPositionKey(for: url)

		webViewController.webView.evaluateJavaScript(
			"[window.scrollX, window.scrollY]",
			in: nil,
			in: .defaultClient
		) { result in
			guard
				case .success(let value) = result,
				let position = value as? [Double],
				position.count == 2,
				position != [0, 0]
			else {
				return
			}

			Defaults[key] = position
		}
	}

	/**
	Scroll a freshly loaded page back to where it was.
	*/
	func restoreScrollPosition(in webView: WKWebView) {
		guard
			Defaults[.restoreScrollPosition],
			let url = webView.url,
			let position = Defaults[scrollPositionKey(for: url)],
			position.count == 2,
			position != [0, 0]
		else {
			return
		}

		// Pages that build themselves from script are not their full height at `didFinish`, so a single scroll lands short. Retrying a few times costs nothing and covers the common case without waiting on a layout signal WebKit does not offer.
		webView.evaluateJavaScript(
			"""
			(() => {
				const x = \(position[0]);
				const y = \(position[1]);
				let attempts = 0;

				const go = () => {
					window.scrollTo(x, y);

					if (++attempts < 5 && Math.abs(window.scrollY - y) > 1) {
						setTimeout(go, 200);
					}
				};

				go();
			})();
			""",
			in: nil,
			in: .defaultClient,
			completionHandler: nil
		)
	}
}
