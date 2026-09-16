import AppKit

/**
Fades the wallpaper back while you are working in another app.

Asked for in the context of Stage Manager, where the desktop is a place you switch to rather than something permanently behind everything. It helps anywhere. A page bright enough to enjoy when you look at it is often too loud behind a document you are reading.

"Focused" here means the Finder is frontmost, which is what clicking the desktop does. Any other app in front counts as not focused.
*/
extension AppState {
	private static let finderBundleIdentifier = "com.apple.finder"

	private var isDesktopFocused: Bool {
		NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleIdentifier
	}

	/**
	The opacity the wallpaper on `display` should currently have.

	Per display, because Browsing Mode is. This was the last piece of the mode that answered for the
	whole app while the thing it feeds — `applyOpacity` — ran per scene, so browsing on one screen
	pushed every screen to full strength. Measured at opacity 0.4 on two displays: browsing on the
	built-in raised the built-in correctly, and raised the external's window to alpha 1.0 while it
	stayed at desktop level, behind everything, brighter than the user had asked for and with no
	reason on screen for why. Dimming while another app is in front went with it on both.

	The window *level* had always been per display. Only this was not, which is why the wrong screen
	changed brightness without changing behaviour.
	*/
	func targetOpacity(on display: Display?) -> Double {
		if isBrowsingMode(on: display) {
			return 1
		}

		let base = Defaults[.opacity]

		guard
			Defaults[.dimWhenUnfocused],
			!isDesktopFocused
		else {
			return base
		}

		return base * Defaults[.dimmedOpacityFactor]
	}
}
