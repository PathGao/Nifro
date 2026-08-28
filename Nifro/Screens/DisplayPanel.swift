import SwiftUI

/**
One column per display, side by side.

The menu this begins to replace could only ever describe one display. Every item in it acted on "the
current website", and with two screens that meant whichever one last held a flag — so the menu was
both telling the user about one display and hiding that fact. Showing every display at once removes
the question rather than answering it.

The picture is the wallpaper itself, taken from the app's own web view. No screen recording is asked
for, and none is needed.
*/
struct DisplayPanel: View {
	@ObservedObject private var model: DisplayPanelModel

	init(model: DisplayPanelModel) {
		self.model = model
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack(alignment: .top, spacing: 16) {
				ForEach(model.columns) { column in
					DisplayColumn(column: column, model: model)
				}
			}
			.padding(16)

			Divider()

			PanelFooter(model: model)
				.padding(.horizontal, 16)
				.padding(.vertical, 10)
		}
		// A popover wears the system's vibrancy, which is tuned for a window over other windows. What is
		// behind this one is the wallpaper, and a wallpaper is whatever the user pointed it at — a busy
		// page reads straight through the panel's own labels.
		//
		// `regularMaterial` rather than a wash the app mixes itself out of `windowBackgroundColor` at
		// thirty-five percent: it is the material the system uses for exactly this — a panel over
		// content it does not control — so it follows the appearance, thins under Reduce Transparency,
		// and is the surface Control Center and Notification Center already sit on.
		.background(.regularMaterial)
		// A popover is the window the user is looking at, whatever AppKit thinks. There is one occasion
		// it is not the key window: Browsing Mode hands the wallpaper's own window the keyboard, and it
		// does that from a button inside this panel — so pressing that button turned every stock control
		// here grey, the accent included, while the panel stayed open in front of the user. The drawn
		// buttons this replaced never noticed, because a hardcoded orange does not.
		.environment(\.controlActiveState, .key)
		.task {
			// The controller puts the columns up before the panel is shown and starts the refreshes
			// straight after, so this changes nothing in the app. It is here for a preview, where there
			// is no controller at all and nothing else would ever ask.
			await model.refresh()
		}
	}
}

/**
Everything that is not about one display.

Icons, because the app's own verbs are not a display's, and a row of words here would compete with the
columns above for the eye. Quit keeps its label: it is the one that cannot be undone, and an
unlabelled power symbol beside four others is exactly the button somebody presses by mistake.

The download icon is the one that comes and goes, and it is where the daily update check finally says
what it found. The check has written `latestKnownVersion` down since #18 and the surface that read it
was in the menu #21 deleted, so for six releases the app asked GitHub once a day and told nobody. It
is read from the store rather than fetched here, so opening the panel costs no network, and it is
compared against the running version on every draw rather than stored as a flag — a flag would go on
saying an update exists after the update was installed.
*/
private struct PanelFooter: View {
	@ObservedObject private var model: DisplayPanelModel

	@Default(.latestKnownVersion) private var latestKnownVersion

	init(model: DisplayPanelModel) {
		self.model = model
	}

	/**
	The version to offer, or `nil` when there is nothing newer than this one.
	*/
	private var newerVersion: String? {
		guard
			let latestKnownVersion,
			UpdateCheck.isNewer(latestKnownVersion, than: SSApp.version)
		else {
			return nil
		}

		return latestKnownVersion
	}

	var body: some View {
		HStack(spacing: PanelMetrics.controlSpacing) {
			PanelButton(symbol: "plus", label: String(localized: "Add Website…")) {
				model.run { Constants.openWebsitesWindow(); NotificationCenter.default.post(name: .showAddWebsiteDialog, object: nil) }
			}

			PanelButton(symbol: "list.bullet", label: String(localized: "Manage Websites…")) {
				model.run { Constants.openWebsitesWindow() }
			}

			PanelButton(symbol: "square.grid.2x2", label: String(localized: "Site Gallery…")) {
				model.run { Constants.openSiteGalleryWindow() }
			}

			PanelButton(symbol: "gearshape", label: String(localized: "Settings…")) {
				model.run { SSApp.showSettingsWindow() }
			}

			// This side of the spacer rather than beside Quit. It appears without warning, and a button
			// that turns up under the pointer next to the one that ends the app is the reach the
			// workspace rule about neighbours is written for.
			if let newerVersion {
				PanelButton(symbol: "arrow.down.circle", label: String(localized: "Get \(newerVersion)…")) {
					model.run { Constants.latestReleaseURL.open() }
				}
			}

			Spacer()

			PanelWideButton(title: String(localized: "Quit Nifro"), symbol: "power") {
				SSApp.quit()
			}
			.fixedSize()
		}
	}
}


