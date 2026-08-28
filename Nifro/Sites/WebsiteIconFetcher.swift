import AppKit
import LinkPresentation
import WebKit

// Moved out of Extensions.swift, which is where it was only because everything was. This is a
// component, not an extension.

// TODO: Make it an actor.
// TODO: Ensure it still works well. Try disabling the LinkPresentation API and caching.
/*
TODO when Swift 5.5 is out:
- Support more ways to get the icon: https://stackoverflow.com/a/22007642/64949
- Get all icons concurrently.
- Recreate the webview for each request.
- Use only a single `evaluateJavaScript` call.
- Run on DOM-ready instad of when the whole page has loaded.
	- If not possible, block all subresources: https://stackoverflow.com/questions/32119975/how-to-block-external-resources-to-load-on-a-wkwebview
- Make the thumbnail in WebsitesScreen not upscale when using 32x32 favicon.
- Support specifying target size and have it return the one closest above the target size, if any.
- Use the icons in the "Switch" menu.
*/
@MainActor
final class WebsiteIconFetcher: NSObject {
	private struct WebAppManifestIcon {
		let url: URL
		let size: CGSize?

		init?(_ dictionary: [String: String]) {
			guard
				// TODO: Handle relative URLs: https://developer.mozilla.org/en-US/docs/Web/Manifest/icons
				let urlString = dictionary["src"],
				let url = URL(string: urlString)
			else {
				return nil
			}

			self.url = url

			// TODO: Handle there being multiple space-separated sizes.
			self.size = if
				let sizeString = dictionary["sizes"]?.split(separator: " ").first,
				let size = CGSize.from(dimensions: String(sizeString))
			{
				size
			} else {
				nil
			}
		}
	}

	@MainActor
	static func fetch(for url: URL) async throws -> NSImage? {
		guard url.isValid else {
			throw NSError.appError("Invalid URL: \(url.absoluteString)")
		}

		return try await self.init().fetch(for: url)
	}

	@MainActor
	private lazy var webView: WKWebView = {
		let configuration = WKWebViewConfiguration()

		let userContentController = WKUserContentController()
		configuration.userContentController = userContentController

		let preferences = WKPreferences()
		preferences.javaScriptCanOpenWindowsAutomatically = false
		configuration.preferences = preferences

		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.customUserAgent = SSWebView.safariUserAgent

		return webView
	}()

	/**
	How long a page gets before its web view is taken away from it.

	Nothing is waiting on this number. No icon is on screen while one is being fetched, so the ceiling
	only has to sit past the point where a page that was going to finish already has — being generous
	costs a row in a list nothing. Thirty seconds is what `WallpaperScene.loadTimeout` was measured at
	for the same question, and this is double that, which is also `URLRequest`'s own default timeout:
	every request the load is still waiting on has given up by the time it fires.

	What it bounds is the leak. A live stream or a dashboard that polls forever — which is what this
	app is for — loads its main frame and then never reaches `didFinish`, so without a ceiling its web
	view, and the web content process behind it, stay alive until the app quits.
	*/
	private static let loadTimeout = Duration.seconds(60)

	private var url: URL?
	private var continuation: CheckedContinuation<Void, Error>?
	private var hasEnded = false

	/**
	End the wait for the page, exactly once, whatever ended it.

	Five things can: `didFinish`, the two failure callbacks, the task being cancelled and the ceiling.
	A checked continuation traps the process if two of them get through or if none does, so this is
	the only place in the file that resumes one, and dropping the continuation as it resumes is the
	guard. No lock: every one of the five is on the main actor by the time it arrives here — the class
	is `@MainActor` and so are the delegate callbacks, and the other two hop through `Task { @MainActor
	in }` first — so the read and the nilling cannot interleave.

	`hasEnded` is for the ordering the continuation alone cannot see. `withTaskCancellationHandler`
	runs its handler even when the task was already cancelled on the way in, and then there is no
	continuation stored yet to end. The flag is what the load finds when it goes to store one.
	*/
	private func end(_ result: Result<Void, Error>) {
		hasEnded = true

		guard let continuation else {
			return
		}

		self.continuation = nil
		continuation.resume(with: result)
	}

