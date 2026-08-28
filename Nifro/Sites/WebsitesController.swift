import SwiftUI
import LinkPresentation

@MainActor
final class WebsitesController {
	static let shared = WebsitesController()

	private var cancellables = Set<AnyCancellable>()

	/**
	One shuffled order per display, so Random on one screen leaves the other where it was.

	Keyed by display rather than one iterator over the whole list, for the same reason the cursor is: a
	website belongs to one screen, and a pick that can land on another screen's website changes a
	wallpaper the person is not looking at.
	*/
	var randomIterators = [Display?: AnyIterator<Website>]()

	@MainActor let thumbnailCache = SimpleImageCache<String>(diskCacheName: "websiteThumbnailCache")

	/**
	All websites, in the order the playlists hold them.

	Read from `playlists` and not from `websites`, which is a mirror of this now — see `mirrorWebsites`
	below for what that key still is and who still reads it. Reading the mirror instead would be one
	turn of the run loop behind at the worst moment: a screen that has just added, deleted or reordered
	a website asks this in the same pass, and would be told the list as it was.

	No setter. There was one, and every caller of it was writing a whole list back to say one thing —
	change this website, drop that one, put this at the end — which is a shape that cannot say *which
	playlist* any of it happened in. The four verbs below say it instead.
	*/
	var all: [Website] { Defaults[.playlists].flatMap(\.websites) }

	/**
	Which website `display` is showing, and the only two ways to ask.

	Every reader of "what is up on which screen" comes through here, so there is one derivation of the
	key. That is the part worth guarding rather than the dictionary itself: a per-display fact keyed by
	something a little different at each call site loses the invariant with nothing to see — the
	website's own display and the display its scene actually draws on are the same value until a
	display is unplugged, and then they are not.

	`Display.settingsKey(for:)` is the key `disabledDisplays`, `rotationModes`, `rotationIntervals` and
	`browsingDisplays` already use, so a display unplugged and plugged back in comes back to its own
	entry rather than to a stranger's — and its entry is still there, because nothing forgets one.
	*/
	func currentWebsiteID(on display: Display?) -> Website.ID? {
		Defaults[.currentWebsites][Display.settingsKey(for: display)]
	}

	/**
	Whether `website` is up on any screen.

	The question the display-less lists ask — the Websites window and the Shortcuts entity — neither of
	which is about one screen. It used to be asked of `website.effectiveDisplay`, the display the
	website was pinned to, and that was the right question only while a website belonged to a screen.
	A screen picks a list now: the display showing a website is whichever one selected the playlist
	holding it, which has nothing to do with the website's own `display` field. Asked the old way, a
	list drew its tick against the wrong row for every website whose playlist is shown anywhere but the
	main display — systematically, and on the normal configuration rather than an edge of it.

	It can also be true on more than one row at once, and that is not a defect either: two displays
	showing one playlist are two screens each with their own cursor, and both of those websites are up.

	**What it gives up**, so that it is a trade and not an oversight. A cursor entry outlives its
	display — deliberately, so a monitor unplugged at night comes back in the morning showing what it
	was showing — and `scheduled` reads an entry naming a website that is gone as "this display has not
	started". So an entry left by an unplugged display can put a tick on a row nothing is currently
	drawing. That is one stale row against every row being wrong, and the direction of the error is the
	safe one: it over-reports what is showing rather than under-reporting it, and "Set as Current"
	beside it is not disabled by anything the user would want.
	*/
	func isShowing(_ website: Website) -> Bool {
		Defaults[.currentWebsites].values.contains(website.id)
	}

