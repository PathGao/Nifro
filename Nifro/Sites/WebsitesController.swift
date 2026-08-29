import SwiftUI
import LinkPresentation

/**
Three things mean "what that screen is showing", and they differ on purpose. Named here because every
question that has to pick one of them is answered in this file.

- **The mark.** `Defaults[.currentWebsites]`, one entry per display: what a display was *told* to
  show. It outlives what it names — nothing clears it when a website is deleted or a monitor is
  unplugged, deliberately, so a monitor plugged back in comes back showing what it was showing.
- **The display's answer.** `WallpaperScene.website`: the mark resolved by `scheduled(for:)` against
  what that display's playlist is offering this hour. It differs from the mark whenever the mark is
  unreachable — a website added and marked but never shown, a mark naming a website since deleted, an
  hour that has ended.
- **The page.** `WallpaperScene.loadedWebsiteID`: what the web view actually has. It lags the answer
  for the length of a swap.

Ask the mark where a display is *standing* — stepping, the shuffled order, what to write. Ask the
answer whether a website is on a screen, which `isShowing` and `switchOffDisplaysShowing` do; asking
the mark for that is the bug those two were rewritten out of. Ask the page only about loading.
*/
@MainActor
final class WebsitesController {
	static let shared = WebsitesController()

	private var cancellables = Set<AnyCancellable>()

	/**
	One shuffled order per display, so Random on one screen leaves the other where it was.

	This held an `AnyIterator` per display until Random became shuffle, and an iterator is exactly what
	a shuffled order must not be: it knows what it will hand out next and will not say, so the chooser
	in the panel could not list what was coming and Previous could not walk back into it. A materialised
	order is the same promise — every website once before any of them twice — written down where it can
	be read. `Rotation.swift` holds the two rules for making one and keeping it.

	**Keyed by `Display.settingsKey(for:)` and not by `Display?`.** The iterator was keyed by the
	optional, and `nil` and `Display.main` are two keys for one screen: whichever caller reached this
	with the concrete display got a second order over the same websites, and "no repeats until the list
	is done" quietly stopped being true. `AppState.actingScene` had to return a whole scene rather than
	the display under the pointer to keep that from happening, and said so in a comment. This is the key
	`currentWebsites`, `currentPlaylists`, `rotationModes`, `rotationIntervals`, `disabledDisplays` and
	`browsingDisplays` all use, so the screen has one name here as it does everywhere else.

	**In memory, and nowhere else.** An order is a plan for the next few hours, and a plan a relaunch
	restores is a plan made for a day that has ended. What does survive is the mark, so a fresh order
	is made around the website already up — see `shuffledOrder(of:startingWith:)`, which is the whole of
	why a relaunch does not make the wallpaper jump.

	The playlist the order was made for is kept beside it because two disjoint lists can be the same
	*size*, and nothing else about the websites would say the display had been pointed somewhere new.
	`ordered(_:on:)` is the only reader of either field, and argues the rest of it there.
	*/
	var shuffledOrders = [String: ShuffledOrder]()

	struct ShuffledOrder {
		let playlist: Playlist.ID?
		let websites: [Website.ID]
	}

	@MainActor let thumbnailCache = SimpleImageCache<String>(diskCacheName: "websiteThumbnailCache")

