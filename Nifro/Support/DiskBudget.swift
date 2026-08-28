import WebKit

/**
Nifro holds a web page open for as long as the Mac is on, so WebKit's storage only ever grows. On the
machine this was written for, ordinary use left a 151 MB container, 147 MB of it one shader site's
`CacheStorage` and the shared network cache — nothing the user had put there.

That is a live disk cost, and it is also what is left behind after the app is dragged to the Trash:
macOS never removes a container, and an app gets no chance to run at uninstall. WebKit offers no way
to cap its storage, so the only lever is to spend the budget down while the app is still running,
which is what keeps the leftovers small too.
*/
enum DiskBudget {
	/**
	Above this, the re-fetchable types are dropped.

	Below what ordinary use was measured to reach, or it would never fire — the first number tried was
	200 MB, which the 151 MB container that prompted all this would have sailed under. It protects no
	particular amount of cache: a wallpaper re-downloading its page costs a few seconds once, and the
	page is on a reload timer anyway.
	*/
	static let limit = Int64(100_000_000)

	/**
	The types the app is willing to throw away.

	Each one is a copy of something the network can hand back. Cookies, local storage, IndexedDB and
	service worker registrations are deliberately absent: those hold logins and whatever a dashboard
	was set to, and housekeeping that signs the user out of their own wallpaper is a bug.
	*/
	static let refetchableTypes: Set<String> = [
		WKWebsiteDataTypeDiskCache,
		WKWebsiteDataTypeMemoryCache,
		WKWebsiteDataTypeFetchCache
	]

	/**
	Where WebKit puts everything the sweep can reach.

	Named rather than measured from the container root, because the budget is about what a sweep could
	free and the rest of the container is a rounding error next to it. Naming them also keeps the walk
	honest in an unsandboxed debug build, where the container root is the real home directory and
	measuring it means walking the whole disk.

	The app's own thumbnail cache is part of that rest, and is deliberately not listed here.
	`removeOrphanedFiles` below says why: a root this sweep cannot spend is a number that only makes
	the sweep fire.
	*/
	private static let sweptRoots = [
		URL.homeDirectory.appending(path: "Library/Caches/WebKit"),
		URL.homeDirectory.appending(path: "Library/WebKit")
	]

	/**
	The store a website gets to itself.

	One store per website rather than one shared by all of them, so that removing a website removes
	what it wrote. Under a shared store there was no way to: a site that had put 80 MB in its
	`CacheStorage` kept it after being deleted from the list, and the only thing that could reach it
	was the button that also signs the user out of every website they kept.

	Keyed on the website's `id`, which is already stored and already stable across edits — renaming a
	website or changing its address keeps the store, which is what editing an entry means.
	*/
	@MainActor
	static func store(for websiteID: UUID) -> WKWebsiteDataStore {
		WKWebsiteDataStore(forIdentifier: websiteID)
	}

	/**
	Every store this app has on disk, the per-website ones and the shared one.

	Anything that means "all website data" has to go through this. The shared store is still in the
	list because builds before per-website stores wrote everything into it, and an upgrade leaves that
	behind: nothing new goes there, but what is there is real and still counts against the disk.
	*/
	@MainActor
	static func allStores() async -> [WKWebsiteDataStore] {
		let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
		return [.default()] + identifiers.map { WKWebsiteDataStore(forIdentifier: $0) }
	}

	/**
	Drops the re-fetchable types if WebKit's storage is over budget.

	Reports nothing: the freed figure this used to return cost a second walk of the same roots to
	measure — `removeData` cannot say what it removed — and no caller ever read it.
	*/
	@MainActor
	static func enforce() async {
		guard await storedBytes(of: sweptRoots) > limit else {
			return
		}

		// By date, not by record: `removeData(for:)` only reaches what WebKit can attribute to an
		// origin, and the network cache mostly is not — the same reason `clearAllWebsiteData` does it
		// this way.
		//
		// Every store, not just the shared one: each website has its own, so sweeping one store would
		// leave the budget being blown by whichever website is not it.
		for store in await allStores() {
			await store.removeData(ofTypes: refetchableTypes, modifiedSince: .distantPast)
		}
	}

