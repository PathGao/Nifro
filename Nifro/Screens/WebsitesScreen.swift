import SwiftUI
import WebKit

struct WebsitesScreen: View {
	@Default(.websites) private var websites
//	@State private var selection: Website.ID? // We need two states as selection must be independent from actually opening the editing because of keyboard navigation and accessibility.
	@State private var editedWebsite: Website.ID?
	@State private var isAddWebsiteDialogPresented = false
	@State private var searchText = ""

	/**
	The websites the search leaves, as bindings into the real list so editing still writes through.

	Searching turns dragging off. The order is the rotation order, and dragging a row while some of
	its neighbours are hidden would move it somewhere other than where it appears to land.
	*/
	private var matches: [Binding<Website>] {
		let query = searchText.trimmed.lowercased()

		return $websites.filter {
			query.isEmpty
				|| $0.wrappedValue.title.lowercased().contains(query)
				|| $0.wrappedValue.url.absoluteString.lowercased().contains(query)
		}
	}

	var body: some View {
		Form {
			if !searchText.trimmed.isEmpty {
				List(matches, id: \.wrappedValue.id) { website in
					RowView(website: website, selection: $editedWebsite)
				}
				.overlay {
					if matches.isEmpty {
						Text("Nothing matches")
							.emptyStateTextStyle()
					}
				}
			} else {
			List($websites, editActions: .all) { website in
				RowView(
					website: website,
					selection: $editedWebsite
				)
			}
			.id(websites) // Workaround for the row not updating when changing the current active website. It's placed here and not on the row to prevent another issue where adding a new website makes it scroll outside the view. (macOS 15.3)
//			.onKeyboardShortcut(.defaultAction) {
//				editedWebsite = selection
//			}
			.onChange(of: websites) { oldWebsites, websites in
				// Check that a website was added.
				guard websites.count > oldWebsites.count else {
					return
				}

				withAnimation {
				}
			}
			.overlay {
				if websites.isEmpty {
					Text("No Websites")
						.emptyStateTextStyle()
				}
			}
			.accessibilityAction(named: "Add website") {
				isAddWebsiteDialogPresented = true
			}
			}
		}
		.searchable(text: $searchText, placement: .toolbar, prompt: Text("Search by name or address"))
		.formStyle(.grouped)
		.safeAreaInset(edge: .bottom) {
			VStack(spacing: 0) {
				Divider()

				ClearWebsiteDataButton()
					// Roomier than the site gallery's footer on purpose. One control alone in a bar looks
					// wedged in if it is given the padding a row of them would share, and being cramped is
					// what was wrong with where this used to live.
					.padding(.horizontal, 20)
					.padding(.vertical, 14)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.frame(width: 480, height: 500)
//		.onChange(of: editedWebsite) {
//			selection = $0
//		}
		.sheet(item: $editedWebsite) {
			AddWebsiteScreen(
				isEditing: true,
				website: $websites[id: $0]
			)
		}
		.sheet(isPresented: $isAddWebsiteDialogPresented) {
			AddWebsiteScreen(
				isEditing: false,
				website: nil
			)
		}
		.onNotification(.showAddWebsiteDialog) { _ in
			isAddWebsiteDialogPresented = true
		}
		.onNotification(.showEditWebsiteDialog) { _ in
			editedWebsite = AppState.shared.currentWebsite?.id
		}
		.toolbar {
			Button("Add Website", systemImage: "plus") {
				isAddWebsiteDialogPresented = true
			}
			.keyboardShortcut("+")
		}
		.onAppear {
		}
		.windowMinimizeBehavior(.disabled)
		.windowLevel(.floating)
	}
}

#Preview {
	WebsitesScreen()
}

/**
Throwing away what every website has stored, at the foot of the window those websites are managed in.

It moved here from the Advanced settings tab, which is where a switch belongs and this is not one: it
is an action, it acts on the list this window shows, and it was the only thing in that tab that did
anything the moment it was touched.

Bottom left, while "Add Website" is in the toolbar at the top right — the two farthest points in the
window. They are a constructive verb and its destructive opposite, and a slip between neighbouring
controls is the only mistake this pair can make.

A stock `Button`, like the ones in About and in the site gallery's footer, and not `PanelWideButton`.
The panel's controls are hand-made because they float over the desktop with nothing around them to
explain what they are; this is an ordinary window with a toolbar and a grouped form, so it takes the
ordinary controls those windows use.

Clearing takes a moment and used to say nothing about it. The button disabled itself the instant it was
pressed and stayed that way, with no sign of work happening, no sign of it finishing, and no way to tell
whether anything had gone. It is a button whose whole purpose is an effect you cannot see, so it has to
report one: it says how much it freed, which is the only answer to "did that do anything" that does not
require taking the app's word for it.
*/
private struct ClearWebsiteDataButton: View {
	private enum Progress: Equatable {
		case ready
		case clearing
		case cleared(bytes: Int64)
	}

	@State private var progress = Progress.ready

	var body: some View {
		HStack(spacing: 8) {
			// Not `role: .destructive`. Red would make it the one coloured control in a window of plain
			// ones, and what keeps a slip from reaching it is the distance from "Add Website", not the
			// colour. Full size too: it was small because it used to sit in a section footer, among
			// footnote text, and there is no footnote text here.
			Button("Clear all website data") {
				clear()
			}
			.disabled(progress == .clearing)

			switch progress {
			case .ready:
				EmptyView()
			case .clearing:
				ProgressView()
					.controlSize(.small)
			case .cleared(let bytes):
				// Zero is a real answer and a common one — pressing it twice frees nothing the second
				// time — so it says "nothing left to clear" rather than "0 bytes freed", which reads
				// like a failure.
				Text(bytes > 0 ? String(localized: "Freed \(bytes.formatted(.byteCount(style: .file)))") : String(localized: "Nothing left to clear"))
					.foregroundStyle(.secondary)
			}
		}
		.help("Clears cookies, local storage, caches, page thumbnails, and what each page had remembered: where it was scrolled or moved to, and how far it was zoomed in. Your websites and their settings are kept.")
	}

	private func clear() {
		progress = .clearing

		Task {
			let before = await DiskBudget.storedBytes(of: [.homeDirectory])

			WebsitesController.shared.thumbnailCache.removeAllImages()
			AppState.shared.forgetWherePagesWere()
			await WKWebsiteDataStore.clearAllWebsiteData()

			let after = await DiskBudget.storedBytes(of: [.homeDirectory])
			progress = .cleared(bytes: max(0, before - after))
		}
	}
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
			.help(String(localized: "This site sends Nifro somewhere else every time it loads: \(destination.absoluteString). Click to save that address instead."))
		}
	}
}

private struct RowView: View {
	@Binding var website: Website
	@Binding var selection: Website.ID?

	var body: some View {
		HStack {
			IconView(website: website)
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
			if website.isCurrent {
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
			.disabled(website.isCurrent)
		}
		.contentShape(.rect)
		.onDoubleClick {
			selection = website.id
		}
		.contextMenu { // Must come after `.onDoubleClick`.
			Button("Set as Current") {
				website.makeCurrent()
			}
			.disabled(website.isCurrent)
			Divider()
			Button("Edit…") {
				selection = website.id
			}
			Divider()
			Button("Delete", role: .destructive) {
				website.remove()
			}
		}
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.if(website.isCurrent) {
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

private struct IconView: View {
	@State private var icon: Image?

	let website: Website

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
			return nil
		}

		cache[website.thumbnailCacheKey] = image

		return image
	}
}
