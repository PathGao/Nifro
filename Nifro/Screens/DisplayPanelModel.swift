import AppKit
import SwiftUI

/**
What the panel draws, and the one place it is assembled.

Held apart from the view because the snapshots are asynchronous and the scenes are not: this waits
for the pictures and the columns arrive together, rather than popping in one at a time.

Held apart from the view because it also outlives it. The panel is one popover shown over and over,
and the columns it last drew are still here when it comes back — which is what lets a reopening start
at the right size instead of growing into it, and is also why `prepareForOpening` exists. The
pictures in those columns are the one part of them that must not be reused.
*/
@MainActor
final class DisplayPanelModel: ObservableObject {
	struct Column: Identifiable {
		let display: Display?
		let displayName: String
		let websiteID: Website.ID?
		let websiteName: String?
		let snapshot: NSImage?

		/**
		The websites this display can be pointed at: the members of the playlist the column is offering,
		in the order it offers them — see `choices(in:isCommitted:on:)`, which is where the playlist and
		the order are settled.

		It was the websites whose own `display` was this one, which is K17 — a display could only offer
		what already named it, so the second monitor's chooser had one item in it and the first launch
		had to pin a different site to each screen to make even that true.

		Carried on the column rather than looked up by the view, so a column is a finished description
		of one display and the view has nothing left to ask.
		*/
		let choices: [Website]

		/**
		The playlists this display may be pointed at, and the name of the one it is pointed at now.

		Every unbound playlist plus the ones bound to this display. That is the whole of what a binding
		does — it filters this list and nothing else, so two playlists bound to one display do not
		conflict and neither is preferred; both are offered here and the user picks. A playlist bound to
		a display that is not attached is in no picker at all, because a picker exists only for a
		display that has a column.

		The name rather than the id, because the control is a `Menu` drawing its own label and there is
		nothing here to tick. A display with no stored selection is showing the default playlist, so this
		reads "Default" rather than reading empty — the picker says what the screen is doing, and what it
		is doing is the fallback.
		*/
		let playlistChoices: [Playlist]
		let playlistName: String

		/**
		Everything this display's controls need to draw themselves.
		*/
		let isShowing: Bool
		let isMuted: Bool
		let rotationMode: RotationMode

		/**
		How long this display waits between websites. Only shown while it is actually rotating.
		*/
		let rotationIntervalMinutes: Double

		let canRotate: Bool

		/**
		Whether a page is on its way to this display.

		Per display, not per app. A load takes a few seconds, and locking the panel for all of them
		because one screen is fetching a page would make the other screen's controls unusable for
		something that is none of its business.
		*/
		let isLoading: Bool

		/**
		Why the app is showing nothing anywhere, in the app's own words, or `nil` when it is showing
		something.

		`isShowing` above is both switches at once, which is what the power button under the picture
		needs and not what the picture can say with it. Every display's is false while the app is off,
		so every column read "Switched off" — the power button's own phrase, on screens nobody had
		switched off — and pressing that button then recorded the display as off for real, so turning
		the app back on brought back a screen the user had never chosen to lose. Unplugging a laptop
		with "Deactivate while on battery" set is the case with nothing at all to press: every wallpaper
		goes, and until this the panel's whole account of it was four columns each blaming their own
		screen.

		A sentence rather than the reason, because the column is the only thing that will ever draw it
		and `AppState.DisabledReason` is not the panel's vocabulary. There is no control here to undo
		either state — the app has no "turn me back on" button anywhere, which is its own gap — so this
		is a reading and not a label on something.
		*/
		let disabledReading: String?

		/**
		That this display's page did not load, if it did not.

		Recorded per display since the app-wide slot was split, and read by nothing in this folder
		until now: a wallpaper URL that starts answering with an error reported itself in the tooltip of
		a menu bar icon nobody is pointing at, and nowhere else. The column named the website and drew
		the last picture that worked, both of them true and neither of them the answer to why the page
		on the desktop has stopped changing.

		Its own field rather than a fifth thing the picture area says, because a failed load does not
		have to take the picture away: swap loading keeps the page that worked up on purpose, so the
		honest column is that picture with a line above it saying the new one never arrived.
		*/
		let failure: String?

		// `nil` display means the main display — the one with the menu bar, not a display named in any
		// setting — and there is only ever one of those, so the display's own id is the identity when it
		// has one and a fixed stand-in when it does not.
		var id: String { display?.id.uuidString ?? "default" }
	}

