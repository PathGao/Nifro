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
		HStack(alignment: .top, spacing: 16) {
			ForEach(model.columns) { column in
				DisplayColumn(column: column, model: model)
			}
		}
		.padding(16)
		.task {
			await model.refresh()
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

	init(column: DisplayPanelModel.Column, model: DisplayPanelModel) {
		self.column = column
		self.model = model
	}

	var body: some View {
		VStack(spacing: 6) {
			Text(column.displayName)
				.font(.headline)
				.lineLimit(1)

			Text(column.websiteName ?? String(localized: "No Website"))
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.lineLimit(1)

			preview

			rotationControls

			picker

			modeButtons
		}
		.frame(width: 260)
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

	Adding a website is a different act with a different home, so an empty display offers nothing here
	rather than a form: the panel points displays at things that exist.
	*/
	@ViewBuilder
	private var picker: some View {
		Picker(selection: Binding(
			get: { column.websiteID },
			set: {
				if let id = $0 {
					model.show(id)
				}
			}
		)) {
			ForEach(column.choices, id: \.id) {
				Text($0.menuTitle.truncating(to: 28)).tag($0.id as Website.ID?)
			}
		} label: {
			EmptyView()
		}
		.labelsHidden()
		.disabled(column.choices.isEmpty)
	}
}
