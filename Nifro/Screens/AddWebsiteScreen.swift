import SwiftUI
import LinkPresentation

/**
Adding a website, and editing one that is already in the list.

**Opening this does not change what is on screen.** It used to: editing ran `makeCurrent()` on
appear, so double-clicking a row in the Websites window to read its settings switched that display's
wallpaper. Neither way out put it back. Escape with nothing edited just dismissed, leaving the new
wallpaper up. Revert and "Don't Keep" went through `revert()`, which restores this website's own
fields — including a `false` mark — but cannot restore the sibling's, since `makeCurrent` had cleared
that as part of marking this one. The display then had no marked website at all, and
`WebsitesController`'s repair marked whichever one sorts first on it. So the verb was "edit" and the
effect was either "switch" or "switch to a third thing", depending on which button you pressed.

That was there for a real reason: custom CSS reaches the wallpaper on the next load, so editing it
against a page you cannot see is guesswork. But making a website current is a deliberate, persisted
change to somebody's desktop, and the list already offers it deliberately — "Set as Current" is in
each row's context menu and its leading swipe. Doing it there costs one click, is reversible by the
same control, and does not depend on which button dismissed a sheet. A preview that has to be undone
correctly on four exit paths is a worse version of a control that already exists one gesture away.

Choosing a region is unaffected either way: that is done over the wallpaper from the panel, never
from in here — see `ZoomSetting`.
*/
struct AddWebsiteScreen: View {
	@Environment(\.dismiss) private var dismiss
	@State private var hostingWindow: NSWindow?
	@State private var isFetchingTitle = false
	@State private var isApplyConfirmationPresented = false
	@State private var isCustomCodePresented = false
	@State private var originalWebsite: Website?
	@State private var urlString = ""

	@State private var newWebsite = Website(
		id: UUID(),
		isCurrent: true,
		url: ".",
		usePrintStyles: false,
		css: Website.starterCSS,
		javaScript: Website.starterJavaScript
	)

	private var isURLValid: Bool {
		URL.isValid(string: urlString)
			&& website.wrappedValue.url.isValid
	}

	private var hasChanges: Bool { website.wrappedValue != originalWebsite }

	private let isEditing: Bool

	// TODO: `@OptionalBinding` extension?
	private var existingWebsite: Binding<Website>?

	private var website: Binding<Website> { existingWebsite ?? $newWebsite }

	init(
		isEditing: Bool,
		website: Binding<Website>?
	) {
		self.isEditing = isEditing
		self.existingWebsite = website
		self._originalWebsite = .init(wrappedValue: website?.wrappedValue)

		if isEditing {
			self._urlString = .init(wrappedValue: website?.wrappedValue.url.absoluteString ?? "")
		}
	}

