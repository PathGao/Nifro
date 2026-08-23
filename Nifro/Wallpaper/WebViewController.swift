import Cocoa
@preconcurrency import Combine
import WebKit

final class WebViewController: NSViewController {
	/**
	The scene this controller draws into. Weak because the scene owns the controller.
	*/
	weak var scene: WallpaperScene?

	private var popupWindow: NSWindow?
	private let didLoadSubject = PassthroughSubject<Void, Error>()
	private var currentDownloadFile: URL?

	/**
	Publishes when the web view finishes loading a page.
	*/
	lazy var didLoadPublisher = didLoadSubject.eraseToAnyPublisher()

	var response: HTTPURLResponse?

	private func createWebView() -> SSWebView {
		let configuration = WKWebViewConfiguration()
		configuration.allowsAirPlayForMediaPlayback = false

		// A wallpaper has nobody to click play. The macOS default happens to allow this, but the
		// header documents no default, and this is now load-bearing for the embedded players.
		configuration.mediaTypesRequiringUserActionForPlayback = []
		configuration.applicationNameForUserAgent = "\(SSApp.name)/\(SSApp.version)"

		// TODO: Enable this again when https://github.com/sindresorhus/Plash/issues/9 is fixed.
//		configuration.suppressesIncrementalRendering = true

		let userContentController = WKUserContentController()
		configuration.userContentController = userContentController
		configuration.applyContentRules()

		// Only worth carrying when something is going to read it.
		if let scene, scene.website?.rendering == .automatic {
			userContentController.add(ActivityMessageProxy(scene: scene), name: ActivityWatcher.messageName)
			userContentController.addUserScript(
				WKUserScript(
					source: ActivityWatcher.script,
					injectionTime: .atDocumentEnd,
					forMainFrameOnly: true,
					in: .page
				)
			)
		}



		let preferences = WKPreferences()
		preferences.javaScriptCanOpenWindowsAutomatically = false
		preferences.isDeveloperExtrasEnabled = true
		preferences.isElementFullscreenEnabled = true
		configuration.preferences = preferences

		let webView = SSWebView(frame: .zero, configuration: configuration)

		webView.publisher(for: \.title)
			.sink { [weak webView] title in
				guard let webView else {
					return
				}

				WebsitesController.shared.recordObservedTitle(title ?? "", for: webView.url)
			}
			.store(forTheLifetimeOf: webView)

		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.allowsBackForwardNavigationGestures = true
		webView.allowsMagnification = true
		webView.customUserAgent = SSWebView.safariUserAgent
		webView.drawsBackground = false

		userContentController.addJavaScript("document.documentElement.classList.add('is-nifro-app', 'is-plash-app')")

		if let website = WebsitesController.shared.current {
			if website.audio == .muted {
				userContentController.muteAudio()
			}

			if website.invertColors2 != .never {
				userContentController.invertColors(
					onlyWhenInDarkMode: website.invertColors2 == .darkMode
				)
			}

			if website.usePrintStyles {
				webView.mediaType = "print"
			}

			// An untouched starter template is all comments. Injecting it would add an empty style element to every page for nothing.
			if
				!website.css.trimmed.isEmpty,
				website.css != Website.starterCSS
			{
				userContentController.addCSS(website.css)
			}

			if
				!website.javaScript.trimmed.isEmpty,
				website.javaScript != Website.starterJavaScript
			{
				userContentController.addJavaScript(
					"""
					try {
						\(website.javaScript)
					} catch (error) {
						alert(`Custom JavaScript threw an error:\n\n${error}`);
						throw error;
					}
					"""
				)
			}

			// Google Sheets shows an error message when we use the Safari or Chrome user agent.
			if website.url.hasDomain("google.com") {
				webView.customUserAgent = ""
			}
		}

		return webView
	}

	/**
	A second web view, configured exactly like the live one, for loading a replacement page out of sight.
	*/
	func makeReplacementWebView() -> SSWebView {
		createWebView()
	}

	/**
	Take a finished replacement as the live web view.
	*/
	func adopt(_ replacement: SSWebView) {
		webView = replacement
		view = replacement
	}

	/**
	Drop the live page and the process behind it.

	Upstream left a TODO here and settled for `about:blank` plus hiding the window, which keeps a WebContent process and its memory alive for as long as the app runs. Replacing the web view with a fresh, unloaded one releases the last reference to the old one, and its process exits with it.
	*/
	func releaseWebView() {
		view = NSView()
		webView = createWebView()
	}

	func recreateWebView() {
		webView = createWebView()
		view = webView
	}

	private(set) lazy var webView = createWebView()

	override func loadView() {
		view = webView
	}

	// TODO: When Swift 6 is out, make this async and throw instead of using `onLoaded` handler.
	func loadURL(_ url: URL) {
		guard !url.isFileURL else {
			_ = url.accessSandboxedURLByPromptingIfNeeded()
			webView.loadFileURL(url.appendingPathComponent("index.html", isDirectory: false), allowingReadAccessTo: url)

			return
		}

		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		webView.load(request)
	}

	private func internalOnLoaded(_ error: Error?) {
		// TODO: A minor improvement would be to inject this on `DOMContentLoaded` using `WKScriptMessageHandler`.
		webView.toggleBrowsingModeClass()

		if let error {
			guard !WKWebView.canIgnoreError(error) else {
				didLoadSubject.send()
				return
			}

			didLoadSubject.send(completion: .failure(error))
			return
		}

		didLoadSubject.send()
	}
}

