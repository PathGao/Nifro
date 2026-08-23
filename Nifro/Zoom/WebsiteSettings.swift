import SwiftUI

/**
Editor for which part of a page fills the wallpaper.

The numbers are here for adjusting a region, not for choosing one — nobody knows where the part they
want sits as a percentage. Choosing is done by dragging over the wallpaper, from the menu.
*/
struct ZoomSetting: View {
	@Binding var zoom: Zoom?

	private var isEnabled: Binding<Bool> {
		.init(
			get: { zoom != nil },
			set: { zoom = $0 ? Self.defaultZoom : nil }
		)
	}

	/**
	A starting region small enough that turning this on visibly does something.
	*/
	private static let defaultZoom = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2)

	var body: some View {
		Toggle("Zoom into part of the page", isOn: isEnabled)
			.help("Fills the screen with one part of the page, cutting away navigation bars, borders and whatever else surrounds it. Use “Choose Region…” in the menu to frame it by dragging over the wallpaper.")

		if zoom != nil {
			HStack {
				field("Centre X", value: binding(\.center.x), format: .percent)
				field("Centre Y", value: binding(\.center.y), format: .percent)
				field("Zoom", value: binding(\.scale), format: .magnification)
			}
			.help("The centre is a position on the page, from its top-left corner. The zoom is how many times that part is enlarged.")
		}
	}

	private enum Format {
		case percent
		case magnification
	}

	private func field(_ label: String, value: Binding<Double>, format: Format) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
			switch format {
			case .percent:
				TextField(label, value: value, format: .percent.precision(.fractionLength(0)))
					.labelsHidden()
					.frame(width: 64)
			case .magnification:
				TextField(label, value: value, format: .number.precision(.fractionLength(1)))
					.labelsHidden()
					.frame(width: 64)
			}
		}
	}

	private func binding(_ keyPath: WritableKeyPath<Zoom, CGFloat>) -> Binding<Double> {
		.init(
			get: { Double(zoom?[keyPath: keyPath] ?? 0) },
			set: { newValue in
				guard var zoom else {
					return
				}

				zoom[keyPath: keyPath] = CGFloat(min(max(newValue, 0), 1))
				self.zoom = zoom
			}
		)
	}

	private func binding(_ keyPath: WritableKeyPath<Zoom, Double>) -> Binding<Double> {
		.init(
			get: { zoom?[keyPath: keyPath] ?? 1 },
			set: { newValue in
				guard var zoom else {
					return
				}

				// Below 1 the region is bigger than the page, which is a window full of nothing along
				// two edges. The user is mid-typing, not asking for that.
				zoom[keyPath: keyPath] = min(max(newValue, 1), 20)
				self.zoom = zoom
			}
		)
	}
}

/**
Which display a website appears on.

Only offered when there is more than one display. Showing a different page on each screen is the most-asked-for thing upstream (Plash#2), and it needs the display to belong to the website rather than to the app.
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

Off by default, because most wallpapers should just stay up. When it is on, both ends are required. One end alone gives no window, so a half-filled schedule never reaches the model.
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
			.help("Useful with rotation. A news page in the morning, something calmer at night. A window that runs past midnight, 22 to 6, works.")

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

Per website rather than a global switch, because the answer belongs to the page. A clock is the same picture for a minute at a time. A screensaver is not.
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

/**
Whether a website can be clicked without turning on Browsing Mode.
*/
struct WebsiteInteractionSetting: View {
	@Binding var allowsInteraction: Bool

	var body: some View {
		Toggle("Clickable on the desktop", isOn: $allowsInteraction)
			.help("Lets you use the page without switching to Browsing Mode. The window then stops letting clicks through, so your desktop icons sit behind it, and the page has to keep rendering.")
	}
}

/**
Whether a website is allowed to make noise.
*/
struct WebsiteAudioSetting: View {
	@Binding var audio: Website.Audio

	var body: some View {
		Picker("Audio", selection: $audio) {
			ForEach(Website.Audio.allCases, id: \.self) { option in
				Text(option.title).tag(option)
			}
		}
		.help("Muting is done by keeping every audio and video element on the page muted. It covers media elements, not sound a page generates with the Web Audio API.")
	}
}
