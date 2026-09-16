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

	Fullscreen policy does not belong in the stored address. `presentationURL(for:fullscreenCompatibility:)`
	adds it only to the request the current process makes.
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
	The player URL this process should load, without mutating the website URL it was derived from.

	`fs=0` is Nifro's safe-wallpaper presentation policy, not part of a video's identity. A saved
	address from a build that wrote it is therefore normalized in both directions: wallpaper mode
	keeps exactly one disabling value; compatibility mode removes every old value and gets YouTube's
	normal fullscreen control.
	*/
	static func presentationURL(for url: URL, fullscreenCompatibility: FullscreenCompatibility) -> URL {
		guard
			url.host?.lowercased().hasSuffix("youtube.com") == true,
			url.path.hasPrefix("/embed/"),
			var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else {
			return url
		}

		var items = (components.queryItems ?? []).filter { $0.name != "fs" }

		if fullscreenCompatibility.hidesYouTubeFullscreenControl {
			items.append(URLQueryItem(name: "fs", value: "0"))
		}

		components.queryItems = items
		return components.url ?? url
	}

	/**
	The browser identification that lets a direct YouTube embed create a player.

	Keeping the player as the main document matters for element fullscreen: an iframe's fullscreen
	request belongs to the iframe host rather than to the `WKWebView` document that receives the
	request. This header replaces the old app-built iframe page while preserving YouTube's required
	identification.
	*/
	static func referrer(for url: URL) -> String? {
		guard
			url.host?.lowercased().hasSuffix("youtube.com") == true,
			url.path.hasPrefix("/embed/")
		else {
			return nil
		}

		return "https://github.com/PathGao/Nifro"
	}

	/**
	The video's own cover image, for a list that would otherwise show the same site icon on every row.

	A list of videos is the case where a picture is worth most and where the usual sources give least:
	a player address has no link preview to read, so every entry falls back to the site's icon and the
	list becomes a column of identical logos with only the titles to tell them apart.

	YouTube publishes a cover at a fixed address derived from the video id, so this answers on its own.
	Bilibili's is behind an API call, which cannot be answered from a string — see `previewImageAPIURL(for:)`.
	*/
	static func previewImageURL(for url: URL) -> URL? {
		guard
			let host = url.host?.lowercased(),
			let identifier = youTubeVideoID(url: url, host: host) ?? youTubeEmbedID(url: url, host: host)
		else {
			return nil
		}

		return URL(string: "https://img.youtube.com/vi/\(identifier)/hqdefault.jpg")
	}

	/**
	The API address whose answer holds the cover for `url`, or `nil` when there is nothing to ask.

	Bilibili publishes no cover address derivable from the id the way YouTube does, so this is the one
	place the app calls a website's API rather than loading its page. What that costs is worth naming:
	one request per entry, carrying the video id and nothing else — no key, no account, no header — and
	only for an entry the user added themselves. The answer lands in the same on-disk thumbnail cache as
	every other row icon, so it is asked once and not once per redraw.

	The request itself belongs to the caller. This file stays free of the network so its parsing can be
	tested without one, which is why the answer comes back through `previewImageURL(inAPIResponse:)`.
	*/
	static func previewImageAPIURL(for url: URL) -> URL? {
		guard
			let host = url.host?.lowercased(),
			let identifier = bilibiliVideoID(url: url, host: host) ?? bilibiliPlayerID(url: url, host: host)
		else {
			return nil
		}

		return URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(identifier)")
	}

	/**
	The cover address inside an answer from `previewImageAPIURL(for:)`.

	Two things about that answer are not what its shape suggests. Its `pic` arrives as `http://`, which
	App Transport Security refuses — the same file is served over TLS by the same host, so the scheme is
	replaced rather than trusted. And it is the full-size cover: measured at 651 KB for one, against 30 KB
	for the YouTube cover sitting next to it in the same list. `@320w_180h.jpg` is the CDN's own resize
	and takes that to 7 KB, which is still more than a 44-point row can show.

	The host is checked because everything after the request is somebody else's text. An answer naming a
	host that is not the image CDN is one this app has no reason to fetch, and the resize suffix would
	mean nothing there anyway.
	*/
	static func previewImageURL(inAPIResponse data: Data) -> URL? {
		struct Answer: Decodable {
			struct Video: Decodable {
				let pic: String
			}

			let code: Int
			let data: Video?
		}

		guard
			let answer = try? JSONDecoder().decode(Answer.self, from: data),
			answer.code == 0,
			let pic = answer.data?.pic,
			var components = URLComponents(string: pic),
			components.host?.hasSuffix(".hdslb.com") == true
		else {
			return nil
		}

		components.scheme = "https"
		components.path += "@320w_180h.jpg"

		return components.url
	}

	/**
	The id in an address that is already a player, which `youTubeVideoID` deliberately refuses.
	*/
	private static func youTubeEmbedID(url: URL, host: String) -> String? {
		guard
			host.hasSuffix("youtube.com"),
			url.path.hasPrefix("/embed/")
		else {
			return nil
		}

		return sanitised(url.lastPathComponent)
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
	The id in a Bilibili address that is already a player, which `bilibiliVideoID` deliberately refuses.
	*/
	private static func bilibiliPlayerID(url: URL, host: String) -> String? {
		guard host == "player.bilibili.com" else {
			return nil
		}

		let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
			.queryItems?
			.first { $0.name == "bvid" }?
			.value

		guard let identifier = sanitised(value) else {
			return nil
		}

		return identifier.hasPrefix("BV") ? identifier : nil
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
