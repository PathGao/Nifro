import SwiftUI

/**
The curated list of pages that work well as wallpapers, compiled into the app.

Shipping it beats linking to it. The work is finding a good page, working out that it needs a 15-minute reload and three lines of CSS to hide its navigation, then typing all that in. Somebody has already done that work once. A web page to copy settings from by hand would make each person redo it.

The bundled copy is generated from the YAML files under `sites` by `Tools/generate-site-catalog.py`. It is a snapshot taken at release time; the live list is fetched from GitHub when the gallery opens, so entries contributed between releases show up without an app update.
*/
enum SiteCatalog {
	struct Entry: Identifiable, Hashable, Decodable {
		let name: String
		let url: String
		let description: String
		let tags: [String]

		let reloadInterval: Double?
		let zoom: Zoom?
		let css: String?
		let javaScript: String?
		let requiresLogin: Bool

		/// Whether the entry is one you would want to hear, which for a wallpaper is the exception.
		let playsSound: Bool

		/// Ships with the app and is installed on first launch.
		let isFeatured: Bool

		var id: String { url }

		private var parsedURL: URL? { URL(string: url) }
	}

	/**
	Where the list actually lives.

	The repository is the source of truth and the place submissions arrive, so the app reads it rather than keeping its own copy authoritative. What ships in the binary is a snapshot for when there is no network.
	*/
	private static let indexURL = URL("https://raw.githubusercontent.com/PathGao/Nifro/main/sites/index.json")

	/**
	The entries that ship with the app, in the order they are installed.

	File name order, which is arbitrary but at least fixed. Worth knowing because the first one is
	the wallpaper somebody sees before they have chosen anything.
	*/
	static var featured: [Entry] { entries.filter(\.isFeatured) }

	static func allTags(in entries: [Entry]) -> [String] {
		Array(Set(entries.flatMap(\.tags))).sorted()
	}

	/**
	Fetch the current list, falling back to the bundled snapshot.
	*/
	static func fetchLatest() async -> (entries: [Entry], isLive: Bool) {
		var request = URLRequest(url: indexURL)
		request.timeoutInterval = 6
		request.cachePolicy = .reloadRevalidatingCacheData

		guard
			let (data, response) = try? await URLSession.shared.data(for: request),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let fetched = try? JSONDecoder().decode([Entry].self, from: data),
			!fetched.isEmpty
		else {
			return (entries, false)
		}

		return (fetched, true)
	}
}

extension SiteCatalog.Entry {
	/**
	Add this site, carrying over the settings that make it work.
	*/
	@MainActor
	func add() {
		guard let parsedURL else {
			return
		}

		let binding = WebsitesController.shared.add(parsedURL, title: name)

		binding.wrappedValue.css = css ?? ""
		binding.wrappedValue.javaScript = javaScript ?? ""
		binding.wrappedValue.zoom = zoom
		// Everything the entry carries is a starting point. From here on the website is the user's:
		// the Sound item in the menu writes to this same field, and nothing puts the entry's answer
		// back. Whatever the menu shows a tick against is what the page is actually doing.
		binding.wrappedValue.audio = playsSound ? .unmuted : .muted
		binding.wrappedValue.reloadInterval = reloadInterval
	}
}

extension WebsitesController {
	/**
	Put the shipped websites in the list, once, on the first launch.

	A wallpaper app that starts with an empty desktop asks the user to go and find something before
	it has shown them what it does. These are ordinary websites once installed: editable, reorderable
	and deletable like anything they add themselves, with no trace of having come from us. That
	matters more than which ones they are. A built-in you cannot delete is not a starting point, it is
	furniture.

	Guarded on having been done rather than on the list being empty, so someone who deletes all of
	them does not get them back on the next launch.
	*/
	@MainActor
	func installFeaturedWebsitesIfNeeded() {
		guard !Defaults[.hasInstalledFeaturedWebsites] else {
			return
		}

		Defaults[.hasInstalledFeaturedWebsites] = true

		for entry in SiteCatalog.featured {
			entry.add()
		}

		// Adding makes each one current in turn, so without this the wallpaper would be whichever
		// happened to be last in the folder. Show the first.
		if let first = all.first {
			makeCurrent(first)
		}
	}
}