	var body: some View {
		Form {
			topView
			if SSApp.isFirstLaunch, !isEditing {
				firstLaunchView
			}
			if isEditing {
				editingView
			}
		}
		.formStyle(.grouped)
		.frame(width: 500)
		.fixedSize()
		.bindHostingWindow($hostingWindow)
		// Note: Current only works when a text field is focused. (macOS 11.3)
		.onExitCommand {
			guard
				isEditing,
				hasChanges
			else {
				dismiss()
				return
			}

			isApplyConfirmationPresented = true
		}
		.onSubmit {
			submit()
		}
		.sheet(isPresented: $isCustomCodePresented) {
			CustomCodeScreen(css: website.css, javaScript: website.javaScript)
		}
		.confirmationDialog2(
			String(localized: "Keep changes?"),
			isPresented: $isApplyConfirmationPresented
		) {
			Button("Keep") {
				dismiss()
			}
			Button("Don't Keep", role: .destructive) {
				revert()
				dismiss()
			}
			Button("Cancel", role: .cancel) {}
		}
		.toolbar {
			if isEditing {
				ToolbarItem {
					Button("Revert") {
						revert()
					}
					.disabled(!hasChanges)
				}
			} else {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						dismiss()
					}
				}
			}
			ToolbarItem(placement: .confirmationAction) {
				Button(isEditing ? "Done" : "Add") {
					submit()
				}
				.disabled(!isURLValid)
			}
		}
	}

	private var firstLaunchView: some View {
		Section {
			HStack {
				HStack(spacing: 3) {
					Text("You could, for example,")
					Button("show the time.") {
						urlString = "https://time.pablopunk.com/?seconds&fg=white&bg=transparent"
					}
					.buttonStyle(.link)
				}
				Spacer()
				Link("More ideas", destination: Constants.candidateSitesURL)
					.buttonStyle(.link)
			}
		}
	}

	private var topView: some View {
		Section {
			TextField("URL", text: $urlString)
				.textContentType(.URL)
				.lineLimit(1)
				// This change listener is used to respond to URL changes from the outside, like the "Revert" button or the Shortcuts actions.
				.onChange(of: website.wrappedValue.url) { _, url in
					guard
						url.absoluteString != "-",
						url.absoluteString != urlString
					else {
						return
					}

					urlString = url.absoluteString
				}
				.onChange(of: urlString) {
					guard let url = URL(humanString: urlString) else {
						// Makes the “Revert” button work if the user clears the URL field.
						if urlString.trimmed.isEmpty {
							website.wrappedValue.url = "-"
						} else if
							let url = URL(string: urlString, encodingInvalidCharacters: false),
							url.isValid
						{
							website.wrappedValue.url = url
						}

						return
					}

					guard url.isValid else {
						return
					}

					website.wrappedValue.url = url
						.normalized(
							removeDefaultPort: false, // We need to allow typing `http://172.16.0.100:8080`.
							removeWWW: false // Some low-quality sites don't work without this.
						)
				}
				.debouncingTask(id: website.wrappedValue.url, interval: .seconds(0.5)) {
					await fetchTitle()
				}

			// Offered rather than applied. Rewriting what somebody just typed is rude, and the point
			// of showing the rewritten URL in the field is that they can see it and undo it.
			if let player = VideoEmbed.playerURL(for: website.wrappedValue.url) {
				Button("Use the player-only page") {
					urlString = player.absoluteString
					website.wrappedValue.url = player
				}
				.help("The address of the player on its own, so the video fills the wallpaper without the navigation, recommendations and comments around it.")
			}

			TextField("Title", text: website.title)
				.lineLimit(1)
				.disabled(isFetchingTitle)
				.overlay(alignment: .leading) {
					if isFetchingTitle {
						ProgressView()
							.controlSize(.small)
							.offset(x: 50)
					}
				}
		} footer: {
			Button("Local Website…") {
				Task {
					guard let url = await chooseLocalWebsite() else {
						return
					}

					urlString = url.absoluteString
				}
			}
			.controlSize(.small)
		}
	}

	@ViewBuilder
	private var editingView: some View {
		Section {
			Picker(selection: website.invertColors2) {
				ForEach(Website.InvertColors.allCases, id: \.self) {
					Text($0.title).tag($0)
				}
			} label: {
				Text("Invert colors")
					.explained(String(localized: "Inverts every colour on the website, as a fake dark mode for sites that have none."))
			}
			Toggle(isOn: website.usePrintStyles) {
				Text("Use print styles")
					.explained(String(localized: "Forces the website's print styles (“@media print”) if it has any, which are often simpler."))
			}
			// Its own panel rather than a fold. Both are empty for almost every website, so they should
			// not be sitting open; and folding them open resizes the dialog, which reads as the window
			// flinching rather than as something opening.
			LabeledContent {
				Button(String(localized: "CSS and JavaScript…")) {
					isCustomCodePresented = true
				}
			} label: {
				Text("Custom code")
					.explained(String(localized: "Inject your own CSS or JavaScript into this website. Most websites need neither."))
			}
		}
		Section {
			WebsiteAudioSetting(audio: website.audio)
			WebsiteInteractionSetting(allowsInteraction: website.allowsInteraction)
			WebsiteDisplaySetting(display: website.display)
			WebsiteScheduleSetting(startHour: website.startHour, endHour: website.endHour)
			WebsiteReloadSetting(reloadInterval: website.reloadInterval)
			ZoomSetting(zoom: website.zoom)
		}
		Section("Advanced") {
			Toggle(isOn: website.allowSelfSignedCertificate) {
				Text("Allow self-signed certificate")
					.explained(String(localized: "Loads the page even though macOS does not trust its certificate — normal for a device on your own network, unsafe for anything from the public internet."))
			}

			// Last, because it copies everything above it. A button that gathers the settings should
			// come after the settings, not before them.
			LabeledContent {
				Button(String(localized: "Copy Settings")) {
					NSPasteboard.general.prepareForNewContents()
					NSPasteboard.general.setString(website.wrappedValue.reportText, forType: .string)
				}
			} label: {
				Text("Report a problem")
					.explained(String(localized: "Copies this website's settings as text for pasting into an issue, reporting the CSS and JavaScript by size rather than by content."))
			}
		}
	}

	private func submit() {
		guard isURLValid else {
			return
		}

		if isEditing {
			dismiss()
		} else {
			add()
		}
	}

	private func revert() {
		guard let originalWebsite else {
			return
		}

		website.wrappedValue = originalWebsite
	}

	private func add() {
		WebsitesController.shared.add(website.wrappedValue)
		dismiss()

		SSApp.runOnce(identifier: "editWebsiteTip") {
			// TODO: Find a better way to inform the user about this.
			Task {
				await NSAlert.show(
					title: "Double-click a website in the list to edit it, toggle dark mode, add custom CSS/JavaScript, and more."
				)
			}
		}
	}

	private func chooseLocalWebsite() async -> URL? {
//		guard let hostingWindow else {
//			return nil
//		}

		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.canCreateDirectories = false
		panel.title = String(localized: "Choose Local Website")
		panel.message = String(localized: "Choose a directory with a “index.html” file.")
		panel.prompt = String(localized: "Choose")

		// Ensure it's above the window when in "Browsing Mode".
		panel.level = .modalPanel

		let url = website.wrappedValue.url

		if
			isEditing,
			url.isFileURL
		{
			panel.directoryURL = url
		}

		// TODO: Make it a sheet instead when targeting the macOS bug is fixed. (macOS 15.3)
//		let result = await panel.beginSheet(hostingWindow)
		let result = await panel.begin()

		guard
			result == .OK,
			let url = panel.url
		else {
			return nil
		}

		guard url.appendingPathComponent("index.html", isDirectory: false).exists else {
			await NSAlert.show(title: String(localized: "Please choose a directory that contains a “index.html” file."))
			return await chooseLocalWebsite()
		}

		do {
			try SecurityScopedBookmarkManager.saveBookmark(for: url)
		} catch {
			await error.present()
			return nil
		}

		return url
	}

	private func fetchTitle() async {
		// Ensure we don't erase a user's existing title.
		if
			isEditing,
			!website.title.wrappedValue.isEmpty
		{
			return
		}

		let url = website.wrappedValue.url

		guard url.isValid else {
			website.wrappedValue.title = ""
			return
		}

		withAnimation {
			isFetchingTitle = true
		}

		defer {
			withAnimation {
				isFetchingTitle = false
			}
		}

		let metadataProvider = LPMetadataProvider()
		metadataProvider.shouldFetchSubresources = false
		metadataProvider.timeout = 5

		guard
			let metadata = try? await metadataProvider.startFetchingMetadata(for: url),
			let title = metadata.title
		else {
			if !isEditing || website.wrappedValue.title.isEmpty {
				website.wrappedValue.title = ""
			}

			return
		}

		website.wrappedValue.title = title
	}
}