extension WebViewController: WKNavigationDelegate {
	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
		// Holding Command or Option sends a link to the default browser whatever the settings say. That matches other Mac apps with an embedded web view, and it is the only way to open a same-site link externally without changing a setting first. Plash#140.
		if
			navigationAction.navigationType == .linkActivated,
			!NSEvent.modifiers.intersection([.command, .option]).isEmpty,
			let newURL = navigationAction.request.url
		{
			if Defaults[.isBrowsingMode], Defaults[.bringBrowsingModeToFront] {
				Defaults[.isBrowsingMode] = false
			}

			newURL.open()

			return .cancel
		}

		if
			Defaults[.openExternalLinksInBrowser],
			navigationAction.navigationType == .linkActivated,
			let originalURL = webView.url,
			let newURL = navigationAction.request.url,
			originalURL.host != newURL.host
		{
			// Hide Nifro if it's in front of everything.
			if Defaults[.isBrowsingMode], Defaults[.bringBrowsingModeToFront] {
				Defaults[.isBrowsingMode] = false
			}

			newURL.open()

			return .cancel
		}

		if navigationAction.shouldPerformDownload {
			return .download
		}

		// Fix signing into Google Account. Google has some stupid protection against fake user agents for "accounts.google.com" and "docs.google.com".
		if let host = navigationAction.request.url?.host {
			let useBlankUserAgent = host == "google.com" || host.hasSuffix(".google.com")
			webView.customUserAgent = useBlankUserAgent ? "" : SSWebView.safariUserAgent
		}

		return .allow
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
		if
			navigationResponse.isForMainFrame,
			let response = navigationResponse.response as? HTTPURLResponse
		{
			self.response = response
		}

		return navigationResponse.canShowMIMEType ? .allow : .download
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		webView.centerAndAspectFillImage(mimeType: response?.mimeType)

		recordTitleIfNeeded(from: webView)
		scene?.refreshMenuBarBandColor()
		scene?.restoreScrollPosition(in: webView)

		internalOnLoaded(nil)
	}

	/**
	Fill in a missing website title from the page that just loaded.

	Also worth doing on later title changes. Single-page apps often load with an empty or placeholder title and set the real one from script a moment later.
	*/
	private func recordTitleIfNeeded(from webView: WKWebView) {
		WebsitesController.shared.recordObservedTitle(webView.title ?? "", for: webView.url)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		internalOnLoaded(error)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		internalOnLoaded(error)
	}

	func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
		// We're intentionally allowing this in non-browsing mode as loading the URL would fail otherwise.
		await webView.defaultAuthChallengeHandler(
			challenge: challenge,
			allowSelfSignedCertificate: WebsitesController.shared.current?.allowSelfSignedCertificate ?? false
		)
	}

	func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
		download.delegate = self
	}

	func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
		download.delegate = self
	}
}

extension WebViewController: WKUIDelegate {
	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		guard
			AppState.shared.isBrowsingMode,
			NSEvent.modifiers != .option
		else {
			// This makes it so that requests to open something in a new window just opens in the existing web view.
			if navigationAction.targetFrame == nil {
				webView.load(navigationAction.request)
			}

			return nil
		}

		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.customUserAgent = WKWebView.safariUserAgent

		var styleMask: NSWindow.StyleMask = [
			.titled,
			.closable,
			.resizable
		]

		// We default the window to be resizable to make it user-friendly.
		if windowFeatures.allowsResizing?.boolValue == false {
			styleMask.remove(.resizable)
		}

		let window = NSWindow(
			contentRect: CGRect(origin: .zero, size: windowFeatures.size),
			styleMask: styleMask,
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false // Since we manually release it.
		window.contentView = webView
		view.window?.addChildWindow(window, ordered: .above)
		window.center()
		window.makeKeyAndOrderFront(self)
		popupWindow = window

		webView.bind(\.title, to: window, at: \.title, default: "")
			.store(forTheLifetimeOf: webView)

		return webView
	}


	func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
		guard AppState.shared.isBrowsingMode else {
			return false
		}

		return await webView.defaultConfirmHandler(message: message)
	}

	func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
		guard AppState.shared.isBrowsingMode else {
			return nil
		}

		return await webView.defaultPromptHandler(prompt: prompt, defaultText: defaultText)
	}

	// swiftlint:disable:next discouraged_optional_collection
	func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
		guard AppState.shared.isBrowsingMode else {
			return nil
		}

		return await webView.defaultUploadPanelHandler(parameters: parameters)
	}

	func webViewDidClose(_ webView: WKWebView) {
		if webView.window == popupWindow {
			popupWindow?.close()
			popupWindow = nil
		}
	}
}

extension WebViewController: WKDownloadDelegate {
	func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
		let url = URL.downloadsDirectory.appendingPathComponent(suggestedFilename).incrementalFilename()
		currentDownloadFile = url
		return url
	}

	func downloadDidFinish(_ download: WKDownload) {
		guard let currentDownloadFile else {
			return
		}

		NSWorkspace.shared.bounceDownloadsFolderInDock(for: currentDownloadFile)
	}

	func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
		error.presentAsModal()
	}
}
