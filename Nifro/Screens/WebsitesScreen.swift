import SwiftUI
import WebKit

/**
Two levels: the lists a display can be given, and what is in one of them.

It was one level, and the level it was missing is the whole of the change: a website used to carry the
display it belonged to, so a flat list was the shape of the model. A screen picks a list now, which
means there is a thing between the screen and the website that the user has to be able to name,
reorder, copy and throw away. That thing has no other home — the panel is a popover over the desktop
with room for a picker and not for management, and Settings is where switches live.

**Reordering is ordering.** Dragging a playlist above another says nothing about which display gets
it: a binding filters a display's picker and does nothing else, so two playlists bound to one screen
do not compete and there is no precedence for a drag to express. The order is the order the picker
lists them in, which is the only thing an order can mean here.

The window's own furniture — the toolbar's Add Website, the bottom bar's Clear Data — stays at the
root and reaches both levels, because both are about the window rather than about one list. Add
Website is the one that has to know where it is: `path.last` is the list the user is looking at, and
`nil` at the root means the one every display falls back to.
*/
struct WebsitesScreen: View {
	@Default(.playlists) private var playlists

	// The stack's path rather than a selection of its own, so that "which list is open" has one
	// answer. Add Website reads it to decide where a website lands, and a second state to say the same
	// thing is a second thing to keep in step with the back button.
	@State private var path = [Playlist.ID]()

	@State private var isAddWebsiteDialogPresented = false

	// Made here because here is what it is scoped to, and handed down rather than reached for. A row
	// that cannot ask for the record without being given it cannot outlive the window it belongs to.
	@State private var iconFailures = IconFetchFailures()