	/**
	Load `request` and return once the page has finished, or throw if it fails, is cancelled or outlasts `loadTimeout`.
	*/
	@MainActor
	private func loadAndWait(_ request: URLRequest) async throws {
		// The ceiling has to end the load and not merely stop waiting for it — the same reason
		// `SSWebView.loadAndWait` reaches for `stopLoading` — because a page that never finishes is
		// still holding the web view, which is the thing being reclaimed. Cancelled on the way out, so
		// a page that finishes in a second does not keep this instance alive for the other fifty-nine.
		let ceiling = Task { @MainActor in
			try await Task.sleep(for: Self.loadTimeout)
			self.webView.stopLoading()
			self.end(.failure(CocoaError(.userCancelled)))
		}

		defer {
			ceiling.cancel()
		}

		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				self.continuation = continuation

				guard !hasEnded else {
					end(.failure(CancellationError()))
					return
				}

				webView.load(request)
			}
		} onCancel: {
			// Any thread, and possibly before the operation above has run at all, so it hops to the
			// actor that owns the continuation rather than touching it from here. `stopLoading` is the
			// half that makes cancelling mean something: ending the wait only releases the caller —
			// `.task(id:)` in `IconView` cancels on every row that scrolls away — while the page carries
			// on loading in a web view nothing will ever look at again.
			Task { @MainActor in
				self.webView.stopLoading()
				self.end(.failure(CancellationError()))
			}
		}
	}

	private func getImage(_ url: URL) async throws -> NSImage? {
		let (data, _) = try await URLSession.shared.data(from: url)
		return NSImage(data: data)
	}

	// The leading slash is the whole of it. Relative resolution drops only the last path segment, so
	// a bare "favicon.ico" asks the directory the page happens to sit in — the site root only for a
	// URL with no path or one segment. Of the 38 addresses in `sites/`, 17 have two or more segments
	// or a trailing slash, and for every one of those the last rung of the chain was fetching a 404.
	private func getFavicon() async throws -> NSImage? {
		guard
			let faviconURL = URL(string: "/favicon.ico", relativeTo: url)
		else {
			return nil
		}

		return try await getImage(faviconURL)
	}

	private func getFromLPMetadataProvider(url: URL) async throws -> NSImage? {
		let metadata = try await LPMetadataProvider().startFetchingMetadata(for: url)

		guard
			let iconProvider = metadata.iconProvider,
			iconProvider.hasItemConforming(to: .image)
		else {
			return nil
		}

		return await iconProvider.getImage()
	}

	// TODO: This is moot as the class is marked as `@MainActor`, but we keep it for now just in case.
	@MainActor
	private func getFromManifest() async throws -> NSImage? {
		let code =
			"""
			document.querySelector('link[rel="manifest"]').href
			"""

		let result = try await webView.evaluateJavaScript(code, contentWorld: .defaultClient)

		guard
			let urlString = result as? String,
			let url = URL(string: urlString)
		else {
			return nil
		}

		let (data, _) = try await URLSession.shared.data(from: url)

		guard
			let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
			let icons = json["icons"] as? [[String: String]]
		else {
			return nil
		}

		let iconStructs = icons.compactMap { WebAppManifestIcon($0) }

		// TODO: Instead of picking the largest one, we should download all and add them as representations to a single `NSImage`.
		guard
			let largestIcon = (iconStructs.max { ($0.size?.width ?? 0) < ($1.size?.width ?? 0) })
		else {
			return nil
		}

		return try await getImage(largestIcon.url)
	}

	@MainActor
	private func getFromLinkIcon() async throws -> NSImage? {
		// TODO: There can be multiple of this one, some with larger sizes specified in a `sizes` prop.
		// The `~` is because of the `shortcut` link type, which is often seen before icon, but this link type is non-conforming, ignored and web authors must not use it anymore: https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types
		let code =
			"""
			document.querySelector('link[rel~="icon"]').href
			"""

		let result = try await webView.evaluateJavaScript(code, contentWorld: .defaultClient)

		guard
			let urlString = result as? String,
			let url = URL(string: urlString)
		else {
			return nil
		}

		return try await getImage(url)
	}

	@MainActor
	private func getFromMetaItemPropImage() async throws -> NSImage? {
		let code =
			"""
			new URL(document.querySelector('meta[itemprop="image"]').content, document.baseURI).toString()
			"""

		let result = try await webView.evaluateJavaScript(code, contentWorld: .defaultClient)

		guard
			let urlString = result as? String,
			let url = URL(string: urlString)
		else {
			return nil
		}

		return try await getImage(url)
	}

	@MainActor
	private func fetch(for url: URL) async throws -> NSImage? {
		self.url = url

		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData

		try await loadAndWait(request)

		// TODO: Use `??` for all of these when `??` supports await.

		if let image = try? await getFromLPMetadataProvider(url: url) {
			return image
		}

		if let image = try? await getFromManifest() {
			return image
		}

		if let image = try? await getFromMetaItemPropImage() {
			return image
		}

		if let image = try? await getFromLinkIcon() {
			return image
		}

		if let image = try? await getFavicon() {
			return image
		}

		return nil
	}
}

extension WebsiteIconFetcher: WKNavigationDelegate {
	func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
		navigationResponse.isForMainFrame ? .allow : .cancel
	}

	// All three go through `end`, which is where the argument for that is. These delegate methods can
	// be called more than once for one load, and by then the wait may also have been ended by the
	// ceiling or by cancellation.
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		end(.success(()))
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		end(.failure(error))
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		end(.failure(error))
	}
}