	/**
	Deletes the stores of websites that are no longer in the list.

	The websites are passed in rather than read here, because this is the half of the problem that has
	nothing to do with WebKit: the app knows which websites exist, and every store that is not one of
	them belongs to a website the user already deleted.
	*/
	@MainActor
	static func removeOrphanedStores(keeping websiteIDs: Set<UUID>) async {
		for identifier in orphans(among: await WKWebsiteDataStore.allDataStoreIdentifiers, keeping: websiteIDs) {
			try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
		}
	}

	/**
	Deletes every per-website store, because every website is gone.

	The sweep above refuses an empty website list, and the refusal is right where it is: it works out
	what an orphan is by reading the list, and a list that reads as empty is far likelier to be a bad
	read than a user with nothing left. This is the one caller for which "there are no websites" is not
	a reading at all — it is what the user asked for, in a dialog that said the stores went with them.

	The shared store is not reached here because it cannot be removed, only emptied, which
	`clearAllWebsiteData` does on the same run. A store still open in a web view refuses removal and is
	left holding nothing instead, which is why the websites are dropped before this is called.
	*/
	@MainActor
	static func removeAllStores() async {
		for identifier in await WKWebsiteDataStore.allDataStoreIdentifiers {
			try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
		}
	}

	/**
	Deletes the files in a cache directory that no live name claims.

	The other half of `removeOrphanedStores`, for the one cache this app writes itself instead of
	letting WebKit write it. `websiteThumbnailCache` is a flat directory holding one file per website
	preview, named for the website's *address* — and the address is the one thing about a website that
	changes under the user's hand. Editing it, or accepting a redirect, leaves the old file behind
	under a name nothing will ever ask for again; so does deleting the website. `removeOrphanedStores`
	can reach none of it: it keeps by `id`, and what it walks is WebKit's stores.

	**The names arrive already in the form the directory uses**, rather than the keys they were made
	from, because the mapping from a key to a file name belongs to the cache that writes the files and
	must not have a second copy here. A second copy that drifted would not fail loudly. It would
	recognise nothing, read every file as an orphan, and empty the cache on the next sweep.

	**Not a root, and not measured against `limit`.** `enforce`'s only lever is
	`WKWebsiteDataStore.removeData`, which cannot touch a directory this app wrote, so a root added
	there is a number the guard reads and the sweep has no way to spend: over budget on thumbnails
	alone, every website's page cache would be dropped every six hours and the total would never come
	down. What bounds this directory is this sweep. After it there is at most one file per website in
	the list, which is exactly the set the list is about to draw — a rounding error next to the WebKit
	roots, for the same reason the rest of the container is one.

	An empty keep-set collects nothing rather than everything, for the reason `orphans` spells out.
	What is lost here is a refetch rather than a login, but the reading is exactly as untrustworthy,
	and there is no reason for the sweeps running off one list to disagree about what an empty list
	means.
	*/
	static func removeOrphanedFiles(in directory: URL, keeping fileNames: Set<String>) {
		guard !fileNames.isEmpty else {
			return
		}

		let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

		for file in contents where !fileNames.contains(file.lastPathComponent) {
			try? FileManager.default.removeItem(at: file)
		}
	}

	/**
	Which stores belong to no website any more.

	An empty website list collects nothing, rather than everything. Nothing here can put a store back,
	so the one reading that must not be trusted is the one that says every website is gone — and a
	user who really has deleted their last website has an app showing nothing, which is not the moment
	to also throw away the logins they are about to want back.
	*/
	static func orphans(among identifiers: [UUID], keeping websiteIDs: Set<UUID>) -> [UUID] {
		guard !websiteIDs.isEmpty else {
			return []
		}

		return identifiers.filter { !websiteIDs.contains($0) }
	}

	/**
	How much disk the given directories are holding.

	Measured from the disk rather than asked of WebKit, because WebKit only reports what it can
	attribute to an origin and the network cache mostly is not.
	*/
	static func storedBytes(of roots: [URL]) async -> Int64 {
		await Task.detached(priority: .utility) {
			let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]

			return roots.reduce(into: Int64(0)) { total, root in
				guard
					let files = FileManager.default.enumerator(
						at: root,
						includingPropertiesForKeys: Array(keys)
					)
				else {
					return
				}

				for case let url as URL in files {
					total += Int64((try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
				}
			}
		}
		.value
	}
}