	@Published private(set) var columns: [Column] = []

	/**
	The playlist a column is *browsing*, where that is not the one its display is showing.

	Choosing a playlist commits nothing. It changes which websites the chooser below it offers, and
	choosing one of those is the commit — which writes the display's playlist and its website together,
	in `WebsitesController.makeCurrent`. So this is the whole of what a playlist choice does, and it
	lives here rather than in `Defaults` because it is not a fact about the display, it is a fact about
	a popover that is open in front of it.

	What that buys is the defect it replaces. Picking a playlist wrote the stored key, the key reached
	`rebuildScenes` through `Events`, and the wallpaper jumped to whatever the new list happened to hold
	first — before the user had said which page they wanted, and with no way to look at a list without
	being moved to it. What it costs is stated and accepted: pointing a display at another playlist is
	done by choosing a website from that playlist. There is no "switch the list and keep this page".

	Keyed by `Display.settingsKey(for:)` and cleared on every opening, which is the same statement twice:
	a browse is one visit to one column. Reopening the panel shows what the display is committed to.
	*/
	private var browsedPlaylists = [String: Playlist.ID]()

	private var liveRefresh: Task<Void, Never>?

	/**
	Which opening of the panel the columns belong to.

	A snapshot is awaited, so a `refresh` begun for one opening can finish after the panel has been
	closed and opened again. Counting the openings is how a late arrival finds out it is late.
	*/
	private var openings = 0

	/**
	Keep the pictures moving while the panel is up.

	A single snapshot on open makes a wallpaper look like a screenshot of itself, which is the wrong
	thing to show for a page whose whole point is that it moves. What it costs to avoid that is a
	snapshot per display per pass, each a few tens of milliseconds of the main actor, plus a rebuild of
	the SwiftUI tree — so the rate is a trade against the panel's own responsiveness and not a frame
	rate to push up.

	**Six passes a second, which is the sleep below and the only place the number is written down.**
	It was 80ms, twelve and a half passes a second, under a comment here saying "a few a second" and
	another on `WallpaperScene.snapshot()` saying "roughly once a second" — three numbers, none of them
	each other, and the two prose ones both wrong. Everywhere else that has to mention how often the
	panel refreshes now points here rather than restating it, because a restated number is a number
	that goes stale on the day this one is tuned.

	Whether it runs at all is not decided here. `DisplayPanelController` owns both this call and
	`stopLiveRefresh`, and what it answers them from is whether the panel can be *seen* — not merely
	whether it is closed, which is what this comment used to claim was the same question. It is not:
	a transient popover self-closes on outside interaction and on nothing else, so it sat through a
	screen lock, the displays sleeping, a Space switch and Mission Control with this loop still
	photographing every display.
	*/
	func startLiveRefresh() {
		liveRefresh?.cancel()

		liveRefresh = Task { [weak self] in
			while !Task.isCancelled {
				await self?.refresh()

				// After the work rather than before it, so a slow refresh spaces itself out instead of
				// queueing up behind the last one.
				try? await Task.sleep(for: Duration.seconds(1) / 6)
			}
		}
	}

	func stopLiveRefresh() {
		liveRefresh?.cancel()
		liveRefresh = nil
	}

	/**
	Everything the panel opens with except the pictures.

	Synchronous, and that is the whole point of it. Every field of a column but the snapshot is a value
	already sitting in memory, so this costs nothing worth measuring. The snapshot is the one part that
	has to be photographed, at a measured 12.5ms a display, and photographing every display before the
	popover appears is a menu bar item that does not open for up to a fifth of a second after the click.

	So the panel opens on the click at the right size with the right names, and a bare rectangle stands
	in for each picture until the first refresh fills it in about a frame later. What it replaces is the
	pictures the columns are still holding, which are of what the displays showed the last time the
	panel was up: a real photograph of a real page, which is exactly why nobody reads it as stale.
	*/
	func prepareForOpening() {
		// Before the columns are rebuilt rather than after, so a snapshot already in the air for the
		// previous opening cannot land on top of what this just put up. `refresh` writes `columns` at
		// the end, after its awaits.
		openings += 1

		// A list somebody was looking at and did not choose from is not a decision, and an opening that
		// began where the last one was abandoned would be the panel remembering something the user does
		// not know it kept.
		browsedPlaylists.removeAll()

		let playlists = Defaults[.playlists]
		columns = AppState.shared.scenes.map { column(for: $0, snapshot: nil, playlists: playlists) }
	}

