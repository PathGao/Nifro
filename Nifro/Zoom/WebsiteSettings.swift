import SwiftUI

/**
Shows which part of the page fills the wallpaper, and the way back to all of it.

No control for choosing the region. Choosing means dragging a rectangle over the wallpaper, which
cannot be done from inside a dialog covering it — and the version with a switch and three number
fields was worse than nothing: turning it on jumped to an arbitrary magnification of the middle of
the page, and nobody could connect those numbers to the thing in the menu that actually does this.

So this reports and undoes, and says where the doing is.
*/
struct ZoomSetting: View {
	@Binding var zoom: Zoom?

	var body: some View {
		LabeledContent(String(localized: "Region")) {
			HStack {
				Text(summary)
					.foregroundStyle(.secondary)
				if zoom != nil {
					Button(String(localized: "Show Whole Page")) {
						zoom = nil
					}
				}
			}
		}
		.help("Choose a region with “Choose Region…” in the Nifro menu: drag a rectangle over the wallpaper and that part fills the screen. The rectangle is locked to the shape of your screen, and it is remembered as a place and a magnification, so the same website works on a second display of a different shape.")
	}

	private var summary: String {
		guard let zoom else {
			return String(localized: "Whole page")
		}

		let scale = zoom.scale.formatted(.number.precision(.fractionLength(1)))
		let across = Int((zoom.center.x * 100).rounded())
		let down = Int((zoom.center.y * 100).rounded())

		return String(localized: "\(scale)× at \(across)%, \(down)%")
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
				hourPicker(String(localized: "From"), selection: $startHour)
				hourPicker(String(localized: "Until"), selection: $endHour)
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
		.help("Whether this website may make noise. Remembered for this website, so a clock stays silent and a live stream does not, and it is the same setting as Sound in the Nifro menu — change it in either place. Muting works by holding every audio and video element on the page muted, so it covers media and not sound a page generates with the Web Audio API.")
	}
}
