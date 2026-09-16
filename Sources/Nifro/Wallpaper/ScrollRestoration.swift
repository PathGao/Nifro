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

A wallpaper often shows one region of a long page, a particular day in a calendar or a section of a dashboard, and every automatic reload used to drop the user back at the top.

The position is captured just before a reload rather than polled, so nothing runs in the background to support it. That covers the reload case, which is the one people hit. A hard quit loses at most the last scroll.

`WKWebView.interactionState` would restore history, form state and scroll in one property, and it is the fuller answer. It goes unused here because applying it drives a navigation, and a stale or rejected blob leaves a blank wallpaper with no obvious way back. Scrolling fails safe. If it does not work, the page is merely at the top.
*/
extension AppState {
	/**
	Drop every remembered scroll position, page address and page zoom.

	Part of clearing website data, because that is what these are: where somebody had scrolled to, what
	part of a map they were looking at, and how far they had zoomed a page in. A button offered as a way
	to leave no trace should not leave the most legible one.

	All three families are keyed per page, and Browsing Mode writes them for pages the user only visited
	once, so nothing else ever removes them.
	*/
	func forgetWherePagesWere() {
		for key in UserDefaults.standard.dictionaryRepresentation().keys
		where PerPageDefaults.allCases.contains(where: { key.hasPrefix($0.rawValue) }) {
			UserDefaults.standard.removeObject(forKey: key)
		}
	}

	/**
	Drop the records of pages that belong to no website in the list.

	Two things land here and it is one sweep on purpose, because they are the same thing. Deleting a
	website used to leave its scroll position, its fragment and its zoom in `UserDefaults` for as long
	as the app stayed installed: only the clear-everything button above ever removed a record, and it
	removes all of them. And every record written before the keys moved off the page's address is
	claimed by no website `id` at all, so it reads here as an orphan too — which is what keeps the one
	dropped generation of positions from sitting in the defaults forever.

	It runs beside `DiskBudget.removeOrphanedStores`, on the same list and by the same argument: a
	record whose website is gone is exactly a store whose website is gone, and the app is the only
	thing that knows which websites exist.

	An empty list collects nothing rather than everything, for the reason `DiskBudget.orphans` spells
	out — the one reading that must not be trusted is the one saying every website has been deleted.
	*/
	func forgetOrphanedPageRecords(keeping websiteIDs: Set<Website.ID>) {
		guard !websiteIDs.isEmpty else {
			return
		}

		let live = Set(websiteIDs.map(\.uuidString))

		for key in UserDefaults.standard.dictionaryRepresentation().keys {
			guard
				let kind = PerPageDefaults.allCases.first(where: { key.hasPrefix($0.rawValue) }),
				!live.contains(String(key.dropFirst(kind.rawValue.count)))
			else {
				continue
			}

			UserDefaults.standard.removeObject(forKey: key)
		}
	}
}

/**
Every kind of thing the app remembers about one page, and the prefix its keys carry.

One enum rather than three literals so the sweep above can be `allCases`. It was three, spelled out
at the place that wrote each one and again at the place that cleared them, and the third was missing
from the sweep — the button that promises to leave no trace left every page's zoom level behind.
A fourth kind added now has to be a case here to get a key at all, and being a case is what gets it
swept.
*/
enum PerPageDefaults: String, CaseIterable {
	case scrollPosition = "scrollPosition_"
	case lastAddress = "lastAddress_"
	case zoomLevel = "zoomLevel_"

