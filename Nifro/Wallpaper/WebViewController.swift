import Cocoa
@preconcurrency import Combine
import WebKit

final class WebViewController: NSViewController {
	/**
	The scene this controller draws into. Weak because the scene owns the controller.
	*/
	weak var scene: WallpaperScene?

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

		// Its own store, so deleting the website deletes what the website wrote. Read here for the same
		// reason everything else below is: this web view belongs to one website for its whole life, and
		// a new one is built when the website changes.
		if let id = scene?.website?.id {
			configuration.websiteDataStore = DiskBudget.store(for: id)
		}

		// A wallpaper has nobody to click play. The macOS default happens to allow this, but the
		// header documents no default, and this is now load-bearing for the embedded players.
		configuration.mediaTypesRequiringUserActionForPlayback = []
		configuration.applicationNameForUserAgent = "\(SSApp.name)/\(SSApp.version)"

		// TODO: Enable this again when https://github.com/sindresorhus/Plash/issues/9 is fixed.
//		configuration.suppressesIncrementalRendering = true

		let userContentController = WKUserContentController()
		configuration.userContentController = userContentController
		configuration.applyContentRules()

		let preferences = WKPreferences()
		preferences.javaScriptCanOpenWindowsAutomatically = false
		preferences.isDeveloperExtrasEnabled = true
		// A wallpaper is already the size of the screen, so a page's fullscreen button has nothing to
		// offer, and taking it breaks the wallpaper: WebKit moves the web view into a window of its
		// own, while the visibility policy carries on reinstalling the content view every couple of
		// seconds. Coming back out then finds nowhere to come back to, and the wallpaper is black
		// with no way to fix it from inside the app.
		preferences.isElementFullscreenEnabled = false
		configuration.preferences = preferences

		let webView = SSWebView(frame: .zero, configuration: configuration)
		webView.scene = scene

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
		userContentController.installAudioControl()
		userContentController.installMediaClock()

		// This scene's website, not the list-wide current one. Everything below is baked into the web
		// view when it is created and never revisited, so reading the wrong website here put one
		// display's custom CSS, custom JavaScript and inverted colours on another display's page for
		// as long as that page was up.
		if let website = scene?.website {
			if website.invertColors2 != .never {
				userContentController.invertColors(
					onlyWhenInDarkMode: website.invertColors2 == .darkMode
				)
			}

			if website.usePrintStyles {
				webView.mediaType = "print"
			}

			if let css = website.customCSS {
				userContentController.addCSS(css)
			}

			if let javaScript = website.customJavaScript {
				userContentController.addJavaScript(
					"""
					try {
						\(javaScript)
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

		// Hidden from birth. A fresh web view is a blank page, and showing one is a flash of white
		// before the wallpaper and, since the menu bar band follows the page, a menu bar that changes
		// colour ahead of it. Whoever loads something is the one that shows it.
		webView.isHidden = true

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

	private(set) lazy var webView = createWebView()

	override func loadView() {
		view = webView
	}

	// TODO: When Swift 6 is out, make this async and throw instead of using `onLoaded` handler.
	func loadURL(_ url: URL) {
		webView.loadWallpaper(url)
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
		// An address that has to be framed by a page must never become the page. YouTube's player
		// answers "error 153, player configuration error" when it is the document rather than a frame
		// in one, and there are several ways to end up there by accident: a link that opens in a new
		// window, a script setting `top.location`, a reload of something that was already wrong. One
		// guard here covers all of them, because they all arrive as a main-frame navigation.
		if
			navigationAction.targetFrame?.isMainFrame == true,
			let url = navigationAction.request.url,
			VideoEmbed.hostPage(for: url) != nil
		{
			webView.loadWallpaper(url)
			return .cancel
		}

		// Holding Command or Option sends a link to the default browser whatever the settings say. That matches other Mac apps with an embedded web view, and it is the only way to open a same-site link externally without changing a setting first. Plash#140.
		if
			navigationAction.navigationType == .linkActivated,
			!NSEvent.modifiers.isDisjoint(with: [.command, .option]),
			let newURL = navigationAction.request.url
		{
			if Defaults[.isBrowsingMode], Defaults[.bringBrowsingModeToFront] {
				Defaults[.isBrowsingMode] = false
			}

			newURL.open()

			return .cancel
		}

		// Compared against the website's own address rather than the document's. They are the same
		// thing until the page needs a host page to be framed by, and then the document is the host
		// and every link on the page counts as leaving the site — so clicking anything in a framed
		// player opened a browser instead of doing what it does. Redirects move the document's
		// address too, with the same result.
		let siteHost = scene?.website?.url.host ?? webView.url?.host

		if
			Defaults[.openExternalLinksInBrowser],
			navigationAction.navigationType == .linkActivated,
			let siteHost,
			let newURL = navigationAction.request.url,
			siteHost != newURL.host
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
		//
		// Main frame only. The user agent belongs to the web view, not to the frame being navigated,
		// so a page that loads anything at all from a Google host in a subframe — which a YouTube
		// player does, for consent and for ads — used to blank the user agent for the whole page and
		// everything it loaded afterwards.
		if
			navigationAction.targetFrame?.isMainFrame == true,
			let host = navigationAction.request.url?.host
		{
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

		// The script starts every page muted and waits to be told. This is the telling.
		webView.setAudioMuted(scene?.website?.audio != .unmuted)

		recordTitleIfNeeded(from: webView)

		// The page is here, so this is the moment it goes on screen — not a fixed delay after asking for
		// it. `revealPage` refreshes the band itself, and does nothing if the page is already up.
		scene?.revealPage()
		scene?.refreshMenuBarBandColor()
		scene?.restorePageState(in: webView)

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
			allowSelfSignedCertificate: scene?.website?.allowSelfSignedCertificate ?? false
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
	/**
	Answers a page asking for a new window. Nifro never opens one.

	Nifro is a background. A window of its own is the opposite of that, and one built the usual way
	was worse than the general argument: an accessory app's window has no Dock icon, so a video that
	opened in it kept playing with nowhere to go back to — disabling the wallpaper did not reach it,
	and only quitting the app stopped the sound.

	Handing it to the user's browser is not the answer either. A site's own flows go through this:
	signing in, a player's controls, a confirmation step. Sent to a browser they complete somewhere
	else, and the wallpaper is still signed out.

	So it opens where the user is already looking. Only while they are browsing, because outside
	Browsing Mode nobody clicked anything, and a page moving the wallpaper on its own is not
	something to allow.
	*/
	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		guard
			AppState.shared.isBrowsingMode,
			navigationAction.targetFrame == nil
		else {
			return nil
		}

		webView.load(navigationAction.request)

		return nil
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
