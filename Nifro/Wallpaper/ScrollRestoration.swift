import AppKit
import WebKit

/**
Puts the page back where it was after a reload.

A wallpaper often shows one region of a long page — a particular day in a calendar, a section of a dashboard — and every automatic reload used to throw that away and drop the user back at the top. Upstream tracked this for six years without landing it (Plash#39).

The position is captured just before a reload rather than polled, so nothing runs in the background to support it. That covers the reload case, which is the one people actually hit; a hard quit loses at most the last scroll.

`WKWebView.interactionState` would restore history, form state and scroll in one property and is the fuller answer. It is not used here because applying it drives a navigation, and a stale or rejected blob leaves a blank wallpaper with no obvious way back — a failure this could not be tested against before shipping. Scrolling fails safe: if it does not work, the page is merely at the top.
*/
extension AppState {
	private static let scrollPositionKeyPrefix = "scrollPosition_"

	private func scrollPositionKey(for url: URL) -> Defaults.Key<[Double]?> {
		let identifier = url
			.normalized(removeFragment: true, removeQuery: false)
			.absoluteString
			.removingSchemeAndWWWFromURL
			.toData
			.base64EncodedString()

		return .init("\(Self.scrollPositionKeyPrefix)\(identifier)")
	}

	/**
	Remember where the page is, so the next load can put it back.
	*/
	func captureScrollPosition() {
		guard
			Defaults[.restoreScrollPosition],
			let url = webViewController.webView.url,
			frozenView == nil
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