	/**
	The `UserDefaults` key this kind of record uses for one website entry.

	The entry's `id`, not its address, because the address is not what these records have to agree
	with. Each entry's page runs in `WKWebsiteDataStore(forIdentifier:)` on that `id`, so two entries
	carrying the same URL already have separate storage — and under an address-shaped key they shared
	one scroll position and one zoom, each overwriting the other's. That takes two entries on one URL,
	which is what a sync group mints per follower display and what duplicating a list mints per copy.
	An `id` also survives editing the entry's address, which is what editing an entry means.

	The question the old key had to ask of each kind — whether `?panel=2` is a different page — cannot
	be asked of an `id` and no longer needs to be. It only ever decided which addresses collapsed onto
	one record; an entry is one record, whatever its page's address does. The cost is the other half
	of that: a page reached by clicking a link in Browsing Mode now shares the entry's record rather
	than getting its own, so the last page scrolled is the one restored.
	*/
	func key(for websiteID: Website.ID) -> String {
		"\(rawValue)\(websiteID.uuidString)"
	}
}

extension WallpaperScene {
	// Optional rather than an empty array on purpose: `nil` means no position was ever stored for this
	// page, and an empty array would have to stand in for that as well as for a position, which the
	// restore path already has to tell apart from [0, 0].
	// swiftlint:disable:next discouraged_optional_collection
	private func scrollPositionKey(for websiteID: Website.ID) -> Defaults.Key<[Double]?> {
		.init(PerPageDefaults.scrollPosition.key(for: websiteID))
	}

	// MARK: - The address after the #

	/**
	Keyed on the entry, and the fragment is what is being remembered about it.

	Nothing is lost by the key no longer carrying the address: both sides of this record already
	refuse a stored address that differs from the website's in anything but the fragment, so editing
	an entry's address makes its old fragment unusable rather than misapplied.
	*/
	private func lastAddressKey(for websiteID: Website.ID) -> Defaults.Key<String?> {
		.init(PerPageDefaults.lastAddress.key(for: websiteID))
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

		Defaults[lastAddressKey(for: onScreen.id)] = current.absoluteString
	}

	/**
	The address to load: the website's, moved to where the page last was, if it said where that is.
	*/
	var addressToLoad: URL? {
		guard
			let website,
			Defaults[.restoreScrollPosition],
			let stored = Defaults[lastAddressKey(for: website.id)],
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
			let websiteID = webViewController.webView.websiteID
		else {
			return
		}

		let key = scrollPositionKey(for: websiteID)

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
	Put a freshly loaded page back the way the user left it.

	Both kinds together, and every caller takes this rather than one of the parts, because they had
	drifted: the scroll position was restored from the two places a page can arrive, and the zoom level
	from one — the wrong one. `zoomLevelWrapper` was read off `webViewController.webView`, which during
	a swap is still the *outgoing* page, so switching website wrote the old page's zoom back onto the
	old page and the new one arrived at 1. The web view to act on is the one being handed the page, so
	it is a parameter here, exactly as it already was for the scroll.

	This is the same guard the per-page defaults themselves got: a third kind of remembered state has
	one place to be added, and both arrival paths get it for free.
	*/
	func restorePageState(in webView: WKWebView) {
		// One cast for both halves. Each of them needs the web view's own website, and that is the
		// question the whole re-key turns on: what the page remembers is filed under the same `id` the
		// store it loaded from is filed under.
		guard let webView = webView as? SSWebView else {
			return
		}

		restoreScrollPosition(in: webView)
		restoreZoomLevel(in: webView)
	}

	/**
	Put back the zoom level chosen from the page's own context menu.
	*/
	private func restoreZoomLevel(in webView: SSWebView) {
		// Reading the wrapper gives the persisted level, or the live one when nothing was persisted.
		// Writing it applies `pageZoom`. Skipping 1 keeps an untouched page from being written back.
		let zoomLevel = webView.zoomLevelWrapper

		if zoomLevel != 1 {
			webView.zoomLevelWrapper = zoomLevel
		}
	}

	/**
	Scroll a freshly loaded page back to where it was.
	*/
	private func restoreScrollPosition(in webView: SSWebView) {
		guard
			Defaults[.restoreScrollPosition],
			let websiteID = webView.websiteID,
			let position = Defaults[scrollPositionKey(for: websiteID)],
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
