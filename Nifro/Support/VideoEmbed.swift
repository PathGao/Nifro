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

	Says nothing about sound. Whether a website is muted is a setting on that website, changed long
	after this URL was stored, so an answer baked in here would be the one the user cannot change.

	YouTube does need one condition to start at all, but that belongs to loading the player rather
	than to its address, so it lives in `hostPage(for:)`.
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

	/**
	The page that has to host `url` for it to work, or `nil` when the address can be opened on its own.

	YouTube's embed address is built to be framed by somebody else's page and refuses to be one:
	opened directly it answers "error 153, player configuration error", which is what a Nifro
	wallpaper pointed straight at it used to show. So it gets a page to be framed by.

	Which address that page is loaded as matters, and not in the way you would guess: YouTube rejects
	being framed by `youtube.com` too. This is the project's own page, which is also an honest answer
	to who is asking.

	The framed address is made to say `mute=1`, which reads like a decision about sound and is not
	one: YouTube's player refuses to start at all unless it is muted, whatever the web view allows.
	It is the price of autoplay. The website's own sound setting is applied to the player afterwards
	by the audio script, which unmutes it and starts it playing. Measured: with `mute=1` the player
	runs, without it the video sits paused on its first frame, which looks identical to a still until
	you wait for it. Added here rather than in the address above so that a player address stored
	before this was known still starts.
	*/
	static func hostPage(for url: URL) -> (html: String, baseURL: URL)? {
		guard
			url.host?.lowercased().hasSuffix("youtube.com") == true,
			url.path.hasPrefix("/embed/"),
			let baseURL = URL(string: "https://github.com/PathGao/nifro"),
			var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else {
			return nil
		}

		var items = components.queryItems ?? []

		if !items.contains(where: { $0.name == "mute" }) {
			items.append(URLQueryItem(name: "mute", value: "1"))
			components.queryItems = items
		}

		let url = components.url ?? url

		// The address is either one this file built out of a checked identifier or one the user
		// typed. Escaped anyway, because the difference is not visible from here.
		let source = url.absoluteString
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "<", with: "&lt;")

		return (
			"""
			<!doctype html>
			<meta name="viewport" content="width=device-width, initial-scale=1">
			<style>
				html, body { margin: 0; height: 100%; background: #000 }
				iframe { border: 0; width: 100%; height: 100% }
			</style>
			<iframe src="\(source)" allow="autoplay; encrypted-media" allowfullscreen></iframe>
			""",
			baseURL
		)
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
