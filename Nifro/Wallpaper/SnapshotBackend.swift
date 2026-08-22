import AppKit
import WebKit

/**
Draws a website by taking a picture of it every so often, instead of keeping a browser running behind it.

Most pages people use as wallpapers change on a timer rather than continuously. A clock ticks once a minute. A dashboard refreshes every quarter of an hour. Rendering those live keeps a WebContent process, its memory and its compositing running all day to produce a picture that was already correct.

So the web view goes into a window nobody can see. Load the page, wait for it to settle, take one snapshot, show that, and drop the web view. The process exits with it. Between refreshes the wallpaper costs an image view.

The cost is that nothing moves and nothing can be clicked, which is why this is per-website and not a global switch. The curated site list already carries the call for each entry, where `backend: snapshot` means exactly this.
*/
extension WallpaperScene {
	/**
	How long to let a page settle after it finishes loading before photographing it.

	Fonts, images and the first frame of any animation land after `didFinish`. A snapshot taken immediately catches a half-drawn page often enough to matter.
	*/
	private static let settleDelay = Duration.seconds(2)

	var usesSnapshotRendering: Bool {
		website?.rendering == .snapshot
			&& !AppState.shared.isBrowsingMode
			// A still cannot be clicked, so the two settings cannot both win.
			&& !(website?.allowsInteraction ?? false)
	}

	/**
	Refresh the still. Loads the page out of sight, photographs it, and drops the renderer.
	*/
	func refreshSnapshot() {
		guard
			usesSnapshotRendering,
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

			let size = screen?.frameWithoutStatusBar.size ?? CGSize(width: 1920, height: 1080)
			let renderer = makeOffscreenRenderer(size: size)

			defer { renderer.close() }

			guard let webView = renderer.contentView as? SSWebView else {
				return
			}

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

			let configuration = WKSnapshotConfiguration()
			configuration.rect = website?.crop ?? CGRect(origin: .zero, size: size)

			guard let image = try? await webView.takeSnapshot(configuration: configuration) else {
				return
			}

			showSnapshot(image)
		}
	}

	/**
	A window off the edge of every display, so the page renders without ever being seen.
	*/
	private func makeOffscreenRenderer(size: CGSize) -> NSWindow {
		let webView = webViewController.makeReplacementWebView()
		webView.frame = CGRect(origin: .zero, size: size)

		let window = NSWindow(
			contentRect: CGRect(x: -size.width - 1000, y: -size.height - 1000, width: size.width, height: size.height),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = webView
		window.orderBack(nil)

		return window
	}

	private func showSnapshot(_ image: NSImage) {
		let view = NSImageView(frame: window.contentLayoutRect)
		view.imageScaling = .scaleAxesIndependently
		view.image = image
		view.autoresizingMask = [.width, .height]

		snapshotView = view
		frozenView = nil
		renderedRegion = nil
		window.cropRect = website?.crop
		window.contentView = view
		installMenuBarBandIfNeeded()
	}

	/**
	Stop drawing from stills and hand the window back to the live web view.

	Does not load anything, because the caller is on its way to doing that. Loading here too would make this and `loadWebsite` call each other. That terminates today only because of a guard, and would stop terminating the moment someone moved it.
	*/
	func stopSnapshotRendering() {
		snapshotTask?.cancel()
		snapshotTask = nil

		guard snapshotView != nil else {
			return
		}

		snapshotView = nil
		installContentView()
	}
}

extension Website {
	enum Rendering: String, CaseIterable, Codable, Sendable {
		case live
		case snapshot

		var title: String {
			switch self {
			case .live:
				"Keep rendering"
			case .snapshot:
				"Refresh periodically"
			}
		}

		var explanation: String {
			switch self {
			case .live:
				"The page keeps running. Necessary for anything that animates or that you want to click."
			case .snapshot:
				"The page is loaded, photographed and closed again on each refresh. Costs almost nothing between refreshes, but nothing moves."
			}
		}
	}
}