	var body: some View {
		NavigationStack(path: $path) {
			Form {
				List($playlists, editActions: .move) { playlist in
					PlaylistRow(
						playlist: playlist,
						duplicate: { duplicate(playlist.wrappedValue) },
						delete: { delete(playlist.wrappedValue) }
					)
				}
				.overlay {
					if playlists.isEmpty {
						Text("No Playlists")
							.emptyStateTextStyle()
					}
				}
				.accessibilityAction(named: "Add website") {
					isAddWebsiteDialogPresented = true
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Playlists")
			.navigationDestination(for: Playlist.ID.self) { id in
				// Through the stored list rather than captured at the moment the row was drawn, so a
				// rename or an edit made in here writes to the playlist that is still there. A playlist
				// deleted while open leaves nothing to draw, and the stack is popped rather than left
				// showing a list that no longer exists.
				if let playlist = $playlists[id: id] {
					PlaylistWebsites(playlist: playlist, iconFailures: iconFailures)
				} else {
					Color.clear.onAppear {
						path.removeAll { $0 == id }
					}
				}
			}
		}
		.frame(width: 480, height: 500)
		// Emptied when the window comes on screen and not left to the view being rebuilt, because
		// whether a closed `Window` scene is torn down or merely put away is SwiftUI's business and not
		// something written here can see. Said out loud, it holds either way — and it is the half of
		// the rule that matters most: a network that was down for a moment must not leave a grey square
		// for the rest of the session, and closing the window is how the user says "try again".
		//
		// On the stack rather than inside it, so pushing into a playlist and coming back is not an
		// opening.
		.onAppear {
			iconFailures.urls.removeAll()
		}
		.sheet(isPresented: $isAddWebsiteDialogPresented) {
			AddWebsiteScreen(
				isEditing: false,
				website: nil,
				playlist: path.last
			)
		}
		.onNotification(.showAddWebsiteDialog) { _ in
			isAddWebsiteDialogPresented = true
		}
		.toolbar {
			Button("Add Website", systemImage: "plus") {
				isAddWebsiteDialogPresented = true
			}
			.keyboardShortcut("+")
		}
		.windowMinimizeBehavior(.disabled)
		.windowLevel(.floating)
	}

	/**
	Put the copy directly under what it was copied from.

	At the end of the list it is somewhere the user has to go and find, and the gesture that produced
	it was performed on a row they were already looking at. `duplicated()` is where the copy itself is
	argued for.
	*/
	private func duplicate(_ playlist: Playlist) {
		guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else {
			return
		}

		playlists.insert(playlist.duplicated(), at: playlists.index(after: index))
	}

	private func delete(_ playlist: Playlist) {
		playlists.removeAll { $0.id == playlist.id }
	}
}

/**
One playlist in the list of them: what it is called, what it holds, and the menu that changes all of it.

The `⋮` menu rather than a context menu alone, because everything in it is reachable no other way —
there is no drawer to open, no inspector, and the row itself is a link into the playlist. A menu the
user has to guess at by right-clicking is a menu that holds the only route to renaming a thing.
*/
private struct PlaylistRow: View {
	@Binding var playlist: Playlist

	let duplicate: () -> Void
	let delete: () -> Void

	@ObservedObject private var displays = Display.observable

	@State private var isRenaming = false
	@State private var draftName = ""
	@State private var isConfirmingDuplicate = false
	@State private var isConfirmingDelete = false

	/**
	The displays this row can offer, which is the attached ones plus the one already chosen.

	The second half is the whole reason `DisplayBinding` stores a name. A binding outlives the cable:
	the monitor it names is unplugged for the evening, or the laptop is undocked, and the row still has
	to say which display this list is held back for and still has to let go of it. Built from the
	attached displays alone, the picker would have no item matching the selection, so the menu would
	draw a tick against nothing and the only way out of the binding would be to plug the display back
	in.

	`localizedName` is asked of the attached displays only, and never of the stored binding — it
	resolves through `NSScreen.screens` and answers `<Unknown name>` for a display that is not there,
	which is a string that must never reach a user. What the stored binding knows is the name that
	display had when it was chosen, and that is the honest thing to show: it is the last time the app
	could see it.
	*/
	private var displayOptions: [DisplayBinding] {
		var options = displays.wrappedValue.all.map {
			DisplayBinding(id: $0.id, nameWhenBound: $0.localizedName)
		}

		if let bound = playlist.boundDisplay, !options.contains(where: { $0.id == bound.id }) {
			options.append(bound)
		}

		return options
	}

	// The id rather than the binding itself, because a `Picker` tags its items and `DisplayBinding`
	// would have to be equal to the tag on every field for the tick to land — including a name that
	// changes when the display is renamed in System Settings.
	private var boundDisplayID: Binding<UUID?> {
		.init(
			get: { playlist.boundDisplay?.id },
			set: { chosen in
				playlist.bind(to: chosen.flatMap { id in displayOptions.first { $0.id == id } })
			}
		)
	}

	private var subtitle: String {
		let count = String(localized: "^[\(playlist.websites.count) website](inflect: true)")

		guard let bound = playlist.boundDisplay?.nameWhenBound else {
			return count
		}

		return "\(count) · \(bound)"
	}

	var body: some View {
		HStack {
			// The rows are dragged to reorder them, and nothing else on the row says so. A `List` on
			// macOS takes the drag from anywhere in the row, so this is a label for a gesture that
			// already works rather than the control that performs it — which is why it is hidden from
			// accessibility, where the same reordering is a move action on the list.
			Image(systemName: "line.3.horizontal")
				.foregroundStyle(.tertiary)
				.accessibilityHidden(true)

			NavigationLink(value: playlist.id) {
				VStack(alignment: .leading, spacing: 2) {
					Text(playlist.name)
					Text(subtitle)
						.foregroundStyle(.secondary)
						.font(.subheadline)
				}
				.lineLimit(1)
				.frame(maxWidth: .infinity, alignment: .leading)
			}

			Menu {
				// A `Picker` and not four buttons, so that "restricted to one display" reads as one
				// answer with a tick on it rather than as four independent switches that happen to be
				// exclusive. "None" is first and is the default: a playlist offered everywhere is the
				// ordinary case, and a restriction is the thing being added.
				Picker(selection: boundDisplayID) {
					Text("None")
						.tag(UUID?.none)

					ForEach(displayOptions, id: \.id) {
						Text($0.nameWhenBound)
							.tag(UUID?.some($0.id))
					}
				} label: {
					Text("Bind to Display")
				}
				// The one playlist every display falls back to, so restricting it to one display leaves
				// every other screen with an empty picker — nothing to select, nothing on the screen, and
				// no way back out from the panel. `Playlist.isDefault` argues for it at length and
				// `bind(to:)` refuses it as well; this is the half the user sees.
				.disabled(playlist.isDefault)

				Divider()

				Button("Rename…") {
					draftName = playlist.name
					isRenaming = true
				}

				Button("Duplicate…") {
					isConfirmingDuplicate = true
				}

				Divider()

				Button("Delete…", role: .destructive) {
					isConfirmingDelete = true
				}
				// For the same reason the binding is refused: it is what a display with no choice of its
				// own shows, so deleting it is deleting the fallback rather than deleting a list.
				.disabled(playlist.isDefault)
			} label: {
				Image(systemName: "ellipsis")
			}
			.menuStyle(.borderlessButton)
			.menuIndicator(.hidden)
			.fixedSize()
			.accessibilityLabel("Playlist Actions")
		}
		.frame(height: 44) // Note: Setting a fixed height prevents a lot of SwiftUI rendering bugs.
		.padding(.horizontal, 8)
		.alert(String(localized: "Rename Playlist"), isPresented: $isRenaming) {
			TextField(String(localized: "Name"), text: $draftName)

			Button(String(localized: "Rename")) {
				// A name is what the picker in the panel shows, so an empty one leaves a row the user
				// cannot tell apart from any other. Nothing is written rather than the field being
				// policed while it is typed in.
				if let name = draftName.trimmed.nilIfEmpty {
					playlist.name = name
				}
			}

			Button(String(localized: "Cancel"), role: .cancel) {}
		}
		// Duplicating destroys nothing, and it still asks — for the one consequence that is invisible
		// from here and cannot be undone afterwards. A website's stored data is filed under its id, the
		// copy's websites have new ids, so the copy is signed out of everything the original is signed
		// in to. Told once, here, rather than built around: keeping the sessions would mean two
		// playlists sharing one set of logins, and then deleting either one signs the other out.
		.confirmationDialog(
			String(localized: "Duplicate \(playlist.name)?"),
			isPresented: $isConfirmingDuplicate
		) {
			Button(String(localized: "Duplicate")) {
				duplicate()
			}

			Button(String(localized: "Cancel"), role: .cancel) {}
		} message: {
			Text("The copy gets its own websites, so a region, a stylesheet or a reload interval changed in one list leaves the other alone. It does not copy logins: every site the original is signed in to, the copy is signed out of.")
		}
		// The same bar a single website's delete has to meet, and the same reason — this app has no
		// undo and the removal is a write to the stored list, so the convention that Mac apps do not
		// confirm a delete is missing its precondition. Higher here than there, because this is that
		// dialog multiplied: everything it warns about happens to every website in the list at once,
		// and the row says how many that is right up until the moment it is asked.
		.confirmationDialog(
			String(localized: "Delete \(playlist.name)?"),
			isPresented: $isConfirmingDelete
		) {
			Button(String(localized: "Delete"), role: .destructive) {
				delete()
			}

			Button(String(localized: "Cancel"), role: .cancel) {}
		} message: {
			Text("Every website in it goes with it, along with the custom CSS, JavaScript, regions and schedules written for them; you will be signed out of each of those sites, and there is no undo.")
		}
	}
}

/**
Inside one playlist: the website list this window used to be, made to belong to something.

Nothing about a website's own row changed. What changed is what the list *is* — the members of one
playlist rather than every website in the app — so the order dragged here is the order that playlist
rotates in, and a website added while this is open is added to this list.
*/
private struct PlaylistWebsites: View {
	@Binding var playlist: Playlist

	let iconFailures: IconFetchFailures

	@State private var editedWebsite: Website.ID?
	@State private var searchText = ""

	/**
	The websites the search leaves, as bindings into the real list so editing still writes through.

	Searching turns dragging off. The order is the rotation order, and dragging a row while some of
	its neighbours are hidden would move it somewhere other than where it appears to land.
	*/
	private func matches(for query: String) -> [Binding<Website>] {
		let query = query.lowercased()

		return $playlist.websites.filter {
			query.isEmpty
				|| $0.wrappedValue.title.lowercased().contains(query)
				|| $0.wrappedValue.url.absoluteString.lowercased().contains(query)
		}
	}

	var body: some View {
		let query = searchText.trimmed

		Form {
			if !query.isEmpty {
				let matches = self.matches(for: query)

				List(matches, id: \.wrappedValue.id) { website in
					RowView(website: website, selection: $editedWebsite, iconFailures: iconFailures)
				}
				.overlay {
					if matches.isEmpty {
						Text("Nothing matches")
							.emptyStateTextStyle()
					}
				}
			} else {
			List($playlist.websites, editActions: .all) { website in
				RowView(
					website: website,
					selection: $editedWebsite,
					iconFailures: iconFailures
				)
			}
			.id(playlist.websites) // Workaround for the row not updating when changing the current active website. It's placed here and not on the row to prevent another issue where adding a new website makes it scroll outside the view. (macOS 15.3)
			.overlay {
				if playlist.websites.isEmpty {
					Text("No Websites")
						.emptyStateTextStyle()
				}
			}
			}
		}
		.searchable(text: $searchText, placement: .toolbar, prompt: Text("Search by name or address"))
		.formStyle(.grouped)
		.navigationTitle(playlist.name)
		.sheet(item: $editedWebsite) {
			AddWebsiteScreen(
				isEditing: true,
				website: $playlist.websites[id: $0]
			)
		}
	}
}

#Preview {
	WebsitesScreen()
}

/**
Says when a website's address is not where the site actually serves it from.

Only for a redirect WebKit reported, never for an address that merely differs. A page that rewrites
its own address as a map is dragged, or a dashboard that adds a tab to the query, ends up with a
different address too — and neither means the stored one is wrong. Those are the snapshot's business:
the website plus what was remembered about it is what ends up on screen.

A redirect is different because it is durable. It happens again on every launch, costs a round trip
every time, and the day the site stops redirecting the entry stops working. So it is worth mentioning
once, here, where the addresses are — and worth leaving to the user, because rewriting it unasked is
how the old menu item turned a website into a GitHub 404.
*/
private struct RedirectNotice: View {
	let website: Website

