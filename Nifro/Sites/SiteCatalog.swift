import SwiftUI

/**
The curated list of pages that work well as wallpapers, compiled into the app.

Shipping it rather than linking to it is the point: finding a good page, working out that it needs a 15-minute reload and three lines of CSS to hide its navigation, and typing all that in, is the work — and it is work somebody has already done. Sending people to a web page to copy settings by hand would be asking them to redo it.

The bundled copy is generated from the YAML files under `sites` by `scripts/generate-site-catalog.py`. It is a snapshot taken at release time; the live list is fetched from GitHub when the gallery opens, so entries contributed between releases show up without an app update.
*/
enum SiteCatalog {
	struct Entry: Identifiable, Hashable, Decodable {
		let name: String
		let url: String
		let description: String
		let tags: [String]

		/**
		Whether the page needs to keep rendering, as opposed to being re-drawn every so often.

		Shown to the user because it is the difference between a page that costs nothing to leave up and one that does not.
		*/
		let isLive: Bool

		let reloadInterval: Double?
		let crop: CGRect?
		let css: String?
		let javaScript: String?
		let requiresLogin: Bool

		var id: String { url }

		var parsedURL: URL? { URL(string: url) }
	}

	/**
	Where the list actually lives.

	The repository is the source of truth and the place submissions arrive, so the app reads it rather than keeping its own copy authoritative. What ships in the binary is a snapshot for when there is no network.
	*/
	static let indexURL = URL("https://raw.githubusercontent.com/PathGao/nifro/main/sites/index.json")

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
		binding.wrappedValue.crop = crop
		binding.wrappedValue.rendering = isLive ? .live : .snapshot

		// A per-site reload interval is not something the app models yet, so the catalogue's value is applied to the global setting only when nothing has been chosen. Better than silently ignoring it, and better than overriding a choice the user made.
		if let reloadInterval, Defaults[.reloadInterval] == nil {
			Defaults[.reloadInterval] = reloadInterval
		}
	}
}
