import SwiftUI
import LinkPresentation

@MainActor
final class WebsitesController {
	static let shared = WebsitesController()

	private var cancellables = Set<AnyCancellable>()
	private var _current: Website? { all.first(where: \.isCurrent) }
	private var nextCurrent: Website? { all.elementAfterOrFirst(_current) }
	private var previousCurrent: Website? { all.elementBeforeOrLast(_current) }

	private var randomWebsiteIterator = Defaults[.websites].infiniteUniformRandomSequence().makeIterator()

	@MainActor let thumbnailCache = SimpleImageCache<String>(diskCacheName: "websiteThumbnailCache")

	/**
	The current website.
	*/
	var current: Website? {
		get { _current ?? all.first }
		set {
			guard let newValue else {
				all = all.modifying {
					$0.isCurrent = false
				}

				return
			}

			makeCurrent(newValue)
		}
	}

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

				// Ensures there's always a current website.
				if
					change.newValue.allSatisfy(!\.isCurrent),
					let website = change.newValue.first
				{
					website.makeCurrent()
				}

				// We only reset the iterator if a website was added/removed.
				if change.newValue.map(\.id) != change.oldValue.map(\.id) {
					randomWebsiteIterator = all.infiniteUniformRandomSequence().makeIterator()
				}
			}
			.store(in: &cancellables)
	}

	/**
	Make a website the current one.
	*/
	func makeCurrent(_ website: Website) {
		all = all.modifying {
			$0.isCurrent = $0.id == website.id
		}
	}

	/**
	Add a website.
	*/
	@discardableResult
	func add(_ website: Website) -> Binding<Website> {
		// The order here is important.
		all.append(website)
		current = website

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
	Makes the next website the current one.
	*/
	func makeNextCurrent() {
		guard let nextCurrent else {
			return
		}

		makeCurrent(nextCurrent)
	}

	/**
	Makes the previous website the current one.
	*/
	func makePreviousCurrent() {
		guard let previousCurrent else {
			return
		}

		makeCurrent(previousCurrent)
	}

	/**
	Makes a random website in the list the current one.
	*/
	func makeRandomCurrent() {
		guard let website = randomWebsiteIterator.next() else {
			return
		}

		makeCurrent(website)
	}

	/**
	Every display that has at least one website assigned to it.

	Falls back to the display chosen in Settings so there is always exactly one scene to show, even before anything is configured.
	*/
	var displaysInUse: [Display?] {
		var seen: [Display?] = []

		for website in all {
			let display = website.effectiveDisplay
			if !seen.contains(where: { $0 == display }) {
				seen.append(display)
			}
		}

		return seen.isEmpty ? [Defaults[.display]] : seen
	}

	/**
	The website showing on `display`, if any.
	*/
	func current(for display: Display?) -> Website? {
		let onDisplay = all.filter { $0.effectiveDisplay == display }
		return onDisplay.first { $0.isCurrent } ?? onDisplay.first
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