	@Default(.redirectedAddresses) private var redirects

	private var destination: URL? {
		redirects[website.id.uuidString].flatMap { URL(string: $0) }
	}

	var body: some View {
		if let destination {
			Button {
				WebsitesController.shared.update(website.id) {
					$0.url = destination
				}

				redirects[website.id.uuidString] = nil
			} label: {
				Image(systemName: "exclamationmark.triangle.fill")
					.renderingMode(.original)
					.imageScale(.large)
			}
			.buttonStyle(.plain)
			.help(String(localized: "This site sends Nifro to \(destination.absoluteString) every time it loads. Click to save that address instead."))
		}
	}
}

private struct RowView: View {
	@Binding var website: Website
	@Binding var selection: Website.ID?

	let iconFailures: IconFetchFailures

	// The tick used to be a field of the website, so the binding above redrew the row when it moved.
	// It is a per-display fact now and lives with the other per-display facts, which this row has to
	// watch for itself or it would go on drawing the tick against the website that used to hold it.
	@Default(.currentWebsites) private var currentWebsites

	@State private var isConfirmingDelete = false

	/**
	Whether this website is the one on screen where it lives.

	This list is one list for every screen and a row has no display, so the question it can ask is
	whether this website is the one on screen where it lives.
	*/
	private var isShowing: Bool {
		// Read for the redraw and not for the answer. Which display is showing what is one question
		// with one derivation of its key, and a list of rows is the last place that should get a
		// second one — the tick and the wallpaper disagreeing is the whole failure being fixed here.
		_ = currentWebsites

		return WebsitesController.shared.isShowing(website)
	}

