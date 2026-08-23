import Foundation

/**
Whether a window on screen hides the wallpaper behind it.

Split out from the window-list handling and kept free of AppKit so the rules can be tested. They are
worth testing: the first version matched the system windows by the name the window list reports,
which is the *localised* application name. On an English Mac it worked. On any other, "Dock" never
matched 程序坞, the Dock's full-screen window counted as coverage, and every wallpaper was judged
completely hidden and frozen from the moment it appeared.
*/
enum Coverage {
	/**
	Applications whose windows do not hide the wallpaper, by bundle identifier.

	The Dock is the one that matters. It owns a window the size of the whole screen, and what it
	draws is translucent, so the page carries on showing through the strip it occupies. Counting that
	window as coverage throws away the entire wallpaper.
	*/
	static let ignoredBundleIdentifiers: Set<String> = [
		"com.apple.dock",
		"com.apple.controlcenter",
		"com.apple.notificationcenterui",
		"com.apple.Spotlight",
		"com.apple.WallpaperAgent"
	]

	/**
	Processes with no bundle identifier to match on, by the name the window list reports.

	Only for system processes that are not applications, whose names are not localised. Anything with
	a bundle identifier belongs in the set above instead.
	*/
	static let ignoredProcessNames: Set<String> = [
		"Window Server" // The menu bar, and various full-screen scaffolding.
	]

	/**
	Whether this window should be treated as hiding the wallpaper.

	- Parameter layer: the window's level. Below zero is the desktop, the desktop icons and the
	  wallpaper itself, none of which hide anything.
	- Parameter isOwnWindow: our own windows never count. The wallpaper cannot hide itself.
	*/
	static func hidesWallpaper(
		layer: Int,
		alpha: Double,
		bundleIdentifier: String?,
		processName: String?,
		isOwnWindow: Bool
	) -> Bool {
		guard
			!isOwnWindow,
			layer >= 0,
			alpha > 0.9
		else {
			return false
		}

		if let bundleIdentifier {
			return !ignoredBundleIdentifiers.contains(bundleIdentifier)
		}

		guard let processName else {
			return true
		}

		return !ignoredProcessNames.contains(processName)
	}
}
