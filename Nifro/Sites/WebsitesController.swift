import SwiftUI
import LinkPresentation

@MainActor
final class WebsitesController {
	static let shared = WebsitesController()

	private var cancellables = Set<AnyCancellable>()

	/**
	One shuffled order per display, so Random on one screen leaves the other where it was.

	Keyed by display rather than one iterator over the whole list, for the same reason the cursor is:
	each display walks its own playlist, and one iterator shared between them would let Random on the
	screen in front of you move the wallpaper on the one behind you.
	*/
	var randomIterators = [Display?: AnyIterator<Website>]()

	@MainActor let thumbnailCache = SimpleImageCache<String>(diskCacheName: "websiteThumbnailCache")

	/**
	All websites, in the order the playlists hold them.

	`playlists` is the whole of where a website is stored. The `websites` key it replaced is read once
	by `migrateToPlaylistsIfNeeded` and by nothing else ever again — see `Constants.swift` for what is
	left of it.

	No setter. There was one, and every caller of it was writing a whole list back to say one thing —
	change this website, drop that one, put this at the end — which is a shape that cannot say *which
	playlist* any of it happened in. The four verbs below say it instead.
	*/
	var all: [Website] { Defaults[.playlists].flatMap(\.websites) }

	/**
	Which website `display` is showing, and the only two ways to ask.

	Every reader of "what is up on which screen" comes through here, so there is one derivation of the
	key. That is the part worth guarding rather than the dictionary itself: a per-display fact keyed by
	something a little different at each call site holds a different invariant perfectly and says
	nothing about screens, with no symptom until somebody attaches a second one.

	`Display.settingsKey(for:)` is the key `disabledDisplays`, `rotationModes`, `rotationIntervals` and
	`browsingDisplays` already use, so a display unplugged and plugged back in comes back to its own
	entry rather than to a stranger's — and its entry is still there, because nothing forgets one.
	*/
	func currentWebsiteID(on display: Display?) -> Website.ID? {
		Defaults[.currentWebsites][Display.settingsKey(for: display)]
	}

	/**
	Which playlist `display` is showing, out of `playlists`.

	Both readings of "no entry" end in the default playlist, and they are different readings. A display
	the user has never picked for has no entry at all, which is the ordinary case on a fresh install and
	on every monitor plugged in afterwards. A display whose stored playlist has since been deleted has
	an entry that names nothing, and answering that with an empty picker would leave the screen blank
	with no way back from the panel. The default playlist is the one thing every picker offers — it
	refuses a binding so that this can be true — so it is the answer to both.

	`playlists` is handed in rather than read here because the panel already has it: `Defaults[.playlists]`
	decodes every website in every list, and this is asked once per display on a popover that refreshes
	twelve times a second. `eligible(for:)` next door does read it, and is the only place that does.
	*/
	func playlist(for display: Display?, in playlists: [Playlist]) -> Playlist? {
		guard
			let id = Defaults[.currentPlaylists][Display.settingsKey(for: display)],
			let chosen = playlists[id: id]
		else {
			return playlists.first(where: \.isDefault)
		}

		return chosen
	}

	/**
	Whether `website` is up on any screen.

	The question the display-less lists ask — the Websites window and the Shortcuts entity — neither of
	which is about one screen. It used to be asked of the display the website was pinned to, and that
	was the right question only while a website belonged to a screen.
	A screen picks a list now: the display showing a website is whichever one selected the playlist
	holding it, which has nothing to do with the screen that website was once pinned to. Asked the old
	way, a list drew its tick against the wrong row for every website whose playlist is shown anywhere
	but the main display — systematically, and on the normal configuration rather than an edge of it.

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
	The normalized addresses of the websites that still have no title.

	`recordObservedTitle` runs on every `document.title` a live page writes, and reading `all` there is
	a JSON decode of the whole website list followed by a `URLComponents` parse per entry — all of it
	ahead of the guard that makes the call a no-op. A page with a clock, an unread count or a track
	name in its title rewrites it once a second for as long as the wallpaper is up, and every one of
	those was paying for the whole table.

	Kept here rather than worked out per call because it is derived from the list, and the list already
	has one place where every route to it meets: the publisher below. Nothing else may write this, and
	nothing else needs to — `Defaults.publisher(.playlists)` fires on every change to the playlists
	whatever made it.

	Subscribed with `ObservationOptions.initial`, which is `Defaults.publisher`'s default, so this is
	filled from the stored list before `init` returns rather than at the first edit.
	*/
	private var addressesAwaitingTitle = Set<URL>()