	/**
	All websites, in the order the playlists hold them.

	`playlists` is the whole of where a website is stored. The `websites` key it replaced is deleted,
	along with the conversion that was its last reader.

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
	several times a second — `DisplayPanelModel.startLiveRefresh` is where how often is settled.
	`eligible(for:)` next door does read it, and is the only place that does.
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
	Whether `website` is on a screen at this moment.

	The question a caller with no display of its own has to ask — the Websites window's list, which is
	one list for every screen, and `WebsiteAppEntity.isCurrent`, which Shortcuts reads off an entity
	that is a website and nothing else. It used to be asked of the display the website was pinned to,
	and that was the right question only while a website belonged to a screen. A screen picks a list
	now: the display showing a website is whichever one selected the playlist holding it.

	**The answer and not the mark**, in the header's words, and both ways of getting that wrong were on
	one Mac at once. Adding a website marks it without showing it — `add(_:to:)` ends in
	`makeCurrent(…, switchingDisplayOn: false)` and says why — so the mark ticked a website no screen
	had taken up. And a mark outlives the website it names, because `remove(_:)` does not clear it, so
	a website deleted weeks earlier held the one tick in the window while the wallpaper actually up had
	none. Neither is worth fixing by tidying the dictionary: pruning it is what would take the
	unplugged monitor's page away.

	`isSwitchedOff` is the second half and is not implied by the first. A switched-off scene keeps its
	`website` — `rebuildScenes` assigns it before it asks whether the display is off, and `suspend()`
	releases the web view without touching it — so the answer outlives the screen going dark, and this
	is what "showing nothing" means: the app-wide switch folded together with the display's own power
	button, for the reason `SwitchedOffTests` gives.

	During a swap the answer has moved and the page has not, so the tick names the arriving website for
	a second or two. That is the right reading for a list of wallpapers — the display's answer *has*
	changed — and a caller that wants the page has `loadedWebsiteID`.

	True of two websites at once when two displays are showing two different ones, and true once when
	both are showing the same one. "On a screen" is the whole of the claim, and no caller that cannot
	name a display can be given a narrower one.
	*/
	func isShowing(_ website: Website) -> Bool {
		AppState.shared.scenes.contains {
			!$0.isSwitchedOff && $0.website?.id == website.id
		}
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

				// The shuffled orders used to be thrown away here, on "the flattened website ids
				// changed", and that condition was wrong in both directions at once. Too broad: a
				// website added to a list no display is showing, or a drag that only reordered one,
				// restarted every display's shuffle over an edit that could not reach any of them —
				// and list order is nothing at all to a shuffle. Too narrow, which is the half that
				// was reported: pointing a display at a *different playlist* adds and removes no
				// website anywhere, so the flattened ids were identical, nothing was reset, and Random
				// went on drawing from the list the user had just switched away from.
				//
				// There is no reset here now, and no reset anywhere else either. An order is asked
				// whether it still describes its display at the moment it is *read* rather than when
				// some key moves — `ordered(_:on:)` is where, and it is one rule covering the added
				// website, the deleted one, the playlist switch, and the one no publisher can announce
				// at all: a website falling in or out of its scheduled hours.
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
	later on a website nobody had chosen. Asked here because here is where all of those meet — Next,
	Previous and Random are three verbs with three entry points each and all nine end in this method,
	so the answer is inherited rather than repeated nine times and forgotten in six of them.

	Asked rather than answered: `AppState.wakeDisplay` is what a request to see something means, and
	this is the only caller left. Pointing a display at a playlist used to be the other one — the same
	request one grain coarser, writing a different key, so it had to remember the waking separately and
	for a while did not. It is not a request of its own any more. Choosing a playlist commits nothing;
	choosing a website out of it is the commit, and it arrives here.

	**Which is why the playlist is written from this method.** The two keys say one thing between them —
	show this page, on this screen — and written apart they were briefly disagreeing on purpose: the
	playlist moved, the mark deliberately did not, and the wallpaper jumped to whatever the new list
	happened to hold first. Here they move together, in one turn of the run loop, so the sinks in
	`Events` that watch the pair never see a display pointed at a list it is not showing a page from.

	- Parameter playlist: the list `website` was chosen out of, where the caller is offering a choice
	between lists. `nil` — every caller but the panel — leaves the display pointed where it was, which
	is what a rotation tick, a Shortcuts action and a `nifro://` command all mean: they step within the
	list the display already has.
	- Parameter switchingDisplayOn: `false` where the mark is bookkeeping rather than a request to
	look at something. Adding a website has to leave *some* website marked on its display, and that is
	not a reason to light up a screen the user switched off.
	*/
	func makeCurrent(_ website: Website, on display: Display?, from playlist: Playlist.ID? = nil, switchingDisplayOn: Bool = true) {
		// Before the mark moves rather than after, which is the order the panel already used: the
		// change reaches the scenes through a publisher on the next turn of the run loop, so a display
		// switched on here is already on by the time the page it should be showing is worked out.
		if switchingDisplayOn {
			AppState.shared.wakeDisplay(display)
		}

		// Two assignments now, and neither can reach any display's answer but this one. What they
		// replaced rewrote the whole website list to move one mark, which is why the mark could travel:
		// the sweep grouped the list by the display each website was pinned to, so it was free to clear
		// a flag belonging to a screen nobody had asked about. Nothing here can touch another key, and
		// the two keys below are one display's two halves of the same sentence.
		//
		// A website that has since been removed leaves a name nothing answers to, which `scheduled`
		// already reads as "this display has not started" and answers with the top of its list — the
		// same place the sweep's repair left it, at no cost and with nothing to run.
		let key = Display.settingsKey(for: display)

		// The list before the page, so that a sink reading both keys — `Events` merges them into one —
		// reads the page as belonging to the list it was chosen from whichever key it wakes on.
		if let playlist {
			Defaults[.currentPlaylists][key] = playlist
		}

		Defaults[.currentWebsites][key] = website.id
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
	Switch off every display showing one of these websites.

	**The rule every deletion in the app obeys, and the reason it needs saying.** Take a website out of
	the list and the mark naming it names nothing, which `showingPosition` reads as "this display is at
	the top of its list" — so the screen moves on to whatever sorts first. Deleting one website changed
	the wallpaper to a different one, chosen by the app, indistinguishable from a rotation tick.
	Removing what a screen is showing switches that screen off instead: there is no replacement the app
	could pick that the user asked for.

	Off means the display's own power switch — `disabledDisplays`, through the one verb that writes it
	— and not an emptied mark, which is the substitution again one rotation tick later: a display with
	nothing marked is a display at position zero, and the clock is still armed. Switched off, `load`,
	both timers and the menu bar band all refuse, for the reason `SwitchedOffTests` gives.

	**"Showing" is the answer and not the mark, exactly as in `isShowing`.** A display whose mark is a
	ghost is showing whatever `scheduled` resolved that ghost into, and deleting *that* website has to
	switch it off. Asked the other way it would not match, the display would stay on, and what happened
	next is the substitution this function exists to stop.

	Nothing here asks whether the display is already off, unlike `isShowing`: switching off a display
	that is off is the same write and the same suspend.

	The way back is the power button under that display's picture in the panel, which is where a
	display switched off any other way is turned back on, and picking a website for that display from
	the panel does it too — `makeCurrent` wakes the display it writes.
	*/
	func switchOffDisplaysShowing(_ websites: Set<Website.ID>) {
		for scene in AppState.shared.scenes {
			guard
				let showing = scene.website?.id,
				websites.contains(showing)
			else {
				continue
			}

			AppState.shared.setDisplayEnabled(false, on: scene.display)
		}
	}

	/**
	Switch every display off.

	For the deletion that takes everything: Clear All Website Data. Asking which displays are showing
	something about to be deleted is the same answer as "all of them" when the answer is everything.

	One caller and kept separate from `switchOffDisplaysShowing` anyway, because the two say different
	things and the shorter one is not a special case of the other running out of arguments: handing an
	empty set to that would switch nothing off, which is the opposite of what "everything is going"
	means. Restore All Settings was the second caller until it stopped deleting websites.
	*/
	func switchOffEveryDisplay() {
		for scene in AppState.shared.scenes {
			AppState.shared.setDisplayEnabled(false, on: scene.display)
		}
	}

	/**
	Remove a website.

	The switch-off first, because it reads the entry the removal is about to orphan and because that is
	the order the rule is written in: close the screen, then delete. Here rather than at the two callers
	— the row's Delete and the Shortcuts action — so a third one inherits it.
	*/
	func remove(_ website: Website) {
		switchOffDisplaysShowing([website.id])

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
			let address = url?.normalized(),
			addressesAwaitingTitle.contains(address),
			let title = title.trimmed.nilIfEmpty,
			let website = all.first(where: { $0.url.normalized() == address }),
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

			// The entry's interval is an override or it is nothing. An entry that names none leaves the
			// website inheriting, and its interval field is left at what it starts at rather than set to
			// a number nobody asked for — the switch and the number are separate now, and writing the
			// number while the switch is off is the shape this change exists to remove.
			if let reloadInterval {
				$0.overridesReloadInterval = true
				$0.reloadInterval = reloadInterval
			}
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
	Throw the whole list away: every playlist, every website, and every key that named one — and
	switch the displays off first, because a screen whose website is being deleted is a screen with
	nothing to show and the app does not choose the next one.

	The three writes are one function because they are one fact. `playlists` is the whole of where a
	website is stored, and `currentWebsites` and `currentPlaylists` are per-display keys whose values
	are a website and a playlist out of it. Emptying the first and leaving either of the other two is a
	display pointed at a website that does not exist or at a list that does not exist, and neither has
	a symptom until somebody plugs in a second monitor. Written here, in one place, so that the answer
	is the same for all three rather than two call sites that each remembered a different subset.

	**Not a sweep over what is left.** The two housekeeping passes in `App.swift` refuse an empty
	website list on purpose, and they are right to: "every website is gone" read off a list is far
	likelier to be a bad read than the truth, and what those passes delete cannot be put back. Here it
	is not a reading. It is what the user asked for.

	*/
	func removeEverything() {
		// Before the three writes, and the same order as `remove`: every website is going, so every
		// screen showing one is a screen with nothing to show. Reading which is pointless when the
		// answer is all of them.
		switchOffEveryDisplay()

		Defaults[.playlists] = []
		Defaults[.currentWebsites] = [:]
		Defaults[.currentPlaylists] = [:]
	}

	/**
	Put the shipped websites in if that has never been done.

	One line, and it kept its name and its callers: this was three, running two conversions before the
	install in an order that was the whole reason the method existed. Both conversions are deleted —
	there is no older shape left to convert from — and what is left is the install's own guard.
	*/
	func prepareWebsiteStorage() {
		installFeaturedWebsitesIfNeeded()
	}

	/**
	Build the state a fresh install has: the default playlist, holding the websites Nifro ships with.

	One path, and the Advanced pane's Add the Default Playlist is now the only caller. It was the end of
	`RestoreDefaults.perform` too, back when a restore emptied the domain and had to put something back;
	a restore keeps the websites now, so getting the shipped list is this button and nothing else.

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

		prepareWebsiteStorage()
	}
}
