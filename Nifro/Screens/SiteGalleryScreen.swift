import SwiftUI

/**
Browse the built-in catalogue and add a site with the settings that make it work.
*/
struct SiteGalleryScreen: View {
	@State private var search = ""
	@State private var selectedTag: String?
	@State private var added = Set<String>()
	@State private var entries = SiteCatalog.entries
	@State private var isLiveList = false
	@State private var isLoading = true

	private var matches: [SiteCatalog.Entry] {
		entries.filter { entry in
			let matchesTag = selectedTag.map(entry.tags.contains) ?? true

			guard let query = search.trimmed.nilIfEmpty?.lowercased() else {
				return matchesTag
			}

			return matchesTag && (
				entry.name.lowercased().contains(query)
					|| entry.description.lowercased().contains(query)
					|| entry.tags.contains { $0.contains(query) }
			)
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()

			if matches.isEmpty {
				ContentUnavailableView.search(text: search)
			} else {
				List(matches) { entry in
					row(for: entry)
				}
				.listStyle(.inset)
			}

			Divider()
			footer
		}
		.frame(width: 560, height: 560)
		.task {
			let result = await SiteCatalog.fetchLatest()
			entries = result.entries
			isLiveList = result.isLive
			isLoading = false
		}
	}

	/**
	The catalogue lives in the repository and that is where submissions arrive, so both routes are one click away rather than buried.
	*/
	private var footer: some View {
		HStack(spacing: 12) {
			Group {
				if isLoading {
					Text("Checking for new entries…")
				} else if isLiveList {
					Text("^[\(entries.count) site](inflect: true) · up to date with GitHub")
				} else {
					Text("^[\(entries.count) site](inflect: true) · bundled copy, could not reach GitHub")
				}
			}
			.font(.caption)
			.foregroundStyle(.secondary)

			Spacer()

			Link("Browse on GitHub", destination: Constants.siteGalleryURL)
			Link("Submit a Site…", destination: Constants.siteSubmissionURL)
		}
		.padding(.horizontal)
		.padding(.vertical, 10)
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Pages that work well as wallpapers. Adding one brings its recommended settings with it.")
				.font(.callout)
				.foregroundStyle(.secondary)

			HStack {
				TextField("Search", text: $search)
					.textFieldStyle(.roundedBorder)

				Picker("", selection: $selectedTag) {
					Text("All").tag(nil as String?)
					ForEach(SiteCatalog.allTags(in: entries), id: \.self) { tag in
						Text(tag.capitalized).tag(tag as String?)
					}
				}
				.labelsHidden()
				.frame(width: 140)
			}
		}
		.padding()
	}

	private func row(for entry: SiteCatalog.Entry) -> some View {
		HStack(alignment: .top, spacing: 12) {
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(entry.name)
						.fontWeight(.medium)

					if entry.isLive {
						badge("live", help: "Keeps rendering continuously. Costs more than a page that is only re-drawn every so often.")
					}

					if entry.requiresLogin {
						badge("sign-in", help: "You will need to log in through Browsing Mode once.")
					}
				}

				Text(entry.description)
					.font(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				Text(entry.tags.joined(separator: " · "))
					.font(.caption)
					.foregroundStyle(.tertiary)
			}

			Spacer(minLength: 8)

			Button(added.contains(entry.id) ? "Added" : "Add") {
				entry.add()
				added.insert(entry.id)
			}
			.disabled(added.contains(entry.id))
		}
		.padding(.vertical, 4)
	}

	private func badge(_ text: String, help: String) -> some View {
		Text(text)
			.font(.caption2)
			.padding(.horizontal, 5)
			.padding(.vertical, 1)
			.background(.quaternary, in: Capsule())
			.help(help)
	}
}
