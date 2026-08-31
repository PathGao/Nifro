import Defaults
import SwiftUI

/**
Browse the built-in catalogue and add a site with the settings that make it work.
*/
struct SiteGalleryScreen: View {
	@State private var search = ""
	@State private var selectedTag: String?
	@Default(.playlists) private var playlists
	@State private var entries = SiteCatalog.entries
	@State private var isLiveList = false
	@State private var isLoading = true

	/**
	The addresses already in the list, which is the whole of what "Added" means.

	Asked of the stored websites rather than remembered in a `@State` set. That set was made empty
	every time the window opened, so a site installed on an earlier visit came back offering "Add" —
	and the second press installed a second copy, because `WebsitesController.add` appends and
	nothing under it looks for a website that is already there.

	By address, because that is the only thing an entry and a website have in common. An entry becomes
	a website with a fresh `UUID` and no trace of where it came from, which is deliberate and argued
	for where the shipped ones are installed: a built-in you cannot tell apart from your own is the
	point. So this cannot ask "did this entry make that website", only "is that address in the list".

	Which is also why an address the user has since edited reads as not installed, and the row offers
	to add the original again. That is the honest answer: the website in the list is no longer the
	page the entry describes, and the entry's settings are no longer on it.
	*/
	private var installedAddresses: Set<URL> {
		Set(playlists.flatMap(\.websites).map(\.url))
	}

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
		let matches = self.matches
		let installed = installedAddresses

		VStack(spacing: 0) {
			header
			Divider()

			// The height is stated on the branch rather than left to it. A `List` is greedy and the
			// empty state is not, so without this the whole stack shrinks to the height of two lines
			// of text and gets centred in the fixed frame — the header drops away from the top and the
			// footer jumps up from the bottom, on the keystroke that stops the query matching.
			Group {
				if matches.isEmpty {
					ContentUnavailableView.search(text: search)
				} else {
					List(matches) { entry in
						// Parsed the same way `add` parses it, so the two cannot disagree about what the
						// entry's address is — and an entry that will not parse is one `add` refuses, so
						// "not installed" is right for it too.
						row(for: entry, isInstalled: URL(string: entry.url).map(installed.contains) ?? false)
					}
					.listStyle(.inset)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

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
	Two ways out: more pages than are in the list yet, and the way to add one.

	Neither points at the directory the entries are authored in. That is thirty-eight YAML files of
	settings — the format for writing an entry, not for reading a list.
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

			Link("Browse more wallpaper ideas", destination: Constants.candidateSitesURL)
			Link("Suggest a site…", destination: Constants.siteSubmissionURL)
		}
		.padding(.horizontal)
		.padding(.vertical, 10)
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Find pages that work well as wallpapers. Adding one also applies its recommended settings.")
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

	private func row(for entry: SiteCatalog.Entry, isInstalled: Bool) -> some View {
		HStack(alignment: .top, spacing: 12) {
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(entry.name)
						.fontWeight(.medium)


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

			Button(isInstalled ? "Added" : "Add") {
				entry.add()
			}
			.disabled(isInstalled)
		}
		.padding(.vertical, 4)
	}

	// `LocalizedStringResource` rather than `String`: a `String` parameter swallows the two literals at
	// the call site whole — `Text` and `.help` then draw them verbatim, nothing extracts them, and no
	// check in the repository can see them. Typed, the same two literals are keys.
	private func badge(_ text: LocalizedStringResource, help: LocalizedStringResource) -> some View {
		Text(text)
			.font(.caption2)
			.padding(.horizontal, 5)
			.padding(.vertical, 1)
			.background(.quaternary, in: Capsule())
			.help(Text(help))
	}
}
