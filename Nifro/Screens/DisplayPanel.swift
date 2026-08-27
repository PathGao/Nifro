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
		.task {
			// The controller drives the refreshes; this is only for the first paint, and for a preview
			// where there is no controller at all.
			await model.refresh()
		}
	}
}

/**
Everything that is not about one display.

Icons, because these five are the app's own verbs rather than a display's, and a row of words here
would compete with the columns above for the eye. Quit keeps its label: it is the one that cannot be
undone, and an unlabelled power symbol beside four others is exactly the button somebody presses by
mistake.
*/
private struct PanelFooter: View {
	@ObservedObject private var model: DisplayPanelModel

	init(model: DisplayPanelModel) {
		self.model = model
	}

	var body: some View {
		HStack(spacing: 10) {
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

	private func onSelect(_ id: Website.ID) {
		model.show(id)
	}

	var body: some View {
		VStack(spacing: 9) {
			displayName

			VStack(spacing: 9) {
				MarqueeText(text: column.websiteName ?? String(localized: "No Website"), isActive: isHovering)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.frame(width: PanelMetrics.columnWidth, height: 16)

				preview

				rotationControls

				picker

				modeButtons
			}
			// A follower shows the leader's wallpaper, so its own controls would be arguing with the next
			// correction five seconds later. Everything below the title is inert; the sync button in the
			// title is not, because it is how the arrangement is undone and disabling it would leave a
			// group with no way out if the leader's display went away.
			.disabled(column.isFollowing)
			.opacity(column.isFollowing ? 0.45 : 1)
		}
		.frame(width: PanelMetrics.columnWidth)
		.padding(9)
		.background {
			RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
				.fill(isHovering ? PanelMetrics.hoverFill : AnyShapeStyle(.clear))
		}
		.overlay {
			// The same treatment the Dock preview uses for the card under the pointer: a two-point
			// accent border and a barely-there fill. Borrowed rather than invented, because a person
			// who has seen one of these should not have to learn the other.
			//
			// The fill is the same `hoverFill` the buttons inside the card use. It was a fixed white
			// wash before, which is what the Dock's fill looks like in the dark appearance only — over
			// a light popover it was all but invisible, so hovering a column showed a border and no
			// card at all for anyone not in dark mode.
			RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
				.strokeBorder(isHovering ? Color.accentColor : Color.clear, lineWidth: 2)
		}
		.contentShape(RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous))
		.onHover {
			isHovering = $0
		}
		.animation(.spring(response: 0.2, dampingFraction: 0.82), value: isHovering)
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
	they never see. The row's height is pinned to the buttons' own 22 points, so the column and the
	popover around it keep their size when the field does appear.
	*/
	@ViewBuilder
	private var rotationControls: some View {
		HStack(spacing: 10) {
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
		.frame(height: 22)
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
	The display's name, with a button beside it for syncing this display to another.

	A button rather than a menu on the title itself. The title looked like a title, so the way into
	syncing was a thing you had to already know was there — the one control in the panel with no
	affordance at all.

	Lit when this display is in a group. A ticked entry means already synced; choosing it again breaks
	that pairing, and the entry that leaves is the one that was picked rather than the one whose menu
	it is — the leader's menu is the one that stays usable.
	*/
	@ViewBuilder
	private var displayName: some View {
		HStack(spacing: 5) {
			Text(column.displayName)
				.font(.headline)
				.lineLimit(1)
				.truncationMode(.middle)

			if !column.syncOptions.isEmpty {
				Menu {
					ForEach(column.syncOptions) { option in
						Button {
							model.apply(option, on: column.display)
						} label: {
							switch option {
							case .follow(_, let name):
								Text("Show what \(name) shows")
							case .unfollow(let name):
								Label(String(localized: "Stop following \(name)"), systemImage: "checkmark")
							case .releaseAll:
								Text("Release every display following this one")
							}
						}
					}
				} label: {
					Image(systemName: "link")
						.font(PanelMetrics.symbolFont)
						.frame(width: 22, height: 20)
						.foregroundStyle(isSynced ? PanelMetrics.onForeground : AnyShapeStyle(.secondary))
						.background(
							isSynced ? AnyShapeStyle(PanelMetrics.onTint) : AnyShapeStyle(.quinary),
							in: RoundedRectangle(cornerRadius: PanelMetrics.smallCornerRadius)
						)
				}
				.menuStyle(.borderlessButton)
				.menuIndicator(.hidden)
				.fixedSize()
				.help(String(localized: "Show the same wallpaper as another display"))
			}
		}
		.frame(maxWidth: PanelMetrics.columnWidth)
	}

	/**
	Lit when this display is part of an arrangement, whether it leads it or follows it.
	*/
	private var isSynced: Bool {
		column.isFollowing || column.syncOptions.contains { if case .releaseAll = $0 { true } else { false } }
	}

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
			} else {
				Text("No Website")
					.font(.callout)
					.foregroundStyle(.secondary)
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
					// Lit while the display is switched *off*, which is the one caller that reads
					// `onTint` as "this button is engaged" rather than as "the thing it turns on is
					// on". The other four read it the second way, and only the second way is written
					// down. Left as it ships until somebody picks which reading the app has; both are
					// defensible and the defect is that the choice is unrecorded, not that this line
					// is wrong.
					isOn: !column.isShowing
				) {
					model.toggleShowing(on: column.display)
				}
			}
			.padding(4)
			// Not `pictureRadius`, and not derived from it: the pill floats six points inside the
			// picture, so a concentric radius would be 2, and 7 is what the two 22-point buttons
			// inside it want. It is the only rounded thing in the app with that argument, so it has
			// no name — a token with one user is a number with a longer spelling.
			// swiftlint:disable:next hardcoded_corner_radius
			.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
			.padding(6)
		}
	}

