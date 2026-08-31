/**
The one process-lifetime choice that makes WebKit element fullscreen safe or available.

It deliberately has no knowledge of `Defaults`, AppKit or a web view. Those are consumers of the
choice; keeping the value itself plain lets the address transformation be tested with no app bundle
or window server.
*/
enum FullscreenCompatibility: Sendable {
	case wallpaper
	case compatibility

	init(isEnabled: Bool) {
		self = isEnabled ? .compatibility : .wallpaper
	}

	var isElementFullscreenEnabled: Bool {
		self == .compatibility
	}

	var hidesYouTubeFullscreenControl: Bool {
		self == .wallpaper
	}
}