	/**
	Give what a display that has just gone away was showing to the screen its website lands on.

	The eviction rule, stated as a write. A website pinned to a departed display moves to the main one
	when the user has asked for that, so two wallpapers now claim one desktop, and the arriving one
	takes it — `showingIndex` argues for that at length. It used to have to be a tie-break, because the
	two claims were two `Bool`s on two websites and neither could be given up without giving up the
	other. They are two dictionary entries now, so the answer can simply be written into the entry of
	the screen the website landed on.

	**Nothing is forgotten here.** The departed display keeps its own entry, for the same reason
	`rebuildScenes` keeps `disabledDisplays`, `rotationModes` and `rotationIntervals` for it: the user
	picked that wallpaper for that screen. Unplug a monitor at night and plug it in in the morning and
	it has to come back showing what it was showing, exactly as it comes back switched off or set to
	rotate hourly. Browsing Mode is the one that cannot survive its display, and it is the odd one
	because it means "somebody is typing on this screen right now", which stops being true when the
	screen is gone. Which website is up does not stop being true, it stops being visible.

	`departed` is the displays whose scenes were just torn down, and it has to be, rather than "every
	stored key with no scene". The second reading fires again on every rebuild — every edit to the
	website list, every wake, every display change — for as long as that display stays unplugged, so it
	would put the evicted website back on the landing screen each time the user rotated away from it.
	It also writes on every one of those passes, and the write republishes into the rebuild that made
	it. Taken from the tear-down, this happens once, at the moment the cable comes out, which is what
	"the arriving wallpaper takes the screen" means.
	*/
	func handOverCurrentWebsites(from departed: [Display?]) {
		let cursors = Defaults[.currentWebsites]
		var updated = cursors

		for display in departed {
			guard
				let id = cursors[Display.settingsKey(for: display)],
				let website = all[id: id],
				website.isShowable
			else {
				continue
			}

			updated[Display.settingsKey(for: website.effectiveDisplay)] = id
		}

		guard updated != cursors else {
			return
		}

		Defaults[.currentWebsites] = updated
	}

	/**
	The normalized addresses of the websites that still have no title.

	`recordObservedTitle` runs on every `document.title` a live page writes, and reading `all` there is
	a JSON decode of the whole website list followed by a `URLComponents` parse per entry — all of it
	ahead of the guard that makes the call a no-op. A page with a clock, an unread count or a track
	name in its title rewrites it once a second for as long as the wallpaper is up, and every one of
	those was paying for the whole table.

	Kept here rather than worked out per call because it is derived from the list, and the list already
	has one place where every route to it meets: the publisher below. Nothing else may write this, and
	nothing else needs to — `Defaults.publisher` sees the mirror, which is written from every change to the
	playlists whatever made it.

	Subscribed with `ObservationOptions.initial`, which is `Defaults.publisher`'s default, so this is
	filled from the stored list before `init` returns rather than at the first edit.
	*/
	private var addressesAwaitingTitle = Set<URL>()

	/**
	Keep `websites` holding exactly what the playlists hold, in their order.

	The key is a mirror rather than a store now, with one writer — this — and no reader that knows it.
	That is what makes moving the store cost one function instead of a sweep: `Events` decides from it
	which scenes a change reached, `DisplayPanelModel` builds a column from it, `Intents` answers
	Shortcuts out of it, `ScrollRestoration` and `CropSelection` look a website up in it, and every one
	of them goes on working unedited and unaware. Those readers move to the playlists as their own
	changes reach them, and the day the last one has, this function and the key both go.

	It also keeps the promise the key's own comment already makes: both keys hold the same websites, so
	somebody who runs this build and goes back to the one before it finds their list where they left
	it.

	Written only when it differs, because the write republishes — `Events` treats every change to this
	key as a possible reason to rebuild a page — and a mirror that reposts an identical list on every
	playlist edit would make each one cost two.
	*/
	private static func mirrorWebsites(of playlists: [Playlist]) {
		let websites = playlists.flatMap(\.websites)

		guard Defaults[.websites] != websites else {
			return
		}

		Defaults[.websites] = websites
	}

	private init() {
		setUpEvents()
	}

	private func setUpEvents() {
		Defaults.publisher(.playlists, options: [])
			.sink { change in
				Self.mirrorWebsites(of: change.newValue)
			}
			.store(in: &cancellables)

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
	stopped rotation working on more than one screen: each tick of one display's rotation wiped the
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
		let display = website.effectiveDisplay

		// Before the mark moves rather than after, which is the order the panel already used: the
		// change reaches the scenes through a publisher on the next turn of the run loop, so a display
		// switched on here is already on by the time the page it should be showing is worked out.
		if
			switchingDisplayOn,
			AppState.shared.scenes.first(where: { $0.display == display })?.isDisabledForDisplay == true
		{
			AppState.shared.setDisplayEnabled(true, on: display)
		}

		// One assignment, and it can only reach one display's answer. What it replaced rewrote the
		// whole website list to move one mark, which is why the mark could travel: the sweep grouped by
		// `effectiveDisplay`, so it was free to clear a flag belonging to a screen nobody had asked
		// about. Nothing here can touch another key.
		//
		// A website that has since been removed leaves a name nothing answers to, which `scheduled`
		// already reads as "this display has not started" and answers with the top of its list — the
		// same place the sweep's repair left it, at no cost and with nothing to run.
		Defaults[.currentWebsites][Display.settingsKey(for: display)] = website.id
	}

