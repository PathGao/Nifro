import Foundation
import OSLog

/**
The curated list of pages that work well as wallpapers, compiled into the app.

Shipping it beats linking to it. The work is finding a good page, working out that it needs a 15-minute reload and three lines of CSS to hide its navigation, then typing all that in. Somebody has already done that work once. A web page to copy settings from by hand would make each person redo it.

The bundled copy is generated from the YAML files under `sites` by `Tools/generate-site-catalog.py`. It is a snapshot taken at release time; the live list is fetched from GitHub when the gallery opens, so entries contributed between releases show up without an app update.

Both outputs of that script are read back as `Entry`, so the two have to be the same shape. They were not: the JSON carried the YAML's own `audio: "muted" | "unmuted"` where `Entry` declared `playsSound: Bool`, so every fetched entry threw and the gallery fell back to the snapshot every single time. Nothing noticed because nothing ever decoded the committed JSON — the fallback made total failure look like a quiet success. `Tests/NifroTests.swift` now does, which is why this file depends on nothing above Foundation: it is compiled by `Package.swift` as well as by the app. Turning an entry into a website needs `Website` and `Defaults` and lives in `WebsitesController.swift` for that reason.
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

		/**
		Where this entry sits in the list installed on first launch, counting from 1. `nil` does not ship.

		A rank rather than a flag, because the order is a decision somebody made and it has to be
		recorded where the decision is: in the entry's own YAML file. It used to be `featured: true`
		with the file name deciding the order, which is not a decision at all — renaming a file
		changed the first wallpaper a new user sees.

		The alternative was a list of URLs in Swift saying which ship and in what order. That is a
		second place answering a question the YAML already answers, with nothing making the two agree.
		*/
		let featuredRank: Int?

		var id: String { url }
	}

	/**
	Where the list actually lives.

	The repository is the source of truth and the place submissions arrive, so the app reads it rather than keeping its own copy authoritative. What ships in the binary is a snapshot for when there is no network.

	Spelled out rather than written as a string literal: the literal spelling comes from an extension in `Support/Extensions.swift`, which this file no longer sees now that it is compiled by `Package.swift` too. A constant that has always parsed.
	*/
	private static let indexURL = URL(string: "https://raw.githubusercontent.com/PathGao/Nifro/main/sites/index.json")!

	/**
	The entries that ship with the app, in the order they are installed.

	Ordered by the rank each entry carries in its own YAML file, so the answer lives in one place and
	the app only reads it. Worth knowing because the first one is the wallpaper somebody sees before
	they have chosen anything, and on a second display they see the second one.

	Sorted through the rank rather than by it, so nothing here has to invent a stand-in rank for an
	entry that does not ship. `sorted(by:)` is not stable either, which is why two entries may not
	claim the same rank; `Tools/validate-sites.py` is what stops them.
	*/
	static var featured: [Entry] {
		entries
			.compactMap { entry in entry.featuredRank.map { (rank: $0, entry: entry) } }
			.sorted { $0.rank < $1.rank }
			.map(\.entry)
	}

	static func allTags(in entries: [Entry]) -> [String] {
		Array(Set(entries.flatMap(\.tags))).sorted()
	}

	/**
	Fetch the current list, falling back to the bundled snapshot.

	Says how many entries it dropped, and does nothing else about it. Skipping an entry and skipping
	all of them are two different faults — one contributor's file is wrong, or the file the app asks
	for is not the shape the app reads — and only the second one is worth a person's attention. But
	telling them apart at runtime does not help the person running the app either way: both leave
	them looking at the snapshot, which is the best answer available, and neither is theirs to fix.
	So one line to the system log, which is where somebody who suspects this would go looking, and no
	alert, no retry, no state. The thing that actually catches the second fault is a test that
	decodes the committed `sites/index.json` through `Entry` before it is ever published.
	*/
	static func fetchLatest() async -> (entries: [Entry], isLive: Bool) {
		var request = URLRequest(url: indexURL)
		request.timeoutInterval = 6
		request.cachePolicy = .reloadRevalidatingCacheData

		guard
			let (data, response) = try? await URLSession.shared.data(for: request),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let decoded = try? JSONDecoder().decode([SkippableEntry].self, from: data)
		else {
			return (entries, false)
		}

		let fetched = decoded.compactMap(\.entry)

		if fetched.count < decoded.count {
			Logger().warning("Site catalogue: \(decoded.count - fetched.count) of \(decoded.count) entries did not decode")
		}

		guard !fetched.isEmpty else {
			return (entries, false)
		}

		return (fetched, true)
	}
}

/**
One entry that is allowed to be undecodable, so that the rest of the list survives it.

The list is fetched from `main` rather than shipped in a build, so an entry can be added without a
release — which means an entry can also be *wrong* without a release. Decoding the array in one call
made that all-or-nothing: a single bad entry threw, the `try?` swallowed it, and every installed copy
silently fell back to the compiled-in snapshot with no sign anything had happened. A catalogue whose
whole point is arriving between releases must not have a failure mode that costs the whole catalogue.

What it was never meant to cover is every entry failing at once, and that is what it went on to hide
for the whole life of the feature: the published file said `audio` where `Entry` said `playsSound`,
so all 38 threw, all 38 were skipped, and the empty result was indistinguishable from a fetch that
had simply found nothing new. Being per-entry is still right — the alternative loses good entries to
one bad one — so what changed is that `fetchLatest` now counts what it dropped and says so, and a
test decodes the committed file so a shape this wrong cannot reach `main` in the first place.
*/
private struct SkippableEntry: Decodable {
	let entry: SiteCatalog.Entry?

	init(from decoder: any Decoder) throws {
		entry = try? SiteCatalog.Entry(from: decoder)
	}
}
