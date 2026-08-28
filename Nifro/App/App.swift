import SwiftUI

// TODO macOS 16:
// - Use `MenuBarExtra` and afterwards switch to `@Observable`.
// - Remove `Combine` and `Defaults.publisher` usage.
// - Remove `ensureRunning()` from some intents that don't require Nifro to stay open.
// - Focus filter support.
// - Use SwiftUI for the desktop window and the web view.

@main
private struct AppMain: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
	@StateObject private var appState = AppState.shared

	init() {
		setUpConfig()
	}

	var body: some Scene {
		Window("Websites", id: "websites") {
			WebsitesScreen()
				.environmentObject(appState)
		}
		.windowToolbarStyle(.unifiedCompact)
		.windowResizability(.contentSize)
		.defaultPosition(.center)
		.defaultLaunchBehavior(.suppressed)
		Window("Site Gallery", id: "site-gallery") {
			SiteGalleryScreen()
				.environmentObject(appState)
		}
		.windowResizability(.contentSize)
		.defaultPosition(.center)
		.defaultLaunchBehavior(.suppressed)

		Settings {
			SettingsScreen()
				.environmentObject(appState)
		}
	}

	private func setUpConfig() {
		// First, and it has to be: CFBundle resolves this app's language on the first string anything
		// asks for and caches it for the life of the process. Nifro is English until somebody picks
		// otherwise, and the only way to say so is to have written it down before that first lookup.
		// Everything below this line is capable of asking.
		Localization.applyDefaultIfUnset()

		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true
		])

		SSApp.setUpExternalEventListeners()
		ProcessInfo.processInfo.disableAutomaticTermination("")
		ProcessInfo.processInfo.disableSuddenTermination()
	}
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
	// Without this, Nifro quits when the screen is locked. (macOS 13.2)
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

	// Every `nifro:` URL arrives here, including the one that started the app: AppKit holds the launch
	// event until the delegate is in place, and `@NSApplicationDelegateAdaptor` puts it there before
	// the app finishes launching. Nothing has to be subscribed early any more.
	func application(_ application: NSApplication, open urls: [URL]) {
		for url in urls {
			AppState.shared.handleURLCommand(url)
		}
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		// On a timer and not only at launch: this app is started at login and then left alone for
		// weeks, so a check that runs once per launch is a check that mostly does not run.
		Task {
			while !Task.isCancelled {
				// The playlists, which are the whole of the list now. A store is filed under `website.id`
				// and so is everything a page remembers, and both sweeps delete what no website claims —
				// deleting a store signs the user out of that site with nothing able to put it back. This
				// used to be a union with the `websites` key while both were live; that key is read only
				// by the migration now, and keeping it in the union would preserve stores for websites
				// the user has since deleted, for good.
				let websites = Defaults[.playlists].flatMap(\.websites)
				let websiteIDs = Set(websites.map(\.id))

				await DiskBudget.removeOrphanedStores(keeping: websiteIDs)

				// The same set, because a page record whose website is gone is exactly a store whose
				// website is gone — and it is what clears out the records of every build that keyed them
				// by address.
				AppState.shared.forgetOrphanedPageRecords(keeping: websiteIDs)

				// A third sweep over the same list, keyed differently because the thumbnail cache is:
				// its files are named for a website's address, so it also has to collect the file left
				// behind by an address that was *edited*, which is not an event the two sweeps above
				// can see at all. Nothing else ever removed one — the button that clears every
				// thumbnail also signs the user out of every site, so it is not cleanup anybody
				// reaches for, and a thumbnail nothing can ask for again sat in the container until
				// the app was uninstalled.
				//
				// Here rather than at the places a website changes. Deleting is one route, editing the
				// address is a second, and accepting a redirect is a third with no button on it at
				// all; all three end in this one list, which is why the other two sweeps read it here
				// too. A hook per route is three places to remember and a fourth route away from being
				// wrong again.
				WebsitesController.shared.thumbnailCache.removeImages(
					notMatching: Set(websites.map(\.thumbnailCacheKey))
				)

				await DiskBudget.enforce()
				try? await Task.sleep(for: .seconds(6 * 60 * 60))
			}
		}

		// Daily, which is Sparkle's default and what macOS apps have settled on. Written down rather
		// than acted on: the panel's footer reads it the next time it is opened.
		Task {
			while !Task.isCancelled {
				// Read each time round rather than captured, so turning it off stops the next check
				// instead of the one after a relaunch. The loop keeps its own rhythm either way.
				if Defaults[.checksForUpdatesAutomatically] {
					await AppState.shared.refreshLatestKnownVersion()
				}

				try? await Task.sleep(for: .seconds(UpdateCheck.interval))
			}
		}
	}

	// This is only run when the app is started when it's already running.
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		AppState.shared.handleMenuBarIcon()
		return false
	}
}
