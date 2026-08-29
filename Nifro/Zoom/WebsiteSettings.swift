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
		LabeledContent {
			HStack {
				Text(zoom.summaryText)
					.foregroundStyle(.secondary)
				if zoom != nil {
					Button(String(localized: "Show Whole Page")) {
						zoom = nil
					}
				}
			}
		} label: {
			Text("Region")
				.explained(String(localized: "Use the panel's Crop button to move and zoom the wallpaper, and where you leave it is the region — remembered as a place and a magnification rather than a rectangle."))
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
		Toggle(isOn: isEnabled) {
			Text("Only show at certain hours")
				.explained(String(localized: "Useful with rotation — a news page in the morning, something calmer at night; a window that runs past midnight, 22 to 6, works."))
		}

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
Where a link that leaves this website opens.

A picker with three entries rather than a switch, because there really are three answers and only two
of them are the website's own. "Follow Settings" is the state every website is in until somebody
decides otherwise, and it is first because the unset state is a real answer, not the absence of one.
*/
struct WebsiteExternalLinksSetting: View {
	@Binding var externalLinks: Website.ExternalLinks

	var body: some View {
		Picker(selection: $externalLinks) {
			ForEach(Website.ExternalLinks.allCases, id: \.self) { option in
				Text(option.title).tag(option)
			}
		} label: {
			Text("External links")
				.explained(String(localized: "Where a link off this website goes — a site you sign in to wants “In Nifro”, because signing in navigates away from it and the page you come back to is the one you wanted."))
		}
	}
}

/**
Whether a website is allowed to make noise.
*/
struct WebsiteAudioSetting: View {
	@Binding var audio: Website.Audio

	var body: some View {
		Picker(selection: $audio) {
			ForEach(Website.Audio.allCases, id: \.self) { option in
				Text(option.title).tag(option)
			}
		} label: {
			Text("Audio")
				.explained(String(localized: "Whether this website may make noise, remembered per website; it mutes the page's audio and video elements, not sound made with the Web Audio API."))
		}
	}
}

/**
How often a website reloads itself.

Off follows Settings, which is the interval for everything that has no opinion. A page that does have
one — a calendar, a departure board, a poster that never changes — sets it here, where it stays with
the website rather than being imposed on every other one.
*/
struct WebsiteReloadSetting: View {
	@Binding var overridesReloadInterval: Bool
	@Binding var reloadInterval: Double

	var body: some View {
		Toggle(isOn: $overridesReloadInterval) {
			Text("Reload on its own schedule")
				.explained(String(localized: "How often a page goes stale is a property of the page; off follows the interval in Settings."))
		}

		if overridesReloadInterval {
			IntervalField(seconds: $reloadInterval)
		}
	}
}
