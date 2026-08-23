import SwiftUI

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