	var body: some View {
		let isShowing = self.isShowing

		HStack {
			// The same label the playlist rows carry, for the same gesture and hidden from
			// accessibility for the same reason. It is in front of the icon rather than behind it so
			// that the two levels of this window have their handles in one column.
			Image(systemName: "line.3.horizontal")
				.foregroundStyle(.tertiary)
				.accessibilityHidden(true)

			IconView(website: website, iconFailures: iconFailures)
			VStack(alignment: .leading, spacing: 2) {
				// TODO: This should use something like `.lineBreakMode = .byCharWrapping` if SwiftUI ever supports that.
				if let title = website.title.nilIfEmpty {
					Text(title)
				}
				HStack(spacing: 6) {
					Text(website.subtitle)
						.foregroundStyle(.secondary)
					// What is set on this website, in the same order every time. A list of videos from
					// one site reads as identical rows otherwise, and these are what the rows differ by.
					ForEach(website.badges, id: \.self) {
						Image(systemName: $0)
							.foregroundStyle(.secondary)
							.imageScale(.small)
					}
				}
				.font(.subheadline)
			}
			.lineLimit(1)
			Spacer()
			RedirectNotice(website: website)
			if isShowing {
				Image(systemName: "checkmark.circle.fill")
					.renderingMode(.original)
					.font(.title2)
			}
		}
		.frame(height: 64) // Note: Setting a fixed height prevents a lot of SwiftUI rendering bugs.
		.padding(.horizontal, 8)
		.help(website.tooltip)
		.swipeActions(edge: .leading, allowsFullSwipe: true) {
			Button("Set as Current") {
				website.makeCurrent()
			}
			.disabled(isShowing)
		}
		.contentShape(.rect)
		.onDoubleClick {
			selection = website.id
		}
		.contextMenu { // Must come after `.onDoubleClick`.
			Button("Set as Current") {
				website.makeCurrent()
			}
			.disabled(isShowing)
			Divider()
			Button("Edit…") {
				selection = website.id
			}
			Divider()
			Button("Delete", role: .destructive) {
				isConfirmingDelete = true
			}
		}
		// The same consequence the Clear Data button asks about, reached from a one-click menu item
		// thirty lines away that asked about nothing. Deleting a website drops it out of the set
		// `removeOrphanedStores` keeps, so its cookies go with it on the next sweep — signing you out
		// of that site — along with the CSS, JavaScript, region and schedule you wrote for it.
		//
		// Mac apps do not normally confirm a Delete in a list, and that is the right convention: they
		// have Undo. This one does not, and the removal is a write to the stored list rather than
		// anything a Cmd-Z could reach, so the convention's precondition is missing and the dialog is
		// what stands in for it. Named in the button rather than "OK", like Clear Data.
		.confirmationDialog(
			String(localized: "Delete \(website.menuTitle)?"),
			isPresented: $isConfirmingDelete
		) {
			Button(String(localized: "Delete"), role: .destructive) {
				website.remove()
			}

			Button(String(localized: "Cancel"), role: .cancel) {}
		} message: {
			Text("Its custom CSS, JavaScript, region and schedule go with it, you will be signed out of the site, and there is no undo.")
		}
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.if(isShowing) {
			$0.accessibilityAddTraits(.isSelected)
		}
		.accessibilityAction(named: "Edit") { // Doesn't show up in accessibility actions. (macOS 14.0)
			selection = website.id
		}
		.accessibilityRepresentation {
			Button(website.menuTitle) {
				selection = website.id
			}
		}
	}
}

/**
The websites this window has looked for an icon for and not found.

`.task(id:)` belongs to the row, not to the list, so it starts again every time the row is built —
which is every time it scrolls out of view and back. What it starts is not cheap: metadata for the
page, and then, for a site that has none, a whole page load in a web view. A lookup that came back
empty came back empty for reasons that do not change while the user is sitting there looking at the
list, so paying for it again on the way back up the list buys nothing.

Not the thumbnail cache, which is the successful half of the same question and is right to be on
disk. A miss is worth remembering for exactly as long as one sitting: it can be a site with no icon
to find, and it can equally be a minute of no network. Remembering it for the life of the app, or
across launches, would turn the second into the first.

A class and not another piece of `@State`, because a row writes into this while it is being drawn and
that write must not redraw the window around it. Nothing observes it — the next lookup reads it, and
that is all.
*/
@MainActor
private final class IconFetchFailures {
	var urls = Set<URL>()
}

private struct IconView: View {
	@State private var icon: Image?

