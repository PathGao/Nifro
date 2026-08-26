import SwiftUI

/**
One column per display, side by side.

The menu this replaces could only ever describe one display. Every item in it acted on "the current
website", and with two screens that meant whichever one last held a flag — so the menu was both
telling the user about one display and hiding that fact. Showing every display at once removes the
question rather than answering it.

The picture is the wallpaper itself, taken from the app's own web view. No screen recording is asked
for, and none is needed.
*/
struct DisplayPanel: View {
	@ObservedObject var model: DisplayPanelModel

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

private struct DisplayColumn: View {
	let column: DisplayPanelModel.Column
	@ObservedObject var model: DisplayPanelModel

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

			WebsitePicker(column: column, model: model)
		}
		.frame(width: 260)
	}

	@ViewBuilder
	private var preview: some View {
		// Fixed 16:10 whatever the display is. A column that changed shape with the screen would make a
		// portrait monitor tall enough to push everything else off the panel.
		ZStack {
			RoundedRectangle(cornerRadius: 8)
				.fill(.quaternary)

			if let image = column.snapshot {
				Image(nsImage: image)
					.resizable()
					.aspectRatio(contentMode: .fill)
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
}

/**
The website on this display, chosen from the ones already set up.

Adding a website is a different act with a different home, so the empty state sends people to the
same list rather than to a form: the panel is for pointing displays at things that exist.
*/
private struct WebsitePicker: View {
	let column: DisplayPanelModel.Column
	@ObservedObject var model: DisplayPanelModel

	var body: some View {
		Picker(selection: Binding(
			get: { column.websiteID },
			set: { model.show($0, on: column.display) }
		)) {
			ForEach(model.choices(for: column.display), id: \.id) {
				Text($0.menuTitle.truncating(to: 28)).tag($0.id as Website.ID?)
			}
		} label: {
			EmptyView()
		}
		.labelsHidden()
		.disabled(model.choices(for: column.display).isEmpty)
	}
}