	/**
	Rebuild every column, pictures included.

	One after another rather than at once. A snapshot is a copy of a view that already exists, so it
	costs milliseconds, and a machine with more displays than that is not the case this is written for.
	*/
	func refresh() async {
		let opening = openings
		var built: [Column] = []

		// Read once for the whole pass rather than once per column. `Defaults[.playlists]` decodes every
		// website in every list on every read, and a column needs the whole set twice over — the list it
		// offers, and the one it is showing — so read inside `column(for:)` this would run at the panel's
		// refresh rate, multiplied by the number of displays. The websites this used to read are in
		// there now, so it is one read where it was one read. The columns are published together as one
		// array anyway, so a single read is also the only way they can agree with each other.
		let playlists = Defaults[.playlists]

		for scene in AppState.shared.scenes {
			// Between the displays and not only around the pass. Every snapshot is awaited, so a pass
			// begun while the panel was up can still be halfway down the displays when it goes away —
			// and the `while !Task.isCancelled` that started this loop is checked once per pass, not
			// once per display. Without this the close published one more set of columns after it,
			// photographed from a panel nobody was looking at any more.
			guard !Task.isCancelled else {
				return
			}

			built.append(column(for: scene, snapshot: await scene.snapshot(), playlists: playlists))
		}

		// The panel was closed and opened again while these were being taken, so they are pictures of
		// the previous opening and `prepareForOpening` has already put the right thing up. Dropping them
		// is the difference between a placeholder that fills in and a stale photograph that comes back.
		guard opening == openings else {
			return
		}

		columns = built
	}

	/**
	One display, described.

	The two things a column costs are both passed in. The snapshot because it has to be photographed:
	the panel is opened with `nil` and the refreshes fill it in. The playlists because reading them
	decodes every website in every list, and one pass builds a column per display off the same read.
	*/
	private func column(for scene: WallpaperScene, snapshot: NSImage?, playlists: [Playlist]) -> Column {
		let controller = WebsitesController.shared

		// Two playlists, and the difference between them is the whole of change A. `showing` is what
		// this display is committed to, and it is what the arrows step and what the interval walks.
		// `offered` is the list the chooser below draws from, which is the same thing until somebody
		// picks a playlist and does not pick a website out of it yet.
		let showing = controller.playlist(for: scene.display, in: playlists)
		let browsed = browsedPlaylists[Display.settingsKey(for: scene.display)].flatMap { playlists[id: $0] }
		let offered = browsed ?? showing

		return Column(
			display: scene.display,
			displayName: scene.display?.localizedName ?? String(localized: "Main Display"),
			websiteID: scene.website?.id,
			websiteName: scene.website?.menuTitle.nilIfEmpty,
			snapshot: snapshot,
			choices: choices(in: offered, isCommitted: offered?.id == showing?.id, on: scene),
			// `boundDisplay == nil` is every display and is the default a playlist is made with, so this
			// is "everything nobody has claimed, plus what this screen was given". The default playlist
			// refuses a binding outright, which is what keeps this from ever being empty.
			playlistChoices: playlists.filter { $0.boundDisplay == nil || $0.boundDisplay?.id == scene.display?.id },
			playlistName: offered?.name ?? String(localized: "No Playlist"),
			// `isSwitchedOff`, not the per-display switch under it. The column was the last reader
			// asking one of the two switches on its own, so with the app disabled — on battery, on a
			// locked screen, from the Disable shortcut — every wallpaper was gone and every column still
			// read "on". The button below then acted on that reading and switched the display off for
			// real, so turning the app back on brought back a screen the user had never switched off.
			isShowing: !scene.isSwitchedOff,
			isMuted: !scene.shouldPlaySound,
			rotationMode: scene.rotationMode,
			rotationIntervalMinutes: scene.rotationIntervalMinutes,
			// The set the arrows actually step through, and not a second count of what is on the display.
			// It was `onDisplay.count > 1` — every website naming this screen — while stepping went
			// through `eligible`, which narrows that by the schedule and by whether a website can be
			// shown at all. So a display with two websites and one of them unshowable lit both arrows
			// and did nothing when either was pressed, which is K24. One expression, asked twice.
			canRotate: controller.eligible(in: showing).count > 1,
			isLoading: scene.isLoading,
			disabledReading: Self.disabledReading,
			// Read here rather than in the view, with everything else the column says. The panel is the
			// second reader of this store and the first one a user ever sees.
			failure: AppState.shared.webViewError(on: scene.display)?.localizedDescription
		)
	}

