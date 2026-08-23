import Foundation

/**
Turns a video page URL into the address of its player and nothing else.

A YouTube or Bilibili page is mostly not the video. Navigation, a sidebar of recommendations and a
comment thread take up more of the screen than the thing you wanted on your wallpaper. The usual
answers are to hide the rest with CSS, crop the window down to the player, or drive the page's
fullscreen button with injected script. All three depend on the page's markup, so all three break
the next time the site is redesigned.

Both sites already publish an address where the page is the player. It is meant for embedding in
other people's pages, which is exactly the promise we want: it stays stable, and it arrives with no
chrome to hide.

Kept as plain string handling so the parsing can be tested without a network or a web view. Fullscreen
is not involved anywhere: the player fills the page, the page fills the window, the window is the
wallpaper.
*/
enum VideoEmbed {
	/**
	The player-only address for `url`, or `nil` if this is not a video page we recognise.

	The address asks the player to start and says nothing about sound. Whether a website is muted is
	a setting on that website, changed long after this URL was produced and stored, so a `mute`
	parameter baked in here would be a second answer to the same question and would win — the
	website could be set to play audio and stay silent. The mute script runs at document start and
	watches for elements the player inserts later, so the setting is enforced without the URL's help.

	`WKWebView` is configured with no user-gesture requirement for playback, so autoplay works here
	whether or not there is sound. That is not true of a normal browser tab.
	*/
	static func playerURL(for url: URL) -> URL? {
		guard let host = url.host?.lowercased() else {
			return nil
		}

		if let identifier = youTubeVideoID(url: url, host: host) {
			return URL(string: "https://www.youtube.com/embed/\(identifier)?autoplay=1&playsinline=1")
		}

		if let identifier = bilibiliVideoID(url: url, host: host) {
			// Danmaku is the scrolling comment overlay. On a wallpaper it is text moving across the
			// picture that nobody is reading.
			return URL(string: "https://player.bilibili.com/player.html?bvid=\(identifier)&autoplay=1&danmaku=0")
		}

		return nil
	}

	private static func youTubeVideoID(url: URL, host: String) -> String? {
		if host.hasSuffix("youtu.be") {
			return sanitised(url.lastPathComponent)
		}

		guard host.hasSuffix("youtube.com") else {
			return nil
		}

		// Already an embed. Leaving it alone matters: rewriting it would append a second query string.
		if url.path.hasPrefix("/embed/") {
			return nil
		}

		if url.path == "/watch" {
			let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.queryItems?
				.first { $0.name == "v" }?
				.value

			return sanitised(value)
		}

		// The short-form path, /shorts/<id>.
		if url.path.hasPrefix("/shorts/") {
			return sanitised(url.lastPathComponent)
		}

		return nil
	}

	private static func bilibiliVideoID(url: URL, host: String) -> String? {
		guard
			host.hasSuffix("bilibili.com"),
			// The player page is the destination, not a source.
			host != "player.bilibili.com"
		else {
			return nil
		}

		// Video pages are /video/<BV id>, sometimes with a trailing slash or a part number.
		let parts = url.path.split(separator: "/")

		guard
			let index = parts.firstIndex(of: "video"),
			parts.indices.contains(index + 1)
		else {
			return nil
		}

		let identifier = String(parts[index + 1])

		return identifier.hasPrefix("BV") ? sanitised(identifier) : nil
	}

	/**
	Reject anything that is not a bare identifier, so nothing from the URL can be smuggled into the
	address we build.
	*/
	private static func sanitised(_ value: String?) -> String? {
		guard
			let value,
			!value.isEmpty,
			value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
		else {
			return nil
		}

		return value
	}
}