	/**
	Change one website in place.

	The read-modify-write around the stored list was spelled out at all seven call sites, which is
	seven chances to write back a list built from a stale read.
	*/
	func update(_ id: Website.ID, _ change: (inout Website) -> Void) {
		Defaults[.playlists] = Defaults[.playlists].map {
			var playlist = $0
			playlist.websites = playlist.websites.modifying(elementWithID: id, update: change)
			return playlist
		}
	}

	/**
	Add a website to a playlist, or to the default one.

	`playlist` is what the management page passes: a website added while looking at a list belongs to
	that list, and every other route in — the gallery, a `nifro://` command, the Shortcuts action, the
	share extension — has no list in hand and means the one every display falls back to.

	The fallback also covers the case the playlists are missing entirely, which is not reachable
	through the app but is reachable by editing the stored preferences, and the cost of being wrong
	about it is a website added to nothing at all.
	*/
	func add(_ website: Website, to playlist: Playlist.ID? = nil) {
		var playlists = Defaults[.playlists]
		let index = playlist.flatMap { id in playlists.firstIndex { $0.id == id } }
			?? playlists.firstIndex(where: \.isDefault)

		if let index {
			playlists[index].websites.append(website)
		} else {
			playlists.append(Playlist(name: Playlist.defaultName, websites: [website], isDefault: true))
		}

		// The order here is important.
		Defaults[.playlists] = playlists

		// Marked, not shown. A new website has to hold its display's mark or that display has none,
		// but putting something in the list is not a request to look at it — a display the user
		// switched off stays off, and the gallery installing several at once does not flick a screen
		// on per website. The screens that do mean "show this now" say so with their own
		// `makeCurrent` afterwards.
		makeCurrent(website, switchingDisplayOn: false)
	}

	/**
	Add a website from a URL.

	Optionally, specify a title. If no title is given or if the title is empty, a title will be automatically fetched from the website.
	*/
	@discardableResult
	func add(_ websiteURL: URL, title: String? = nil, to playlist: Playlist.ID? = nil) -> Website {
		var website = Website(
			id: UUID(),
			isCurrent: true,
			url: websiteURL,
			usePrintStyles: false
		)

		// Set before the website is stored rather than written back through a binding afterwards. A
		// binding into the list was what this used to hand back, and a binding is a second way to write
		// a website — one that names no playlist, so it could only ever have written the mirror.
		if let title = title?.nilIfEmptyOrWhitespace {
			website.title = title
		}

		add(website, to: playlist)

		if website.title.isEmpty {
			fetchTitleIfNeeded(for: website.id, at: website.url)
		}

		return website
	}

	/**
	Remove a website.
	*/
	func remove(_ website: Website) {
		Defaults[.playlists] = Defaults[.playlists].map {
			var playlist = $0
			playlist.websites = playlist.websites.removingAll(website)
			return playlist
		}
	}

	/**
	The websites that should be on screen right now, before any question of which display.

	Both of the places that route by display start here, so a wallpaper the user has said should go
	away with its unplugged display goes away once rather than in two places that could disagree.
	*/
	@MainActor
	var showable: [Website] { all.filter(\.isShowable) }

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
			let website = all.first(where: { $0.url.normalized() == url.normalized() }),
			website.title.isEmpty
		else {
			return
		}