#Preview {
	AddWebsiteScreen(
		isEditing: false,
		website: nil
	)
}


/**
Where a website's own CSS and JavaScript are written.

A panel rather than part of the dialog. Almost no website has either, and giving them room in the
form pushed everything that is actually set on a typical website below the fold; giving them a fold
made the dialog resize itself every time it was opened or closed.
*/
private struct CustomCodeScreen: View {
	@Environment(\.dismiss) private var dismiss

	@Binding var css: String
	@Binding var javaScript: String

	private static let notes = String(localized: "The page is laid out at the size of the wallpaper, so `100vw` and `100vh` mean that area, and `<html>` carries `is-nifro-app` always and `nifro-is-browsing-mode` while Browsing Mode is on.")

	var body: some View {
		VStack(alignment: .leading) {
			Text(Self.notes)
				.font(.callout)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			Divider()
				let cssHelpText = "This lets you modify the website with CSS. You could, for example, change some colors or hide some unnecessary elements."
				VStack(alignment: .leading) {
					HStack {
						Text("CSS")
						Spacer()
						InfoPopoverButton(cssHelpText)
							.controlSize(.small)
					}
					ScrollableTextView(
						text: $css,
						// A code editor's font, not the app's. It answers to what fits eighty columns
						// of CSS, and pointing it at the panel's type would couple an editor to a
						// popover that has nothing to do with it.
						// swiftlint:disable:next hardcoded_font_size
						font: .monospacedSystemFont(ofSize: 11, weight: .regular),
						isAutomaticQuoteSubstitutionEnabled: false,
						isAutomaticDashSubstitutionEnabled: false,
						isAutomaticTextReplacementEnabled: false,
						isAutomaticSpellingCorrectionEnabled: false
					)
					.frame(height: 70)
				}
				.accessibilityElement(children: .combine)
				.accessibilityLabel("CSS")
				.accessibilityHint(Text(cssHelpText))
				let javaScriptHelpText = "This lets you modify the website with JavaScript. Prefer using CSS instead whenever possible. You can use “await” at the top-level."
				VStack(alignment: .leading) {
					HStack {
						Text("JavaScript")
						Spacer()
						InfoPopoverButton(javaScriptHelpText)
							.controlSize(.small)
					}
					ScrollableTextView(
						text: $javaScript,
						// The CSS editor's font, for the same reason, and matching it deliberately:
						// the two boxes sit one above the other and hold the same kind of text.
						// swiftlint:disable:next hardcoded_font_size
						font: .monospacedSystemFont(ofSize: 11, weight: .regular),
						isAutomaticQuoteSubstitutionEnabled: false,
						isAutomaticDashSubstitutionEnabled: false,
						isAutomaticTextReplacementEnabled: false,
						isAutomaticSpellingCorrectionEnabled: false
					)
					.frame(height: 70)
				}
				.accessibilityElement(children: .combine)
				.accessibilityLabel("JavaScript")
				.accessibilityHint(Text(javaScriptHelpText))
		}
		.padding()
		.frame(width: 520, height: 560)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button(String(localized: "Done")) {
					dismiss()
				}
			}
		}
	}
}
