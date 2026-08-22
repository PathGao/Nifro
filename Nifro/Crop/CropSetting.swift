import SwiftUI

/**
Editor for a website's crop region.

Numbers are page pixels measured from the top-left of the page. The four of them are one setting, not four, so the form treats them that way: cropping is either off or fully specified, and a half-filled crop never reaches the model.
*/
struct CropSetting: View {
	@Binding var crop: CGRect?

	private var isEnabled: Binding<Bool> {
		.init(
			get: { crop != nil },
			set: { crop = $0 ? Self.defaultCrop : nil }
		)
	}

	/**
	A starting region small enough to be obviously a crop, placed away from the corner so it does not look like a mistake.
	*/
	private static let defaultCrop = CGRect(x: 0, y: 0, width: 600, height: 400)

	var body: some View {
		Toggle("Crop to a region", isOn: isEnabled)
			.help("Shows only part of the page, cutting away navigation bars, borders and anything else around the part worth looking at. The window shrinks to the cropped region, so the rest of your desktop stays usable.")

		if crop != nil {
			HStack {
				field("X", value: binding(\.origin.x))
				field("Y", value: binding(\.origin.y))
				field("Width", value: binding(\.size.width))
				field("Height", value: binding(\.size.height))
			}
			.help("Page pixels, measured from the top-left of the page.")
		}
	}

	private func field(_ label: String, value: Binding<Double>) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
			TextField(label, value: value, format: .number.precision(.fractionLength(0)))
				.labelsHidden()
				.frame(width: 64)
		}
	}

	private func binding(_ keyPath: WritableKeyPath<CGRect, CGFloat>) -> Binding<Double> {
		.init(
			get: { Double(crop?[keyPath: keyPath] ?? 0) },
			set: { newValue in
				guard var crop else {
					return
				}

				// A zero or negative extent would produce a window macOS cannot show, and the user is mid-typing, not asking for that.
				crop[keyPath: keyPath] = max(0, CGFloat(newValue))
				self.crop = crop.standardized
			}
		)
	}
}

/**
Which display a website appears on.

Only offered when there is more than one display: on a single-display Mac the choice does not exist, and the answer to "show a different page on each screen" — the most-asked-for thing upstream (Plash#2) — is that the display belongs to the website, not to the app.
*/
struct WebsiteDisplaySetting: View {
	@Binding var display: Display?

	@ObservedObject private var displays = Display.observable

	var body: some View {
		if displays.wrappedValue.all.count > 1 {
			Picker("Show on", selection: $display) {
				Text("Default display").tag(nil as Display?)
				ForEach(displays.wrappedValue.all) { candidate in
					Text(candidate.localizedName).tag(candidate as Display?)
				}
			}
			.help("Each website can live on its own screen. “Default display” follows the choice in Settings.")
		}
	}
}

/**
The hours a website is allowed to be showing.

Off by default: most wallpapers should just be up. When it is on, both ends are needed — a window with only one end set is not a window, and a half-filled schedule should never reach the model.
*/
struct WebsiteScheduleSetting: View {
	@Binding var startHour: Int?
	@Binding var endHour: Int?

	private var isEnabled: Binding<Bool> {
		.init(
			get: { startHour != nil && endHour != nil },
			set: { on in
				startHour = on ? 8 : nil
				endHour = on ? 18 : nil
			}
		)
	}

	var body: some View {
		Toggle("Only show at certain hours", isOn: isEnabled)
			.help("Useful with rotation: a news page in the morning, something calmer at night. A window that runs past midnight — 22 to 6 — works.")

		if startHour != nil, endHour != nil {
			HStack {
				hourPicker("From", selection: $startHour)
				hourPicker("Until", selection: $endHour)
			}
		}
	}

	private func hourPicker(_ label: String, selection: Binding<Int?>) -> some View {
		Picker(label, selection: selection) {
			ForEach(0..<24, id: \.self) { hour in
				Text(String(format: "%02d:00", hour)).tag(hour as Int?)
			}
		}
		.frame(maxWidth: 140)
	}
}

/**
Whether a website keeps a browser running or gets photographed periodically.

Per website rather than a global switch, because the answer is a property of the page: a clock is the same picture for a minute at a time, a screensaver is not.
*/
struct WebsiteRenderingSetting: View {
	@Binding var rendering: Website.Rendering

	var body: some View {
		Picker("Rendering", selection: $rendering) {
			ForEach(Website.Rendering.allCases, id: \.self) { option in
				Text(option.title).tag(option)
			}
		}
		.help(rendering.explanation)
	}
}
