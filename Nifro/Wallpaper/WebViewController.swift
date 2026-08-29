import Cocoa
@preconcurrency import Combine
import WebKit

// Not an `NSViewController`, though it was one for as long as it has existed. Nothing ever read its
// `view`: the scene takes the page off `webView` and installs that, so `loadView` never ran and the
// slot was only ever written to. What it did do is hold a second strong reference to the live web
// view — the very thing `releaseWebView` exists to drop, which is why that method had to clear the
// slot before it could work at all.
@MainActor
final class WebViewController: NSObject {
	/**
	The scene this controller draws into. Weak because the scene owns the controller.
	*/
	weak var scene: WallpaperScene?

	private let didLoadSubject = PassthroughSubject<Void, Error>()

	/**
	Where each download still in flight is being written.

	Keyed on the download, because the download is what a destination belongs to and one controller is
	the delegate for every download a display starts. A single slot held the last destination decided
	rather than the destination of the download that was finishing: two at once, and the second one's
	path was handed to the first one's completion, so the Dock bounced at a file that had not arrived
	while the one that had went unannounced.

	`ObjectIdentifier` rather than the `WKDownload` itself, so that an entry nothing ever comes back
	for costs a `URL` instead of pinning a download and its connection open for the rest of the
	session. The address cannot be misread after it is reused: an entry is only ever read for the
	download that wrote it, and the write happens before the download starts.
	*/
	private var downloadDestinations = [ObjectIdentifier: URL]()

	/**
	Whether a download this page is starting is one somebody asked for.

	Downloads were left out of the conversion that put the four `WKUIDelegate` panels behind Browsing
	Mode, and they need it more than those four do: a refused panel is a dialog nobody sees, while a
	download writes a file into the user's Downloads folder and bounces the Dock. The three explicit
	download items are already taken out of the page's context menu, so until this guard the only
	downloads the app could perform were the ones nobody asked for — including the response path, which
	needs no click at all: a wallpaper that navigates itself to something WebKit cannot display started
	a download on a screen nobody was looking at.

	*This display's* Browsing Mode, like the four panels. Browsing one screen is not consent for a page
	on another screen to write to disk.
	*/
	private var isDownloadWanted: Bool {
		AppState.shared.isBrowsingMode(on: scene?.display)
	}

	/**
	Publishes when the web view finishes loading a page.
	*/
	lazy var didLoadPublisher = didLoadSubject.eraseToAnyPublisher()

	/**
	Build a web view for this scene: the live one, its replacement while a new page loads out of sight,
	and the empty one that takes over when the page is dropped.
	*/
	func createWebView() -> SSWebView {
		let configuration = WKWebViewConfiguration()
		configuration.allowsAirPlayForMediaPlayback = false

		// Its own store, so deleting the website deletes what the website wrote. Read here for the same
		// reason everything else below is: this web view belongs to one website for its whole life, and
		// a new one is built when the website changes.
		//
		// Read once and kept on the view, because the scroll position, the remembered fragment and the
		// zoom level are keyed on this same `id` — the store and the records have to name the same
		// website or two entries on one address end up sharing one of the two.
		let websiteID = scene?.website?.id

		if let websiteID {
			configuration.websiteDataStore = DiskBudget.store(for: websiteID)
		}

		// A wallpaper has nobody to click play. The macOS default happens to allow this, but the
		// header documents no default, and this is now load-bearing for the embedded players.
		configuration.mediaTypesRequiringUserActionForPlayback = []

		// TODO: Enable this again once the first load of a session stops showing a block of grey while
		// it waits. Suppressing incremental rendering makes that wait longer and more visible, and the
		// first load is the one path with nothing already on screen to protect it.
//		configuration.suppressesIncrementalRendering = true

		let userContentController = WKUserContentController()
		configuration.userContentController = userContentController
		configuration.applyContentRules()

		let preferences = WKPreferences()
		preferences.javaScriptCanOpenWindowsAutomatically = false
		// A wallpaper is already the size of the screen, so a page's fullscreen button has nothing to
		// offer, and taking it breaks the wallpaper: WebKit moves the web view into a window of its
		// own, while the visibility policy carries on reinstalling the content view every couple of
		// seconds. Coming back out then finds nowhere to come back to, and the wallpaper is black
		// with no way to fix it from inside the app.
		preferences.isElementFullscreenEnabled = false
		configuration.preferences = preferences

		let webView = SSWebView(frame: .zero, configuration: configuration)
		webView.scene = scene
		webView.websiteID = websiteID

		// The only place a title is recorded, and enough on its own. `didFinish` used to read the same
		// property a second time, for the reason this sink is here: a single-page app loads with a
		// placeholder title and sets the real one from script a moment later, which is a title change
		// after the load finished, not before it. WebKit clears the title on every main-frame commit
		// and posts the real one after, so there is no title the load callback could see that this has
		// not already been handed.
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
		// A wallpaper has no window to open the inspector from, so attaching Safari's Develop menu to it
		// is the only way to see what a page is doing.
		webView.isInspectable = true

		userContentController.addJavaScript("document.documentElement.classList.add('is-nifro-app')")
		userContentController.installAudioControl()

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
		}