	/**
	The websites a column offers, in the order it offers them.

	The playlist's own order, which is what a list is, except for one case: a display showing that list
	and set to Random offers the shuffled order instead, because for that display the order is the
	answer to "what is coming" — that is the whole of why shuffle is a decided order rather than an
	iterator, and a dropdown that would not say it would be hiding the one thing that changed.

	`isCommitted` is the reason a list being *browsed* is offered plainly even in Random. A display that is
	not pointed at a list has no order for it, and making one here would take the order it is actually
	walking and throw it away to describe a list it is not on. The order for that list is made when the
	display is pointed at it, which is the moment a website is chosen — and made around that website, so
	the first thing the dropdown says afterwards is the page that is up.

	Not narrowed by the schedule, in either case, which is what it did before this and is left alone:
	the chooser offers what the list holds, so a website outside its hours can still be asked for by
	hand. Rotation is where the hours apply. The Random order is the exception that proves it — it comes
	from `eligible`, so a site out of hours is missing from that one dropdown until its hours come round.
	*/
	private func choices(in playlist: Playlist?, isCommitted: Bool, on scene: WallpaperScene) -> [Website] {
		let controller = WebsitesController.shared

		guard
			isCommitted,
			scene.rotationMode == .random
		else {
			return playlist?.websites ?? []
		}

		return controller.ordered(controller.eligible(in: playlist), on: scene.display)
	}

	/**
	What the panel says when the app itself is off.

	One sentence each, and the second one is the reason this is not simply "off": the battery rule
	takes every wallpaper away without anybody having asked for it in that moment, and a column that
	will not name it leaves the user looking for a fault in their website. Neither sentence names a
	control, because there is none to name.
	*/
	private static var disabledReading: String? {
		switch AppState.shared.disabledReason {
		case .switchedOff:
			String(localized: "Nifro is off")
		case .onBattery:
			String(localized: "Off while this Mac is on battery")
		case nil:
			nil
		}
	}


	/**
	Hand the display's page over, or take it back.

	Through the app's own verb and not through `setBrowsingMode` beside it, which is the same flip
	minus the first-time explanation of what Browsing Mode is. This button is the most discoverable
	way into it and was the one route that said nothing.
	*/
	func toggleBrowsingMode(on display: Display?) {
		AppState.shared.toggleBrowsingMode(on: display)
	}

	/**
	Start framing the region shown on `display`.

	The panel closes first. Framing is a full-screen gesture against the wallpaper, and a popover
	sitting over it would be in the way of the thing being framed.
	*/
	func chooseRegion(on display: Display?) {
		guard
			let scene = AppState.shared.scenes.first(where: { $0.display == display }),
			let website = scene.website
		else {
			return
		}

		onClose?()
		WebsitesController.shared.makeCurrent(website, on: display)
		AppState.shared.beginCropSelection(on: scene)
	}

	/**
	Close the panel, then do the thing.

	In that order, and always: every one of these opens a window, and a popover left up in front of the
	window it just opened is the panel getting in the way of what it was asked for.
	*/
	func run(_ action: @escaping () -> Void) {
		onClose?()
		action()
	}

	/**
	Put the panel away. Set by whatever is showing it.
	*/
	var onClose: (() -> Void)?

	/**
	Everything a column's controls do, each one naming the display it acts on.

	The display is passed rather than assumed. That is the whole point of the panel: the menu it
	replaces had no way to say which screen it meant, so every action went to whichever one last held
	a flag.
	*/
	func step(_ direction: Step, on display: Display?) {
		// No waking here. Stepping a display that is switched off is how you wake it and this used to
		// say so itself, one line above the same answer inherited from `makeCurrent` — which is how the
		// column came to have two opinions about what pointing a display at a website means: this
		// button woke the display and the chooser beside it, going through `makeCurrent` alone, was
		// believed not to. Both go through `makeCurrent`, so both wake it, and there is one place left
		// to change when a third switch means off.
		switch direction {
		case .previous:
			WebsitesController.shared.makePreviousCurrent(on: display)
		case .next:
			WebsitesController.shared.makeNextCurrent(on: display)
		}

		Task {
			await refresh()
		}
	}

	enum Step {
		case previous
		case next
	}