	/**
	The website on this display, from the ones it already owns.

	A `Menu` rather than a `Picker` because the label has to be ours: a picker draws the chosen value
	itself, truncated, and the name is the one thing in the column that needs room. Fixed width, so
	two columns do not end up different sizes because one website has a longer title.

	Adding a website is a different act with a different home, so an empty display offers nothing here
	rather than a form: the panel points displays at things that exist.
	*/
	@ViewBuilder
	private var picker: some View {
		Menu {
			ForEach(column.choices, id: \.id) { choice in
				Button(choice.menuTitle) {
					onSelect(choice.id)
				}
			}
		} label: {
			HStack(spacing: 0) {
				// Pinned to the left edge and given a fixed slot, so the name is centred in what is left
				// rather than the pair of them drifting together as the name changes length.
				Image(systemName: "chevron.up.chevron.down")
					.font(PanelMetrics.symbolFont)
					.foregroundStyle(.secondary)
					.frame(width: 16, alignment: .leading)

				MarqueeText(text: column.websiteName ?? String(localized: "No Website"), isActive: isHovering)
					.font(PanelMetrics.font)
					.frame(maxWidth: .infinity)
					// The chevron's slot, given back, so the name is centred on the control and not on the
					// space beside it.
					.padding(.trailing, 16)
			}
			.frame(maxWidth: .infinity)
			.frame(height: PanelMetrics.height)
		}
		.menuStyle(.borderlessButton)
		.menuIndicator(.hidden)
		// Width, then padding, then background, in that order. `borderlessButton` sizes a menu to its
		// label, so the width has to be forced from outside the label — and the background has to come
		// after it, or it paints the pill at the label's size and the frame merely centres that.
		.frame(
			width: PanelMetrics.chooserWidth - PanelMetrics.horizontalPadding * 2,
			height: PanelMetrics.height
		)
		.padding(.horizontal, PanelMetrics.horizontalPadding)
		.background(.quinary, in: RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius))
		.disabled(column.choices.isEmpty)
	}
}
