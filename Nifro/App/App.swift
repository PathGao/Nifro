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
				await DiskBudget.removeOrphanedStores(keeping: Set(Defaults[.websites].map(\.id)))
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
