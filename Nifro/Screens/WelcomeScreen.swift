import Cocoa

extension AppState {
	func showWelcomeScreenIfNeeded() {
		guard SSApp.isFirstLaunch else {
			return
		}

		SSApp.forceActivate()

		NSAlert.showModal(
			title: String(localized: "Welcome to Nifro!"),
			message:
				"""
				Nifro lives in the menu bar, towards the right of the screen. Click its icon and choose “Add Website…” to get started.

				Use “Browsing Mode” when you need to log into a site or interact with it. Everything you do there is remembered, so you only have to sign in once.

				Not sure what to put up there? “Site Gallery…” in the same menu lists pages that work well as wallpapers, each with the settings that make it work.
				""",
			buttonTitles: [
				String(localized: "Continue")
			],
			defaultButtonIndex: -1
		)

		NSAlert.showModal(
			title: String(localized: "Feedback Welcome"),
			message:
				"""
				Nifro is open source and its issue tracker is open. If something is broken, missing, or just annoying, the feedback button in the app goes straight there.
				""",
			buttonTitles: [
				String(localized: "Get Started with Nifro")
			]
		)

		// Does not work on macOS 11 or later.
//		statusItemButton.playRainbowAnimation()

		delay(.seconds(1)) { [self] in
			statusItemButton.performClick(nil)
		}
	}
}