		// Hidden from birth. A fresh web view is a blank page, and showing one is a flash of white
		// before the wallpaper and, since the menu bar band follows the page, a menu bar that changes
		// colour ahead of it. Whoever loads something is the one that shows it.
		webView.isHidden = true

		return webView
	}

	/**
	Take a finished replacement as the live web view.
	*/
	func adopt(_ replacement: SSWebView) {
		webView = replacement
	}

	/**
	Drop the live page and the process behind it.

	Upstream left a TODO here and settled for `about:blank` plus hiding the window, which keeps a WebContent process and its memory alive for as long as the app runs. Replacing the web view with a fresh, unloaded one releases the last reference to the old one, and its process exits with it.
	*/
	func releaseWebView() {
		webView = createWebView()
	}

	private(set) lazy var webView = createWebView()

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

		// Holding Command or Option sends a link to the default browser whatever the settings say. That matches other Mac apps with an embedded web view, and it is the only way to open a same-site link externally without changing a setting first.
		if
			navigationAction.navigationType == .linkActivated,
			!NSEvent.modifiers.isDisjoint(with: [.command, .option]),
			let newURL = navigationAction.request.url
		{
			// This display's own Browsing Mode: opening a link in the browser should put back the screen
			// the link was on, not every screen.
			if AppState.shared.isBrowsingMode(on: scene?.display), Defaults[.bringBrowsingModeToFront] {
				AppState.shared.setBrowsingMode(false, on: scene?.display)
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
			scene?.website?.opensExternalLinksInBrowser ?? Defaults[.openExternalLinksInBrowser],
			navigationAction.navigationType == .linkActivated,
			let siteHost,
			let newURL = navigationAction.request.url,
			siteHost != newURL.host
		{
			// Hide Nifro if it's in front of everything.
			// This display's own Browsing Mode: opening a link in the browser should put back the screen
			// the link was on, not every screen.
			if AppState.shared.isBrowsingMode(on: scene?.display), Defaults[.bringBrowsingModeToFront] {
				AppState.shared.setBrowsingMode(false, on: scene?.display)
			}

			newURL.open()

			return .cancel
		}

		if navigationAction.shouldPerformDownload {
			return isDownloadWanted ? .download : .cancel
		}

		// Fix signing into Google Account. Google has some stupid protection against fake user agents for "accounts.google.com" and "docs.google.com".
		//
		// Main frame only. The user agent belongs to the web view, not to the frame being navigated,
		// so a page that loads anything at all from a Google host in a subframe — which a YouTube
		// player does, for consent and for ads — used to blank the user agent for the whole page and
		// everything it loaded afterwards.
		if
			navigationAction.targetFrame?.isMainFrame == true,
			let url = navigationAction.request.url,
			// An address with no host is not a site to decide anything about, and the user agent stays
			// whatever the last real navigation made it.
			url.host != nil
		{
			webView.customUserAgent = url.hasDomain("google.com") ? "" : SSWebView.safariUserAgent
		}

		return .allow
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
		// Onto the web view this response is for, not onto the controller: see `responseMIMEType`.
		// Assigned whatever the cast gives, including nothing, so that a main frame answered by
		// something other than an `HTTPURLResponse` says so rather than leaving the previous answer in
		// place — which is the same rule the clear on the way in enforces, in the one case that reaches
		// here.
		if navigationResponse.isForMainFrame {
			(webView as? SSWebView)?.responseMIMEType = (navigationResponse.response as? HTTPURLResponse)?.mimeType
		}

		if navigationResponse.canShowMIMEType {
			return .allow
		}

		return isDownloadWanted ? .download : .cancel
	}

	/**
	A new page is on its way into this web view, so nothing it is told is the last page's.

	Here rather than at the top of `decidePolicyFor navigationAction` for two reasons, and either
	one on its own would be enough. This runs for the main frame only, and the policy callback runs
	for every subframe too — so an image page with an advert in an iframe would clear the answer it
	had already been given. And this runs for loads the policy callback is not asked about at all,
	which includes the two that have no response of their own to replace what they find: a local
	folder and a framed player's host page.

	Before `decidePolicyFor navigationResponse` and long before `didFinish`, which is the whole
	order that makes a clear here safe.
	*/
	func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		(webView as? SSWebView)?.responseMIMEType = nil
	}

	/**
	The server sent us somewhere else.

	This is the one thing a URL comparison cannot tell apart from everything else that changes an
	address. A page that writes its own fragment as it is dragged, a dashboard that adds a tab to the
	query, a link followed in Browsing Mode — all of those end with `webView.url` different from the
	stored one, and none of them means the stored one is wrong. A redirect does: it will happen again
	on every launch, and the day the site stops redirecting the entry breaks.

	Recorded rather than acted on. Rewriting the address behind the user's back is how "Update Website
	to Current" once turned a website into a GitHub 404.
	*/
	func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
		guard
			let website = scene?.website,
			let destination = webView.url?.normalized(),
			website.url.normalized() != destination,
			// A framed player's host page is ours, and its address is not anywhere anybody went.
			VideoEmbed.hostPage(for: website.url) == nil
		else {
			return
		}

		Defaults[.redirectedAddresses][website.id.uuidString] = destination.absoluteString
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		// This web view's own answer, from the navigation that has just finished in it.
		webView.centerAndAspectFillImage(mimeType: (webView as? SSWebView)?.responseMIMEType)

		// The script starts every page muted and waits to be told. This is the telling.
		webView.setAudioMuted(!(scene?.shouldPlaySound ?? false))

		// The page is here, so this is the moment it goes on screen — not a fixed delay after asking for
		// it.
		pageDidSettle(webView)
		scene?.restorePageState(in: webView)

		internalOnLoaded(nil)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		pageDidSettle(webView)
		internalOnLoaded(error)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		pageDidSettle(webView)
		internalOnLoaded(error)
	}

	/**
	This scene's live page has stopped loading, whichever way it went, so it goes on screen.

	Two decisions that each used to sit at one call site now meet here.

	Which web view. The live page and a replacement loading out of sight both report through this one
	delegate, and the reveal was taken from either of them. Measured on a cold launch: the
	replacement finished first and unhid the live web view, which was still loading — so the
	wallpaper went up half-painted, and the page that had actually finished only reached the screen
	seconds later. A replacement gets there through `adopt`, which reveals and re-samples on its own;
	nothing about one should touch what is on screen before then.

	Which outcome. A load that fails leaves the desktop showing nothing for exactly as long as one
	that hangs, and only the backstop timer ever put that right — thirty seconds now, with the panel
	reporting the display as loading for all of it. A page that has stopped loading is as finished as
	it is going to get, so it is shown.

	The band is re-sampled beside the reveal rather than left to it: `revealPage` refreshes the band,
	but it does nothing at all once the page is up, and a reload is a page that is already up with
	new content on it.
	*/
	private func pageDidSettle(_ webView: WKWebView) {
		guard webView === self.webView else {
			return
		}

		scene?.revealPage()
		scene?.refreshMenuBarBandColor()
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

	*This display's* Browsing Mode, like the three panels below it. Asked of the app, browsing one
	screen let every other screen's page open windows, raise confirms and prompts and put up a file
	picker — pages nobody had clicked anything on, which is the whole of what the permission rests on.
	*/
	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		guard
			AppState.shared.isBrowsingMode(on: scene?.display),
			navigationAction.targetFrame == nil
		else {
			return nil
		}

		webView.load(navigationAction.request)

		return nil
	}

	func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
		guard AppState.shared.isBrowsingMode(on: scene?.display) else {
			return false
		}

		return await webView.defaultConfirmHandler(message: message)
	}

	func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
		guard AppState.shared.isBrowsingMode(on: scene?.display) else {
			return nil
		}

		return await webView.defaultPromptHandler(prompt: prompt, defaultText: defaultText)
	}

	// swiftlint:disable:next discouraged_optional_collection
	func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
		guard AppState.shared.isBrowsingMode(on: scene?.display) else {
			return nil
		}

		return await webView.defaultUploadPanelHandler(parameters: parameters)
	}
}

extension WebViewController: WKDownloadDelegate {
	func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
		let url = URL.downloadsDirectory.appendingPathComponent(suggestedFilename).incrementalFilename()
		downloadDestinations[ObjectIdentifier(download)] = url
		return url
	}

	/**
	One of the two endings, and it takes its entry out on the way past.

	Taken rather than read. A map that is only ever written to is not a fix for a slot that was only
	ever written to — it is the same defect with a bigger footprint, and the entry has nothing left to
	say once the download it belongs to has ended.
	*/
	func downloadDidFinish(_ download: WKDownload) {
		guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else {
			return
		}

		NSWorkspace.shared.bounceDownloadsFolderInDock(for: destination)
	}

	/**
	The other ending, and the only other one there is.

	`WKDownloadDelegate` has exactly two terminal callbacks, and a cancelled download arrives at this
	one — there is no third way out for the app to miss, because nothing in the app holds a
	`WKDownload` to cancel it with. Clearing here as well as on success is what keeps the map to the
	downloads actually in flight.
	*/
	func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
		downloadDestinations[ObjectIdentifier(download)] = nil
		error.presentAsModal()
	}
}
