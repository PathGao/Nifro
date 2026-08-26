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

			PanelWideButton(title: String(localized: "Quit Nifro")) {
				SSApp.quit()
			}
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

	init(column: DisplayPanelModel.Column, model: DisplayPanelModel) {
		self.column = column
		self.model = model
	}

	private func onSelect(_ id: Website.ID) {
		model.show(id)
	}

	var body: some View {
		VStack(spacing: 6) {
			displayName

			MarqueeText(text: column.websiteName ?? String(localized: "No Website"), isActive: isHovering)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.frame(width: 260, height: 16)

			preview

			rotationControls

			picker

			modeButtons
		}
		.frame(width: 260)
		.padding(9)
		.background {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(isHovering ? Color.white.opacity(0.15) : Color.clear)
		}
		.overlay {
			// The same treatment the Dock preview uses for the card under the pointer: a two-point
			// accent border and a barely-there fill. Borrowed rather than invented, because a person
			// who has seen one of these should not have to learn the other.
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.strokeBorder(isHovering ? Color.accentColor : Color.clear, lineWidth: 2)
		}
		.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.onHover {
			isHovering = $0
		}
		.animation(.spring(response: 0.2, dampingFraction: 0.82), value: isHovering)
	}

	/**
	Previous, the rotation mode, next.

	The mode is one control that cycles rather than three that are mutually exclusive: it has three
	values and only one of them is true at a time, which is a switch, and three separate buttons would
	invite the question of what happens when two are pressed.
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
				isOn: column.rotationMode != .loop
			) {
				model.cycleRotationMode(on: column.display)
			}

			PanelButton(
				symbol: "chevron.right",
				label: String(localized: "Next website"),
				isEnabled: column.canRotate
			) {
				model.step(.next, on: column.display)
			}
		}
	}

	/**
	The two verbs no symbol says plainly, and Browsing Mode lights up while it is on.
	*/
	@ViewBuilder
	private var modeButtons: some View {
		HStack(spacing: 6) {
			PanelWideButton(
				title: String(localized: "Crop"),
				isEnabled: column.websiteID != nil
			) {
				model.chooseRegion(on: column.display)
			}

			PanelWideButton(
				title: String(localized: "Browsing Mode"),
				isOn: model.isBrowsingMode,
				isEnabled: column.websiteID != nil
			) {
				model.toggleBrowsingMode()
			}
		}
	}

	/**
	The display's name, and the way into syncing it with another.

	A menu on the title rather than a control of its own, because syncing is a statement about *this
	display and that one* and the title is the only thing on the column that names a display. A lit
	entry means already synced; choosing it again breaks the group.
	*/
	@ViewBuilder
	private var displayName: some View {
		if column.syncTargets.isEmpty {
			Text(column.displayName)
				.font(.headline)
				.lineLimit(1)
				.frame(maxWidth: 260)
		} else {
			Menu {
				ForEach(column.syncTargets, id: \.name) { target in
					Button {
						model.toggleSync(column.display, with: target.display)
					} label: {
						if target.isSynced {
							Label(target.name, systemImage: "checkmark")
						} else {
							Text(target.name)
						}
					}
				}
			} label: {
				HStack(spacing: 3) {
					Text(column.displayName)
						.font(.headline)
						.lineLimit(1)
						.truncationMode(.middle)

					if column.syncTargets.contains(where: \.isSynced) {
						Image(systemName: "link")
							.font(.system(size: 10, weight: .semibold))
							.foregroundStyle(.tint)
					}
				}
			}
			.menuStyle(.borderlessButton)
			.menuIndicator(.hidden)
			.fixedSize()
		}
	}

	@ViewBuilder
	private var preview: some View {
		// A fixed shape whatever the display is. A column that took the screen's own aspect would make
		// a portrait monitor tall enough to push everything else off the panel.
		ZStack {
			RoundedRectangle(cornerRadius: 8)
				.fill(.quaternary)

			if let snapshot = column.snapshot {
				Image(nsImage: snapshot)
					.resizable()
					.scaledToFill()
					.clipShape(RoundedRectangle(cornerRadius: 8))
			} else {
				Text("No Website")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: 260, height: 162)
		.clipShape(RoundedRectangle(cornerRadius: 8))
		.overlay {
			RoundedRectangle(cornerRadius: 8)
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
					isOn: !column.isShowing
				) {
					model.toggleShowing(on: column.display)
				}
			}
			.padding(4)
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
			HStack(spacing: 4) {
				MarqueeText(text: column.websiteName ?? String(localized: "No Website"), isActive: isHovering)
					.frame(height: 15)

				Image(systemName: "chevron.up.chevron.down")
					.font(.system(size: 9, weight: .semibold))
					.foregroundStyle(.secondary)
			}
			.frame(width: 216, alignment: .leading)
		}
		.menuStyle(.borderlessButton)
		.menuIndicator(.hidden)
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(.quinary, in: RoundedRectangle(cornerRadius: 5))
		.disabled(column.choices.isEmpty)
	}
}
