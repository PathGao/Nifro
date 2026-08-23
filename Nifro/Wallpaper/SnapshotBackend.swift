import AppKit
import WebKit

/**
Draws a website by taking a picture of it every so often, instead of keeping a browser running behind it.

Most pages people use as wallpapers change on a timer rather than continuously. A clock ticks once a minute. A dashboard refreshes every quarter of an hour. Rendering those live keeps a WebContent process, its memory and its compositing running all day to produce a picture that was already correct.

So the page is loaded, photographed once, and dropped. The web process exits with it, and between refreshes the wallpaper costs an image view.

The photograph is taken in the wallpaper's own window rather than a hidden one. WebKit does not run `requestAnimationFrame` for a page whose window is not on screen, and it does not matter that the page is told otherwise — overriding `document.hidden` and `document.visibilityState` changes what the page reads and not what the engine does. A page that draws itself, which is most maps, charts and anything on a canvas, therefore photographs blank from a hidden window however long you wait. The page is visible for the couple of seconds it takes to load and settle, and then it is a still again.

The cost is that nothing moves and nothing can be clicked, which is why this is per-website and not a global switch. The curated site list already carries the call for each entry, where `backend: snapshot` means exactly this.
*/
extension WallpaperScene {
	/**
	How long to let a page settle after it finishes loading before photographing it.

	Fonts, images and the first frame of any animation land after `didFinish`. A snapshot taken immediately catches a half-drawn page often enough to matter.
	*/
	private static let settleDelay = Duration.seconds(2)

	// ponytail: the live page is on screen while it loads, once per refresh interval. Hiding that
	// would mean keeping the still on top of a web view that is still in the window, since taking the
	// web view out of the window is exactly what breaks the render. Worth doing if a short interval
	// ever makes the reload visible enough to notice.

	/**
	Refresh the still. Loads the page out of sight, photographs it, and drops the renderer.
	*/
	func refreshSnapshot() {
		guard
			renderingMode == .snapshot,
			let url = website?.url,
			snapshotTask == nil
		else {
			return
		}

		snapshotTask = Task { [weak self] in
			defer { self?.snapshotTask = nil }

			guard let self else {
				return
			}

			// The same layout size the live page gets, because the crop below is a rectangle of that layout.
			let size = pageLayoutSize ?? CGSize(width: 1920, height: 1080)

			// Puts the page in the window, which is what makes it render at all.
			content = .live(zoom: website?.zoom)

			let webView = webViewController.webView

			do {
				var resolved = url
				if let replaced = try replacePlaceholders(of: url) {
					resolved = replaced
				}

				try await webView.loadAndWait(resolved, timeout: .seconds(30))
			} catch {
				AppState.shared.webViewError = error
				return
			}

			try? await Task.sleep(for: Self.settleDelay)

			guard !Task.isCancelled else {
				return
			}

			// The region the live page would be showing, photographed at the width it would fill.
			// Photographing the region at its own width and letting an image view stretch it would
			// show the magnified page as a blur.
			let region = (website?.zoom ?? .identity).region(inPageOfSize: size)
			let configuration = WKSnapshotConfiguration()
			configuration.rect = region
			configuration.snapshotWidth = NSNumber(value: size.width)

			guard let image = try? await webView.takeSnapshot(configuration: configuration) else {
				return
			}

			content = .snapshot(image)

			// The still is on screen now, so the page behind it has nothing left to do. Dropping it
			// takes the web process with it, which is the point of rendering this way.
			webViewController.releaseWebView()
		}
	}

	/**
	Stop drawing from stills and hand the window back to the live web view.

	Does not load anything, because the caller is on its way to doing that. Loading here too would make this and `loadWebsite` call each other. That terminates today only because of a guard, and would stop terminating the moment someone moved it.
	*/
	func stopSnapshotRendering() {
		snapshotTask?.cancel()
		snapshotTask = nil

		guard case .snapshot = content else {
			return
		}

		installContentView()
	}
}

extension Website {
	enum Rendering: String, CaseIterable, Codable, Sendable {
		case automatic
		case live
		case snapshot

		var title: String {
			switch self {
			case .automatic:
				String(localized: "Decide automatically")
			case .live:
				String(localized: "Keep rendering")
			case .snapshot:
				String(localized: "Refresh periodically")
			}
		}

		var explanation: String {
			switch self {
			case .automatic:
				String(localized: "Watches what the page actually does for a minute, then keeps rendering it or switches to stills. It changes its mind again if the page starts moving.")
			case .live:
				String(localized: "The page keeps running. Necessary for anything that animates or that you want to click.")
			case .snapshot:
				String(localized: "The page is loaded, photographed and closed again on each refresh. Costs almost nothing between refreshes, but nothing moves.")
			}
		}
	}
}
