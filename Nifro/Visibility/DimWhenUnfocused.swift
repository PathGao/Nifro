import AppKit

/**
Fades the wallpaper back while you are working in another app.

Asked for in the context of Stage Manager, where the desktop is a place you switch to rather than something permanently behind everything (Plash#177). It helps anywhere. A page bright enough to enjoy when you look at it is often too loud behind a document you are reading.

"Focused" here means the Finder is frontmost, which is what clicking the desktop does. Any other app in front counts as not focused.
*/
extension AppState {
	private static let finderBundleIdentifier = "com.apple.finder"

	var isDesktopFocused: Bool {
		NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleIdentifier
	}

	/**
	The opacity the wallpaper should currently have.
	*/
	var targetOpacity: Double {
		if isBrowsingMode {
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
