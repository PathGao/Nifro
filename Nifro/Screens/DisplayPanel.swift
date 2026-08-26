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
				DisplayColumn(column: column) {
					model.show($0)
				}
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
	let onSelect: (Website.ID) -> Void

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

			picker
		}
		.frame(width: 260)
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
					onSelect(id)
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
