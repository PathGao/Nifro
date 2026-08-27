import SwiftUI
import LinkPresentation

@MainActor
final class WebsitesController {
	static let shared = WebsitesController()

	private var cancellables = Set<AnyCancellable>()

	/**
	One shuffled order per display, so Random on one screen leaves the other where it was.

	Keyed by display rather than one iterator over the whole list, for the same reason `isCurrent` is
	no longer read across displays: a website belongs to one screen, and a pick that can land on
	another screen's website changes a wallpaper the person is not looking at.
	*/
	var randomIterators = [Display?: AnyIterator<Website>]()

	@MainActor let thumbnailCache = SimpleImageCache<String>(diskCacheName: "websiteThumbnailCache")

	/**
	All websites.
	*/
	var all: [Website] {
		get { Defaults[.websites] }
		set {
			Defaults[.websites] = newValue
		}
	}

	private let allBinding = Defaults.bindingCollection(for: .websites)

	private init() {
		setUpEvents()
		thumbnailCache.prewarmCacheFromDisk(for: all.map(\.thumbnailCacheKey))
	}

	private func setUpEvents() {
		Defaults.publisher(.websites)
			.sink { [weak self] change in
				guard let self else {
					return
				}

				// Every display keeps exactly one marked website, not the list as a whole. A display
				// with none is what `advance` reads as "start from the beginning", so it would never
				// move past the first website in its list.
				var marked = change.newValue
				var didMark = false

				for display in Set(marked.map(\.effectiveDisplay))
				where !marked.contains(where: { $0.effectiveDisplay == display && $0.isCurrent }) {
					guard let index = marked.firstIndex(where: { $0.effectiveDisplay == display }) else {
						continue
					}

					marked[index].isCurrent = true
					didMark = true
				}

				if didMark {
					all = marked
				}

				// We only reset the iterators if a website was added/removed.
				if change.newValue.map(\.id) != change.oldValue.map(\.id) {
					randomIterators = [:]
				}
			}
			.store(in: &cancellables)
	}

	/**
	Make a website the current one on its own display.

	Only the websites sharing that display lose the mark. Clearing it across the whole list is what
	stopped rotation working on more than one screen: each tick of one display's playlist wiped the
	other display's mark, so `advance` there found nothing current, started again from index 0, and
	that screen sat on the first website in its list for good.
	*/
	func makeCurrent(_ website: Website) {
		guard let target = all.firstIndex(where: { $0.id == website.id }) else {
			return
		}

		let flags = currentFlags(
			displays: all.map(\.effectiveDisplay),
			wasCurrent: all.map(\.isCurrent),
			makingCurrent: target
		)

		all = zip(all, flags).map {
			var updated = $0
			updated.isCurrent = $1
			return updated
		}
	}

	/**
	Change one website in place.

	The read-modify-write around the stored list was spelled out at all seven call sites, which is
	seven chances to write back a list built from a stale read.
	*/
	func update(_ id: Website.ID, _ change: (inout Website) -> Void) {
		let display = all[id: id]?.effectiveDisplay

		all = all.modifying(elementWithID: id, update: change)

		// Every edit to a website goes through here, so this is where a synced display hands its change
		// to the rest of its group. Doing it at each call site instead would mean finding all of them,
		// and finding all of them again whenever one is added.
		if let display {
			mirrorAcrossSyncGroup(from: display)
		}
	}

	/**
	Add a website.
	*/
	@discardableResult
	func add(_ website: Website) -> Binding<Website> {
		// The order here is important.
		all.append(website)
		makeCurrent(website)

		return allBinding[id: website.id]!
	}

	/**
	Add a website from a URL.

	Optionally, specify a title. If no title is given or if the title is empty, a title will be automatically fetched from the website.
	*/
	@discardableResult
	func add(_ websiteURL: URL, title: String? = nil) -> Binding<Website> {
		let websiteBinding = add(
			Website(
				id: UUID(),
				isCurrent: true,
				url: websiteURL,
				usePrintStyles: false
			)
		)

		if let title = title?.nilIfEmptyOrWhitespace {
			websiteBinding.wrappedValue.title = title
		} else {
			fetchTitleIfNeeded(for: websiteBinding)
		}

		return websiteBinding
	}

	/**
	Remove a website.
	*/
	func remove(_ website: Website) {
		all = all.removingAll(website)
	}

	/**
	Every display that has at least one website assigned to it.

	Falls back to the display chosen in Settings so there is always exactly one scene to show, even before anything is configured.
	*/
	/**
	The websites that should be on screen right now, before any question of which display.

	Both of the places that route by display start here, so a wallpaper the user has said should go
	away with its unplugged display goes away once rather than in two places that could disagree.
	*/
	@MainActor
	var showable: [Website] { all.filter(\.isShowable) }

	var displaysInUse: [Display?] {
		var seen: [Display?] = []

		for website in showable {
			let display = website.effectiveDisplay
			if !seen.contains(where: { $0 == display }) {
				seen.append(display)
			}
		}

		return seen.isEmpty ? [.main] : seen
	}

	/**
	Record a title observed in the live web view, if we do not already have one.

	`LPMetadataProvider` fetches the raw HTML with subresources turned off and gives up after a few seconds. It comes back empty for anything that sets its title from JavaScript or loads slowly, which covers a lot of the sites people use as wallpapers. The web view has already run the page, so its title is more accurate and costs nothing.
	*/
	func recordObservedTitle(_ title: String, for url: URL?) {
		guard
			let url,
			let title = title.trimmed.nilIfEmpty,
			let index = all.firstIndex(where: { $0.url.normalized() == url.normalized() }),
			all[index].title.isEmpty
		else {
			return
		}

		all[index].title = title
	}

	/**
	Fetch the title for a website in the background if the existing title is empty.
	*/
	private func fetchTitleIfNeeded(for website: Binding<Website>) {
		guard website.wrappedValue.title.isEmpty else {
			return
		}

		Task {
			let metadataProvider = LPMetadataProvider()
			metadataProvider.shouldFetchSubresources = false

			guard
				let metadata = try? await metadataProvider.startFetchingMetadata(for: website.wrappedValue.url),
				let title = metadata.title
			else {
				return
			}

			website.wrappedValue.title = title
		}
	}
}
