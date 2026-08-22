import SwiftUI

/**
TODO macOS 16:
- Use `MenuBarExtra` and afterwards switch to `@Observable`.
- Remove `Combine` and `Defaults.publisher` usage.
- Remove `ensureRunning()` from some intents that don't require Nifro to stay open.
- Focus filter support.
- Use SwiftUI for the desktop window and the web view.
*/

@main
struct AppMain: App {
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
		Settings {
			SettingsScreen()
				.environmentObject(appState)
		}
	}

	private func setUpConfig() {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true
		])

		SSApp.setUpExternalEventListeners()
		ProcessInfo.processInfo.disableAutomaticTermination("")
		ProcessInfo.processInfo.disableSuddenTermination()
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	// Without this, Nifro quits when the screen is locked. (macOS 13.2)
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

	func applicationWillFinishLaunching(_ notification: Notification) {
		// It's important that this is here so it's registered in time.
		AppState.shared.setUpURLCommands()
	}

	// This is only run when the app is started when it's already running.
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		AppState.shared.handleAppReopen()
		return false
	}
}