		update(website.id) {
			$0.title = title
		}
	}

	/**
	Fetch the title for a website in the background if the existing title is empty.
	*/
	private func fetchTitleIfNeeded(for id: Website.ID, at url: URL) {
		Task {
			let metadataProvider = LPMetadataProvider()
			metadataProvider.shouldFetchSubresources = false

			guard
				let metadata = try? await metadataProvider.startFetchingMetadata(for: url),
				let title = metadata.title
			else {
				return
			}

			// By id, because this comes back seconds later: the website may have been moved to another
			// playlist, or deleted, in between. A binding held across that wait would write it back.
			update(id) {
				$0.title = title
			}
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
	func add(to playlist: Playlist.ID? = nil) -> Website.ID? {
		guard let parsedURL = URL(string: url) else {
			return nil
		}

		let website = WebsitesController.shared.add(parsedURL, title: name, to: playlist)

		WebsitesController.shared.update(website.id) {
			$0.css = css ?? ""
			$0.javaScript = javaScript ?? ""
			$0.zoom = zoom
			// Everything the entry carries is a starting point. From here on the website is the user's:
			// the Sound item in the menu writes to this same field, and nothing puts the entry's answer
			// back. Whatever the menu shows a tick against is what the page is actually doing.
			$0.audio = playsSound ? .unmuted : .muted
			$0.reloadInterval = reloadInterval
		}

		return website.id
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

		// Nothing is assigned to a display. It used to be: the Nth of these went to the Nth attached
		// display, because a scene existed only for a display some website named, so the second screen
		// was blank unless something was pinned to it. Scenes come from `Display.all` now, so every
		// attached display has one whether or not a website names it, and the pinning would be a
		// decision made on the user's behalf — one they then have to find and undo before they can use
		// these eight as the single list they look like.

		// Adding makes each one current in turn, so without this the wallpaper would be whichever was
		// added last rather than the first of a list that is ordered on purpose.
		guard let first = installed.first.flatMap({ all[id: $0] }) else {
			return
		}

		makeCurrent(first)
	}
}

extension WebsitesController {
	/**
	Turn the stored website list into playlists, once.

	Websites with a display of their own become a playlist bound to that display; everything else
	becomes the default playlist. Per-display settings — `rotationModes`, `rotationIntervals`,
	`disabledDisplays` — are keyed by display and stay exactly where they are, because they describe
	the screen and not what is on it.

	**Guarded on a flag of its own, not on the playlist list being empty.** No playlists is a state the
	user can reach and stay in, and a migration that read that as "not done yet" would rebuild their
	playlists out of a website list they stopped editing long ago, every launch, for as long as they
	left it that way. `installFeaturedWebsitesIfNeeded` above makes the same guard for the same reason;
	stating it again rather than pointing at it, because the consequence here is worse. Deleting what
	that installs undoes it. What this writes is everything the user has.

	**Nothing here writes `websites`.** It is read and left as it was, so somebody who runs this build
	and goes back to the previous one still has their list, and so anything that looks wrong about the
	playlists can be checked against what they were made from. That key goes when its last reader does,
	which is not this change.

	The grouping itself is `playlistMigration`, over in a file the package target compiles, so the case
	this cannot be run against — two displays, a list built by hand — is the case `swift test` covers.
	Everything left here is naming and lookup, both of which need the app.
	*/
	func migrateToPlaylistsIfNeeded() {
		guard !Defaults[.hasMigratedWebsitesToPlaylists] else {
			return
		}

		Defaults[.hasMigratedWebsitesToPlaylists] = true

		// The stored key, not `all` — which reads the playlists this is about to write, and so would
		// hand back an empty list and migrate nothing.
		let websites = Defaults[.websites]

		Defaults[.playlists] = playlistMigration(displays: websites.map(\.display)).map { group in
			let members = group.websites.map { websites[$0] }

			guard let display = group.screen else {
				return Playlist(
					name: Playlist.defaultName,
					websites: members,
					isDefault: true
				)
			}

			// Asked once, here, and stored — which is the only moment it can be asked at all. A display
			// that is not attached right now answers `<Unknown name>`, and that is genuinely all this
			// app has ever known about it: what is stored against a website is a `Display`, and a
			// `Display` is a UUID. Resolving it later would not know more, it would only be wrong in
			// front of the user.
			let name = display.localizedName

			return Playlist(
				name: name,
				websites: members,
				boundDisplay: DisplayBinding(id: display.id, nameWhenBound: name)
			)
		}
	}
}
