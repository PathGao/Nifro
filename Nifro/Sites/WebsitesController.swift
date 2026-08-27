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

	/**
	The normalized addresses of the websites that still have no title.

	`recordObservedTitle` runs on every `document.title` a live page writes, and reading `all` there is
	a JSON decode of the whole website list followed by a `URLComponents` parse per entry — all of it
	ahead of the guard that makes the call a no-op. A page with a clock, an unread count or a track
	name in its title rewrites it once a second for as long as the wallpaper is up, and every one of
	those was paying for the whole table.

	Kept here rather than worked out per call because it is derived from the list, and the list already
	has one place where every route to it meets: the publisher below. Nothing else may write this, and
	nothing else needs to — `Defaults.publisher` sees writes through `all`, through `allBinding` and
	through any settings screen that reaches the key directly, which is why the current-mark repair in
	the same closure can also be the only one of its kind.

	Subscribed with `ObservationOptions.initial`, which is `Defaults.publisher`'s default, so this is
	filled from the stored list before `init` returns rather than at the first edit.
	*/
	private var addressesAwaitingTitle = Set<URL>()

	private init() {
		setUpEvents()
	}

	private func setUpEvents() {
		Defaults.publisher(.websites)
			.sink { [weak self] change in
				guard let self else {
					return
				}

				addressesAwaitingTitle = Set(
					change.newValue.lazy
						.filter(\.title.isEmpty)
						.map { $0.url.normalized() }
				)

				// Every display keeps exactly one marked website, not the list as a whole — both
				// halves of that, which is what changed here. A display with none is what `advance`
				// reads as "start from the beginning", so it would never move past the first website
				// in its list; a display with two is a tie `scheduled(for:)` breaks by list order, so
				// a website sent to a display by "Show on" arrived with no effect and that screen did
				// not change. Only the first half was enforced, and it is the half whose failure is
				// visible. `repairedCurrentFlags` is where the rule and the argument for it live.
				//
				// Here rather than in `update`, because "Show on" never reaches `update`: it writes
				// the display through a settings binding straight into the stored list. This
				// publisher is the one place every route to that list meets.
				let displays = change.newValue.map(\.effectiveDisplay)
				let wasCurrent = change.newValue.map(\.isCurrent)

				let repaired = repairedCurrentFlags(
					displays: displays,
					isCurrent: wasCurrent,
					// Matched by id rather than by position: the two lists differ in membership
					// whenever a website was added or removed, and the same index in each is then a
					// different website.
					wasAlreadyCurrentHere: zip(change.newValue, displays).map { website, display in
						guard let before = change.oldValue.first(where: { $0.id == website.id }) else {
							return false
						}

						return before.isCurrent && before.effectiveDisplay == display
					}
				)

				// Only when it actually changed something. The write goes back through this same
				// publisher, so repairing a list that was already right is a write per change.
				if repaired != wasCurrent {
					all = zip(change.newValue, repaired).map {
						var updated = $0
						updated.isCurrent = $1
						return updated
					}
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

	Marking a website is a request to *see* it, so a display that is switched off is switched back on.
	Stepping a display that is off is how you wake it — the panel's own Next and Previous had always
	said so and did it themselves, and the keyboard shortcut, the `nifro://` commands and the Shortcuts
	action reached the same verb by another door and skipped it. The mark then moved under a dark
	screen: nothing was fetched, nothing appeared, so it got pressed again, and the display came back
	later on a website nobody had chosen. Answered here because here is where all of those meet —
	Next, Previous and Random are three verbs with three entry points each and all nine end in this
	method, so the answer is inherited rather than repeated nine times and forgotten in six of them.

	- Parameter switchingDisplayOn: `false` where the mark is bookkeeping rather than a request to
	look at something. Adding a website has to leave *some* website marked on its display, and that is
	not a reason to light up a screen the user switched off.
	*/
	func makeCurrent(_ website: Website, switchingDisplayOn: Bool = true) {
		guard let target = all.firstIndex(where: { $0.id == website.id }) else {
			return
		}

		// Before the mark moves rather than after, which is the order the panel already used: the list
		// change reaches the scenes through a publisher on the next turn of the run loop, so a display
		// switched on here is already on by the time the page it should be showing is worked out.
		if
			switchingDisplayOn,
			AppState.shared.scenes.first(where: { $0.display == all[target].effectiveDisplay })?.isDisabledForDisplay == true
		{
			AppState.shared.setDisplayEnabled(true, on: all[target].effectiveDisplay)
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
		all = all.modifying(elementWithID: id, update: change)
	}

	/**
	Add a website.
	*/
	@discardableResult
	func add(_ website: Website) -> Binding<Website> {
		// The order here is important.
		all.append(website)

		// Marked, not shown. A new website has to hold its display's mark or that display has none,
		// but putting something in the list is not a request to look at it — a display the user
		// switched off stays off, and the gallery installing several at once does not flick a screen
		// on per website. The screens that do mean "show this now" say so with their own
		// `makeCurrent` afterwards.
		makeCurrent(website, switchingDisplayOn: false)

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
	The websites that should be on screen right now, before any question of which display.

	Both of the places that route by display start here, so a wallpaper the user has said should go
	away with its unplugged display goes away once rather than in two places that could disagree.
	*/
	@MainActor
	var showable: [Website] { all.filter(\.isShowable) }

	/**
	Every display that has at least one website assigned to it.

	Falls back to the main display — the one with the menu bar — so there is always exactly one scene
	to show, even before anything is configured.
	*/
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

	Called once per navigation from `didFinish`, and again on every title the page writes afterwards —
	which is why `addressesAwaitingTitle` is asked first. It is an index over the last guard below
	rather than a replacement for it: a wrong answer from it can only cost a title that was going to be
	filled in, never write one over a title the user already has.

	Keyed on "some website is still without a title" and not on "this has run once", because the case
	worth keeping is exactly the one that arrives late: a single-page app loads with an empty or
	placeholder title and sets the real one from script seconds afterwards, and a latch would have
	closed before it got there.
	*/
	func recordObservedTitle(_ title: String, for url: URL?) {
		guard
			let url,
			addressesAwaitingTitle.contains(url.normalized()),
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

// The rest of this file is how a catalogue entry becomes a website. It sits here rather than beside
// the catalogue because `SiteCatalog` itself is now compiled by `Package.swift` as well as by the
// app, so that `swift test` can decode the committed `sites/index.json` through the real `Entry`.
// That only works while the catalogue depends on nothing above Foundation — no `Website`, no
// `Defaults`, no SwiftUI. Everything that does is below.

extension SiteCatalog.Entry {
	/**
	Add this site, carrying over the settings that make it work.

	Returns the website it created, so a caller installing several of them can say something about
	the ones it added rather than about whatever else is in the list. `nil` when the entry's address
	will not parse.
	*/
	@MainActor
	@discardableResult
	func add() -> Website.ID? {
		guard let parsedURL = URL(string: url) else {
			return nil
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

		return binding.wrappedValue.id
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

		// What was added, not what is in the list. The guard is on this having been done rather than
		// on the list being empty, so somebody upgrading into this may already have websites of their
		// own — and `all.first` was then one of theirs.
		let installed = SiteCatalog.featured.compactMap { $0.add() }
		let displays = Display.all

		// Adding makes each one current in turn, so without this the wallpaper would be whichever was
		// added last. A second display would have been left with nothing at all: every website was on
		// the main display, so there was only ever one scene to be current in.
		for placement in firstLaunchPlacements(displayCount: displays.count, websiteCount: installed.count) {
			let id = installed[placement.website]

			// Pinned, which is what puts a second scene on the second screen: `displaysInUse` is read
			// off the websites, so a display nothing names has no wallpaper. The first display is left
			// unpinned on purpose — see `firstLaunchPlacements`.
			if let index = placement.display {
				update(id) {
					$0.display = displays[index]
				}
			}

			guard let website = all[id: id] else {
				continue
			}

			makeCurrent(website)
		}
	}
}