	private init() {
		setUpEvents()
	}

	private func setUpEvents() {
		Defaults.publisher(.playlists)
			.sink { [weak self] change in
				guard let self else {
					return
				}

				let websites = change.newValue.flatMap(\.websites)

				addressesAwaitingTitle = Set(
					websites.lazy
						.filter(\.title.isEmpty)
						.map { $0.url.normalized() }
				)

				// We only reset the iterators if a website was added/removed.
				if websites.map(\.id) != change.oldValue.flatMap(\.websites).map(\.id) {
					randomIterators = [:]
				}
			}
			.store(in: &cancellables)
	}

	/**
	Make a website the current one on `display`.

	**The display is named by the caller rather than read off the website.** It used to be read off the
	website, and that worked for exactly as long as a website belonged to one screen. A display shows a
	playlist now and a playlist is offered to whichever displays its binding allows — the default one to
	all of them — so the same website is reachable from two columns, and asking the website which screen
	it is on answered with the screen it was pinned to before any of this. Picking a site in the second
	column would have moved the *first* column's wallpaper, and every rotation tick on a display showing
	the default playlist would have written the main display's entry: that display never advancing, and
	another one changing under nobody's hand. Every caller here knows the display it is acting for; the
	three that genuinely do not — a Shortcuts action, the list in the Websites window and adding a
	website from anywhere — pass `Display.main` themselves, where it is a stated fallback rather than a
	hidden one.

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
	func makeCurrent(_ website: Website, on display: Display?, switchingDisplayOn: Bool = true) {
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
		// whole website list to move one mark, which is why the mark could travel: the sweep grouped the
		// list by the display each website was pinned to, so it was free to clear a flag belonging to a
		// screen nobody had asked about. Nothing here can touch another key.
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

		// Marked, not shown, and on the display with the menu bar because that is the only display a
		// caller with no screen in hand can mean. Putting something in the list is not a request to
		// look at it — a display the user switched off stays off, and the gallery installing several at
		// once does not flick a screen on per website. The screens that do mean "show this now" say so
		// with their own `makeCurrent` afterwards.
		makeCurrent(website, on: Display.main, switchingDisplayOn: false)
	}

	/**
	Add a website from a URL.

	Optionally, specify a title. If no title is given or if the title is empty, a title will be automatically fetched from the website.
	*/
	@discardableResult
	func add(_ websiteURL: URL, title: String? = nil, to playlist: Playlist.ID? = nil) -> Website {
		var website = Website(
			id: UUID(),
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

		makeCurrent(first, on: Display.main)
	}
}

extension WebsitesController {
	/**
	Throw the whole list away: every playlist, every website, and every key that named one.

	The four writes are one function because they are one fact. `playlists` is the whole of where a
	website is stored; `currentWebsites` and `currentPlaylists` are per-display keys whose values are a
	website and a playlist out of it, and `redirectedAddresses` is filed under `website.id`. Emptying
	the first and leaving any of the other three is a display pointed at a website that does not exist,
	a display pointed at a list that does not exist, or a redirect nothing can ever apply — and none of
	the three has a symptom until somebody plugs in a second monitor or wonders why an address they
	fixed came back. Written here, in one place, so that the answer is the same for all four rather
	than three call sites that each remembered a different subset.

	**Not a sweep over what is left.** The two housekeeping passes in `App.swift` refuse an empty
	website list on purpose, and they are right to: "every website is gone" read off a list is far
	likelier to be a bad read than the truth, and what those passes delete cannot be put back. Here it
	is not a reading. It is what the user asked for.

	Nothing is done about the `websites` key. It is the pre-playlist list, read once by the migration
	and by nothing else in this build, and it is the only copy of what the user had before the
	conversion — keeping it is what `Constants.swift` argues for, and clearing today's list is not a
	reason to burn the record of the old one. It cannot come back on its own: the migration reads its
	own flag, and this leaves that flag set.
	*/
	func removeEverything() {
		Defaults[.playlists] = []
		Defaults[.currentWebsites] = [:]
		Defaults[.currentPlaylists] = [:]
		Defaults[.redirectedAddresses] = [:]
	}