	func cycleRotationMode(on display: Display?) {
		guard let scene = AppState.shared.scenes.first(where: { $0.display == display }) else {
			return
		}

		scene.rotationMode = scene.rotationMode.next
		scene.resetRotationTimer()
		objectWillChange.send()

		Task {
			await refresh()
		}
	}

	/**
	Set how many minutes `display` waits between websites.

	The number is put through `rotationInterval(entered:current:)` on the way in rather than trusted:
	this is a text field, so "0", "-3" and a number with nine digits in it are all one keystroke away,
	and each of them means a display that never changes again.

	No `resetRotationTimer` here — writing the key is what restarts the timers, through the publisher
	in `Events`, which also catches the same number being changed from anywhere else.
	*/
	func setRotationInterval(_ minutes: Double, on display: Display?) {
		guard let scene = AppState.shared.scenes.first(where: { $0.display == display }) else {
			return
		}

		scene.rotationIntervalMinutes = rotationInterval(entered: minutes, current: scene.rotationIntervalMinutes)
		objectWillChange.send()

		Task {
			await refresh()
		}
	}

	func toggleMuted(on display: Display?) {
		guard
			let scene = AppState.shared.scenes.first(where: { $0.display == display }),
			let website = scene.website
		else {
			return
		}

		WebsitesController.shared.update(website.id) {
			$0.audio = $0.audio == .unmuted ? .muted : .unmuted
		}

		Task {
			await refresh()
		}
	}

	func toggleShowing(on display: Display?) {
		guard let scene = AppState.shared.scenes.first(where: { $0.display == display }) else {
			return
		}

		// The same answer the column drew, so pressing the button means what the button says. Read off
		// the per-display switch it would have written the opposite of what a user pressing "on" while
		// the app was disabled had asked for.
		//
		// Switching a display on while the app is off records the setting and leaves the screen dark —
		// `setDisplayEnabled` says so, and it is the only honest answer available here: this button
		// cannot clear a Disable that came from the battery or the lock screen.
		AppState.shared.setDisplayEnabled(scene.isSwitchedOff, on: display)

		Task {
			await refresh()
		}
	}

	/**
	Show `website` on `display`.

	Both arguments, where there used to be neither. The display, because a website no longer settles
	which screen it is on: the same site is in the chooser of every display showing a playlist that
	contains it, and asking the website would have moved whichever screen it was pinned to instead of
	the one the user was pointing at. The website itself rather than its id, because the chooser is
	drawn from a playlist's own members and a playlist holds bodies — duplicating one makes copies with
	ids of their own, so looking the id up in the website list would find nothing.

	A switched-off display is woken by this, and nothing here says so: `makeCurrent` is where a request
	to see something answers that, and the arrows above this chooser reach it by the same door. Two
	sibling controls in one column had two answers about what picking a website means for as long as
	either of them wrote its own.

	**This is the column's only commit**, and the playlist rides with it. A list being browsed is handed
	over here and forgotten here, so the two keys move in one turn of the run loop and there is never a
	moment when the display is pointed at a list it is not showing a page from — which is exactly the
	moment the wallpaper used to jump in.
	*/
	func selectWebsite(_ website: Website, on display: Display?) {
		let key = Display.settingsKey(for: display)

		WebsitesController.shared.makeCurrent(website, on: display, from: browsedPlaylists[key])

		// Committed, so there is nothing left to be browsing: the column reads the same answer from the
		// stored key from here on, and a stale entry would go on winning over a playlist changed from
		// somewhere else while the panel stayed open.
		browsedPlaylists[key] = nil
	}

	/**
	Show `display`'s column the websites in a playlist.

	**And nothing else.** This wrote `currentPlaylists` and woke the display, which made choosing a list
	a decision the user had not finished making: the key reached `rebuildScenes` through `Events`, and
	the wallpaper moved to whatever that list happened to hold first before anybody had said which page
	they wanted. There was no way to look inside a list without being moved into it.

	So it does not write, and it does not wake either — nothing is being asked for yet, and a screen
	that lit up here would be answering a question with a look at a menu. `selectWebsite` below is the
	commit — it is directly above — and it inherits the waking from `makeCurrent`, where every
	request to see something meets.

	`objectWillChange` because the answer is held here rather than in `Defaults`, so nothing else will
	say it moved; `refresh` for the pictures, as everything in this file does.
	*/
	func selectPlaylist(_ id: Playlist.ID, on display: Display?) {
		browsedPlaylists[Display.settingsKey(for: display)] = id
		objectWillChange.send()

		Task {
			await refresh()
		}
	}
}