	let website: Website
	let iconFailures: IconFetchFailures

	var body: some View {
		VStack {
			if let icon {
				// Filled rather than fitted: these are video covers as often as they are site icons now,
				// and a 16:9 cover fitted into a square is mostly empty space.
				icon
					.resizable()
					.scaledToFill()
			} else {
				Color.primary.opacity(0.1)
			}
		}
		.frame(width: 44, height: 44)
		// A masked favicon in a stock `Form`, not a panel control, so `controlRadius` would be
		// the wrong source: this wants whatever radius macOS masks app icons with, and 5 on 44 points
		// is the closest hand-written approximation of it. It follows the system if the system ever
		// exposes the number, not the panel.
		// swiftlint:disable:next hardcoded_corner_radius
		.clipShape(.rect(cornerRadius: 5))
		.task(id: website.url) {
			guard let image = await fetchIcons() else {
				return
			}

			icon = Image(nsImage: image)
		}
	}

	private func fetchIcons() async -> NSImage? {
		let cache = WebsitesController.shared.thumbnailCache

		if let image = cache[website.thumbnailCacheKey] {
			return image
		}

		// Once per opening of this window, for the reason `IconFetchFailures` gives.
		guard !iconFailures.urls.contains(website.url) else {
			return nil
		}

		// A video's own cover first. The general fetcher would fall back to the site's icon here, and
		// a list of videos all wearing the same logo is the case a picture was supposed to help with.
		if
			let previewURL = VideoEmbed.previewImageURL(for: website.url),
			let (data, _) = try? await URLSession.shared.data(from: previewURL),
			let image = NSImage(data: data)
		{
			cache[website.thumbnailCacheKey] = image
			return image
		}

		guard let image = try? await WebsiteIconFetcher.fetch(for: website.url) else {
			// A cancelled lookup found nothing because it was stopped, not because there is nothing to
			// find, and scrolling a row away is what stops it. Recorded, it would mean that hurrying down
			// a long list left a grey square behind every row that went past mid-fetch, which is the
			// failure this record exists to avoid rather than one to cause.
			if !Task.isCancelled {
				iconFailures.urls.insert(website.url)
			}

			return nil
		}

		cache[website.thumbnailCacheKey] = image

		return image
	}
}