/**
Everything one display gets to say for itself.

Handed a finished column rather than the model, so the only thing that knows how a column is
assembled is the thing that assembles it.
*/
private struct DisplayColumn: View {
	let column: DisplayPanelModel.Column
	@ObservedObject private var model: DisplayPanelModel

	@State private var isHovering = false

	// The stored set, so the view observes it: a shortcut pressed while the panel is open lights the
	// button too. Read per display, because Browsing Mode is now one display's business — it used to
	// light in every column at once, which is what it looked like when it was one flag for the app.
	@Default(.browsingDisplays) private var browsingDisplays

	init(column: DisplayPanelModel.Column, model: DisplayPanelModel) {
		self.column = column
		self.model = model
	}

	var body: some View {
		VStack(spacing: 9) {
			displayName

			failureLine

			VStack(spacing: 9) {
				VStack(spacing: 9) {
					MarqueeText(text: column.websiteName ?? String(localized: "No Website"), isActive: isHovering)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.frame(width: PanelMetrics.columnWidth, height: 16)

					preview

					rotationControls
				}
				.opacity(inertOpacity)

				// Above the website chooser, not instead of it: the two say what to show at different
				// grains, and a display picks a list before it picks a page out of it. Inside the
				// dimming, unlike the chooser below, because it is not the control reporting the load.
				playlistChooser
					.opacity(inertOpacity)

				// Outside the dimming, and only that. It is disabled with the rest of the column, but
				// while a page is on its way it is also the thing reporting that — and a pulse under a
				// 0.45 veil is not one.
				picker

				modeButtons
					.opacity(inertOpacity)
			}
			// A load is the one reason a column cannot be used: the page being asked for has not
			// arrived, so every control here would be aimed at a display that is already on its way
			// somewhere. It lasts a few seconds and lets go by itself, so nothing has to be exempt from
			// it — the whole column comes back at once.
			.disabled(column.isLoading)
		}
		.frame(width: PanelMetrics.columnWidth)
		.padding(9)
		.background {
			RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
				.fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
		}
		.overlay {
			// The same treatment the Dock preview uses for the card under the pointer: a two-point
			// accent border and a barely-there fill. Borrowed rather than invented, because a person
			// who has seen one of these should not have to learn the other.
			//
			// The fill is `.quaternary`, the semantic style the drawn buttons inside the card used to
			// name. It was a fixed white wash before, which is what the Dock's fill looks like in the
			// dark appearance only — over a light popover it was all but invisible, so hovering a
			// column showed a border and no card at all for anyone not in dark mode.
			RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
				.strokeBorder(isHovering ? Color.accentColor : Color.clear, lineWidth: 2)
		}
		.contentShape(RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous))
		.onHover {
			isHovering = $0
		}
	}

	/**
	How dim a control looks while the column cannot be used.

	Named rather than written out at each of its two call sites, because it is one statement — nothing
	here will answer right now — and two literals are two chances for half of the column to say it.
	*/
	private var inertOpacity: Double {
		column.isLoading ? 0.45 : 1
	}

	/**
	Previous, the rotation mode, next, and how often it does it.

	The mode is one control that cycles rather than three that are mutually exclusive: it has three
	values and only one of them is true at a time, which is a switch, and three separate buttons would
	invite the question of what happens when two are pressed.

	The interval is here rather than in Settings because it is one display's business, the same as the
	mode it qualifies. It sits directly after the mode, inside the pair of arrows rather than outside
	them: "loop, every 30 minutes" is one sentence, and putting it beyond the right arrow split that
	sentence around a button belonging to a different idea — the arrows are a step you take by hand,
	the interval is how often the app takes one for you.

	It appears only while the display is rotating. There is no interval when nothing is moving, and a
	field showing a number that changes nothing is a field the user will change and then wonder about.
	Nothing is held for it in `pinned`: the row keeps the width of its three buttons, so the resting
	state of every column is the row that shipped, and a placeholder would have moved those three
	buttons off-centre for the majority of users who never leave `pinned` to make room for a control
	they never see. The row's height is pinned, so the column and the popover around it keep their size
	when the field does appear.
	*/
	@ViewBuilder
	private var rotationControls: some View {
		HStack(spacing: PanelMetrics.controlSpacing) {
			PanelButton(
				symbol: "chevron.left",
				label: String(localized: "Previous website"),
				isEnabled: column.canRotate
			) {
				model.step(.previous, on: column.display)
			}

			PanelButton(
				symbol: column.rotationMode.symbol,
				label: column.rotationMode.label,
				// Lit while it is doing something. Pinned is the resting state and says so by staying dark.
				isOn: column.rotationMode != .pinned
			) {
				model.cycleRotationMode(on: column.display)
			}

			if column.rotationMode != .pinned {
				PanelIntervalField(
					minutes: .init(
						get: { column.rotationIntervalMinutes },
						set: { model.setRotationInterval($0, on: column.display) }
					)
				)
			}

			PanelButton(
				symbol: "chevron.right",
				label: String(localized: "Next website"),
				isEnabled: column.canRotate
			) {
				model.step(.next, on: column.display)
			}
		}
		.frame(height: 32)
	}

	/**
	The two verbs no symbol says plainly, and Browsing Mode lights up while it is on.
	*/
	@ViewBuilder
	private var modeButtons: some View {
		HStack(spacing: 9) {
			PanelWideButton(
				title: String(localized: "Crop"),
				isEnabled: column.isShowing && column.websiteID != nil
			) {
				model.chooseRegion(on: column.display)
			}

			PanelWideButton(
				title: String(localized: "Browsing Mode"),
				isOn: browsingDisplays.contains(Display.settingsKey(for: column.display)),
				isEnabled: column.isShowing && column.websiteID != nil
			) {
				model.toggleBrowsingMode(on: column.display)
			}
		}
	}

	/**
	That this display's page did not load, when it did not.

	At the top of the column, under the display's name and above everything about the page, because it
	is the reason the rest of the column is not describing what the user expected — the menu this panel
	replaced put the same message at the very top for the same reason. It says one thing and hangs the
	error itself off the pointer: this is 260 points wide and a `WKWebView`'s own account of a failure
	is a sentence and a URL, which would take four lines and push the picture off the panel.

	`.secondary` rather than red, and rather than the accent. The argument written here before was that
	`PanelMetrics.onTint` was already this panel's colour for something happening, so a failure was the
	end of that story rather than a new word — but #73 gave the panel's drawing back to the system and
	that constant went with it, along with the pulse the argument rested on. What is left is the same
	conclusion by a shorter route: a caption under a title is `.secondary` here and on line 167 and 459,
	and a line that says a page did not load does not need a colour to be read as bad news.

	Outside the dimming and outside the `disabled`, like the chooser below it: a load in flight makes
	the controls inert and this is not a control. It clears itself, because `load` writes the failure
	away before it starts the next attempt.
	*/
	@ViewBuilder
	private var failureLine: some View {
		if let failure = column.failure {
			Text("This page did not load")
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.frame(maxWidth: PanelMetrics.columnWidth)
				.help(failure)
		}
	}

	/**
	Which display this column is about, and nothing else.

	A title rather than a control. Everything a display can be told to do is below it, where the
	picture is, so the one line above the picture is free to be the label that says which screen the
	person is looking at — truncated in the middle, because a display's name ends in the part that
	tells two of them apart.
	*/
	private var displayName: some View {
		Text(column.displayName)
			.font(.headline)
			.lineLimit(1)
			.truncationMode(.middle)
			.frame(maxWidth: PanelMetrics.columnWidth)
	}

	/**
	The wallpaper as it is now, or an honest stand-in for it.

	Five states, because five things can be true, and there used to be two. A picture. The app being
	off, which is not this display's doing and is read first for that reason — see `disabledReading`,
	and note that the two below it are both about a screen the user chose something for, while this one
	is about there being no wallpapers anywhere. "Switched off", where the power button beside it is
	off — the same two words that button's accessibility label uses, because they are describing the
	same fact and a column should not have two vocabularies for it. "No Website", but only where the
	display genuinely has none — that used to be what any column without a picture said, so a display
	whose page simply had not been photographed yet was told it had nothing on it. And the bare
	rectangle for the rest: the panel opens without pictures and the first refresh fills them in about
	a frame later, so this is what a picture looks like in the moment before it arrives. An empty rectangle is not mistaken for anything, which is the whole of what is
	wanted here — the previous opening's photograph, which is what used to be in this space, is
	mistaken for the page.

	Switched off is read before the website, because it is the reason there is no picture whatever the
	website says, and it is the answer to the question the user is actually asking at that moment: they
	pressed the button a moment ago. It is a new state rather than a fourth thing the bare rectangle
	covers, because the bare rectangle already means "a picture is a frame away" — and the two were
	indistinguishable, which is how a display that had been switched off could sit there looking like
	one still taking its first photograph. There was a live thumbnail in this space instead until the
	load behind it was refused; without a reading of its own, fixing that would have replaced a wrong
	picture with a rectangle that says nothing.
	*/
	@ViewBuilder
	private var preview: some View {
		// A fixed shape whatever the display is. A column that took the screen's own aspect would make
		// a portrait monitor tall enough to push everything else off the panel.
		ZStack {
			RoundedRectangle(cornerRadius: PanelMetrics.pictureRadius)
				.fill(.quaternary)

			if let snapshot = column.snapshot {
				Image(nsImage: snapshot)
					.resizable()
					.scaledToFill()
					.clipShape(RoundedRectangle(cornerRadius: PanelMetrics.pictureRadius))
			} else if let disabledReading = column.disabledReading {
				reading(disabledReading)
			} else if !column.isShowing {
				reading(String(localized: "Switched off"))
			} else if column.websiteID == nil {
				reading(String(localized: "No Website"))
			}
		}
		.frame(width: PanelMetrics.columnWidth, height: 162)
		.clipShape(RoundedRectangle(cornerRadius: PanelMetrics.pictureRadius))
		.overlay {
			RoundedRectangle(cornerRadius: PanelMetrics.pictureRadius)
				.strokeBorder(.separator)
		}
		.overlay(alignment: .bottomTrailing) {
			// On the picture rather than under it: these two say what this display is *doing*, and the
			// row below says what to show on it. Keeping them apart stops the column reading as five
			// controls in a stack with no grouping.
			HStack(spacing: 2) {
				PanelButton(
					symbol: column.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
					label: column.isMuted ? String(localized: "Muted") : String(localized: "Playing sound"),
					isEnabled: column.websiteID != nil
				) {
					model.toggleMuted(on: column.display)
				}

				PanelButton(
					symbol: column.isShowing ? "power" : "power.circle",
					label: column.isShowing ? String(localized: "Showing") : String(localized: "Switched off"),
					// Lit while the wallpaper is up, like every other lit control in the panel. It used
					// to be the inverse — lit while the display was switched *off* — which made this the
					// one control reading its lit state as "this button is engaged" instead of as "the
					// thing it turns on is on". Five controls now answer that question the same way.
					isOn: column.isShowing
				) {
					model.toggleShowing(on: column.display)
				}
			}
			.padding(2)
			// Not `pictureRadius`, and not derived from it: the pill floats six points inside the
			// picture, so a concentric radius would be 2, and 7 is what the two buttons inside it
			// want. It is the only rounded thing in the app with that argument, so it has
			// no name — a token with one user is a number with a longer spelling.
			// swiftlint:disable:next hardcoded_corner_radius
			.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
			.padding(6)
		}
	}

	/**
	One of the picture area's readings.

	Written once for all of them because there are three now and were two, and each of the two carried
	its own copy of the same two modifiers — which is how a fourth would have arrived looking slightly
	different from its neighbours. The text is passed in already localized rather than as a key, so
	`disabledReading` — which is a sentence chosen in the model, where the app's reason for being off
	is known — draws through the same call as the two the view chooses itself.
	*/
	private func reading(_ text: String) -> some View {
		Text(text)
			.font(.callout)
			.foregroundStyle(.secondary)
			.multilineTextAlignment(.center)
			.padding(.horizontal, 9)
	}

	/**
	The playlist this display is showing, from the ones it may be offered.

	Built to match the website chooser below rather than as a `Picker`, for the reason that one is a
	`Menu`: a picker draws the chosen value itself and truncates it, and a playlist's name is the user's
	own word for a list they made. Two controls that mean "what to show", one above the other, that do
	not look alike would read as two unrelated things.

	Never empty in practice — the default playlist takes no binding, so every display is offered at
	least it — but disabled when it is, rather than drawing a menu that opens onto nothing.
	*/
	private var playlistChooser: some View {
		chooser(
			title: column.playlistName,
			width: PanelMetrics.chooserWidth,
			isEnabled: !column.playlistChoices.isEmpty,
			isLoading: false
		) {
			ForEach(column.playlistChoices) { choice in
				Button(choice.name) {
					model.selectPlaylist(choice.id, on: column.display)
				}
			}
		}
	}

	/**
	The website on this display, from the playlist it is showing.

	Adding a website is a different act with a different home, so a playlist with nothing in it offers
	nothing here rather than a form: the panel points displays at things that exist.
	*/
	private var picker: some View {
		chooser(
			title: column.websiteName ?? String(localized: "No Website"),
			width: PanelMetrics.websiteChooserWidth,
			isEnabled: !column.choices.isEmpty,
			isLoading: column.isLoading
		) {
			ForEach(column.choices, id: \.id) { choice in
				Button(choice.menuTitle) {
					model.selectWebsite(choice, on: column.display)
				}
			}
		}
	}

	/**
	One of the column's two choosers.

	A stock pull-down, which sizes itself to the name in it. A `Menu` rather than a `Picker` because the
	label still has to be ours — a picker draws the chosen value itself and cannot slide it — but
	nothing forces a width any more. It was forced before, and a `Menu` will not take one: measured, it
	sizes its bezel to its label's text and treats every `frame` as a ceiling rather than a size, so the
	choice was a drawn pill or a control that hugs its name. It hugs. Two columns showing names of
	different lengths now show controls of different widths, which is what a pull-down does everywhere
	else on the Mac.

	The ceiling still matters, and is the one thing the frame is for: without it the widest page titles
	push past the column they are in.

	Written once for both, because they are the same control twice and the second one arriving is
	exactly when a copy would have been made — the chevron's fixed slot, the marquee, and the order the
	width, padding and background have to be applied in are three things that look arbitrary and are
	not.
	*/
	private func chooser(
		title: String,
		width: Double,
		isEnabled: Bool,
		isLoading: Bool,
		@ViewBuilder items: () -> some View
	) -> some View {
		Menu {
			items()
		} label: {
			// An explicit height, because `MarqueeText` is a `GeometryReader` and has no height of its
			// own to offer the label. No chevron of ours beside it: a stock pull-down draws one itself,
			// at the trailing edge, where every other pull-down on the Mac has it.
			MarqueeText(text: title, isActive: isHovering)
				.frame(height: 16)
		}
		.controlSize(.large)
		.frame(maxWidth: width)
		.disabled(!isEnabled)
		.overlay(alignment: .leading) { loadingIndicator(isLoading) }
	}

	/**
	A stock spinner in the margin beside the website chooser, while this display's page is on its way.

	Beside that control rather than somewhere else in the column, because it is the control the website
	was picked with: a page takes seconds to arrive and nothing on the desktop changes while it does —
	swap loading holds the old one up on purpose — so the answer belongs on the thing that was just
	pressed. An overlay rather than a stack, so the chooser does not step sideways while it is there,
	and outside the control rather than inside because the control is only as wide as its name and a
	short name leaves nothing to put it in. Twenty-two points out, which is inside the column's own
	padding even when a title has grown the chooser to its ceiling.

	It replaced a pill breathing behind the whole control in the app's own orange, at
	`WallpaperScene.loadingPulseDuration`, so that it and the menu bar icon would read as one thing
	happening rather than two. That rate is no longer shared: a `ProgressView` is the system's answer to
	"this is in progress" and paces itself. The menu bar keeps the pulse, because a status item is the
	one surface in the app with nothing system-drawn to reach for.

	Only the website chooser ever asks for it. The playlist above changes what a display may show and
	not what it is fetching, so a load is not its answer to give.
	*/
	@ViewBuilder
	private func loadingIndicator(_ isLoading: Bool) -> some View {
		if isLoading {
			ProgressView()
				.controlSize(.small)
				.offset(x: -22)
		}
	}
}