	/**
	Build the state a fresh install has: the default playlist, holding the websites Nifro ships with.

	One path with two callers — restoring the whole app, and the button in Advanced that wants only
	this half of it. These two lines were the end of `RestoreDefaults.perform`, and a second control
	wanting the same state would have meant a second way to build it, with nothing making the two agree
	about the order they run in.

	**Only the install flag is forced.** `migrateToPlaylistsIfNeeded` keeps the position
	`RestoreDefaults` argued for and is left to its own guard, and that is the whole of what makes this
	safe to press from a settings pane. After a restore the flag went with the domain, so the migration
	runs against nothing and writes the empty default list the install then fills. Pressed from
	Advanced the flag is set, so the migration does nothing — which is what has to happen, because it
	assigns `playlists` outright and would take every list the user has made with it.

	**An existing default playlist is filled, not replaced and not doubled.** `add` puts each website
	into the default playlist it finds and makes one only when there is none, so "there is already one"
	and "there is not" are answered by the same code and neither of them can produce a second. What it
	costs is that pressing this with the shipped websites already in the list leaves a second copy of
	each — visible in the Websites window and undone by deleting them. The two alternatives were worse
	in a way that is not undoable at all: replacing a list somebody spent an evening arranging, or a
	button that silently does nothing and gives them no way to tell it apart from a button that broke.
	*/
	func installDefaultPlaylist() {
		Defaults[.hasInstalledFeaturedWebsites] = false

		migrateToPlaylistsIfNeeded()
		installFeaturedWebsitesIfNeeded()
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

	**Nothing here writes `websites`.** It is read and left as it was, which is now the only thing that
	ever happens to it: this is the key's last reader, and what it reads is the only copy of a list
	nothing else in the app can reach any more.

	**Everything lands in one playlist, including what was pinned.** Grouping the pinned websites into a
	playlist per display was the first shape of this, and it was wrong for the case it was built for:
	a display that was pinned to got a playlist of one, which is the state the whole refactor exists to
	end — a second screen whose chooser has a single entry. What the user has after this is one list of
	everything, which every display offers and each walks on its own. What they lose is the record of
	which screen a website used to be pinned to, and that record described a rule this build no longer
	has.
	*/
	func migrateToPlaylistsIfNeeded() {
		guard !Defaults[.hasMigratedWebsitesToPlaylists] else {
			return
		}

		Defaults[.hasMigratedWebsitesToPlaylists] = true

		// The stored key, not `all` — which reads the playlists this is about to write, and so would
		// hand back an empty list and migrate nothing.
		let stored = Defaults[.websites]

		// `map`, not `filter` or `compactMap`. Every stored entry becomes a member: this runs once,
		// against the only copy of a list the user built themselves, and an entry dropped here is
		// dropped for good.
		Defaults[.playlists] = [
			Playlist(
				name: Playlist.defaultName,
				websites: stored.map(\.website),
				isDefault: true
			)
		]
	}
}

/**
A website as the builds before playlists wrote it: the website itself, and the display it was pinned to.

`Website` has no display of its own any more — a website belongs to a playlist and a display picks a
playlist — and the pinning is exactly what `migrateToPlaylistsIfNeeded` above turns into playlists. So
it has to be read out of the stored payload rather than off the model, and this is the shape that
payload has. Nothing else reads it and nothing writes it at all.

`Website(from:)` is handed the same decoder rather than a nested container because the stored payload
is one flat object per website: the display sat beside the website's own fields, not inside them.
`encode(to:)` puts it back the same way. Nothing calls it — the key is read-only — and it is written
out anyway, because a `Codable` whose two halves disagree about the shape is a trap laid for whoever
does call it.
*/
struct PinnedWebsite: Hashable, Codable, Defaults.Serializable {
	var website: Website
	var display: Display?

	private enum CodingKeys: String, CodingKey {
		case display
	}

	init(from decoder: any Decoder) throws {
		website = try Website(from: decoder)
		display = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Display.self, forKey: .display)
	}

	func encode(to encoder: any Encoder) throws {
		try website.encode(to: encoder)

		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encodeIfPresent(display, forKey: .display)
	}
}
