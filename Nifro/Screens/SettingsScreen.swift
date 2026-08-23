import SwiftUI
import WebKit
import LaunchAtLogin
import KeyboardShortcuts

struct SettingsScreen: View {
	var body: some View {
		TabView {
			GeneralSettings()
				.settingsTabItem(.general)
			ShortcutsSettings()
				.settingsTabItem(.shortcuts)
			AdvancedSettings()
				.settingsTabItem(.advanced)
			AboutSettings()
				.settingsTabItem(.about)
		}
		.formStyle(.grouped)
		.frame(width: 400)
		.fixedSize()
		.windowLevel(.floating + 1) // To ensure it's always above the Nifro browser window.
	}
}

private struct GeneralSettings: View {
	var body: some View {
		Form {
			Section {
				LaunchAtLogin.Toggle()
			}
			Section {
				ReloadIntervalSetting()
				OpacitySetting()
			}
			Section {
				DisplaySetting()
				ShowOnAllSpacesSetting()
			}
		}
	}
}

private struct ShortcutsSettings: View {
	var body: some View {
		Form {
			KeyboardShortcuts.Recorder("Toggle enabled state", name: .toggleEnabled)
			KeyboardShortcuts.Recorder("Toggle browsing mode", name: .toggleBrowsingMode)
			KeyboardShortcuts.Recorder("Hold to use the page", name: .holdToInteract)
			KeyboardShortcuts.Recorder("Toggle sound", name: .toggleSound)
			KeyboardShortcuts.Recorder("Choose region", name: .chooseRegion)
			KeyboardShortcuts.Recorder("Reload website", name: .reload)
			KeyboardShortcuts.Recorder("Next website", name: .nextWebsite)
			KeyboardShortcuts.Recorder("Previous website", name: .previousWebsite)
			KeyboardShortcuts.Recorder("Random website", name: .randomWebsite)
		}
	}
}

private struct AdvancedSettings: View {
	var body: some View {
		Form {
			Section {
				BringBrowsingModeToFrontSetting()
				Defaults.Toggle(String(localized: "Deactivate while on battery"), key: .deactivateOnBattery)
				ContentRulesSetting()
				FreezeWhenCoveredSetting()
				PlaylistIntervalSetting()
				Defaults.Toggle(String(localized: "Restore scroll position after reload"), key: .restoreScrollPosition)
					.help("A page that reloads on a timer starts back at the top. This puts it back where it was, which matters for a long page you scrolled to a particular part of.")
				Defaults.Toggle(String(localized: "Reload when the Mac wakes"), key: .reloadOnWake)
				DimWhenUnfocusedSetting()
				OpenExternalLinksInBrowserSetting()
				HideMenuBarIconSetting()
			}
			Section {} // Padding
			Section {} footer: {
				ClearWebsiteDataSetting()
					.controlSize(.small)
			}
		}
	}
}

private struct FreezeWhenCoveredSetting: View {
	var body: some View {
		Defaults.Toggle(
			String(localized: "Only render what is on show"),
			key: .freezeWhenCovered
		)
		.help("When other windows cover most of the wallpaper, Nifro shrinks the window to whatever is still visible, such as the strip behind the Dock, and keeps rendering only that. When nothing is visible it holds the last frame. Turn this off to keep drawing the whole page.")
	}
}

private struct ContentRulesSetting: View {
	@Default(.contentRulesURL) private var url

	var body: some View {
		TextField("Content blocking rules", text: $url.withDefaultValue(""), prompt: Text("URL to a rule list"))
			.help("Points at a WebKit content-blocking rule list somebody else maintains, for hiding cookie banners and ads. Nifro keeps no rules of its own, because blocklists go stale within weeks and keeping one working is a full-time job.")
	}
}

private struct PlaylistIntervalSetting: View {
	@Default(.playlistInterval) private var interval

	private static let defaultInterval = 60.0 * 30

	var body: some View {
		Toggle("Rotate between websites every", isOn: $interval.isNotNil(trueSetValue: Self.defaultInterval))
			.help("Moves to the next website on each display in turn. Websites with hours set are skipped outside them.")

		if interval != nil {
			Stepper(
				"\(Int((interval ?? Self.defaultInterval) / 60)) minutes",
				value: $interval.withDefaultValue(Self.defaultInterval).secondsToMinutes,
				in: 1...(60 * 24),
				step: 1
			)
		}
	}
}

private struct DimWhenUnfocusedSetting: View {
	@Default(.dimWhenUnfocused) private var isEnabled
	@Default(.dimmedOpacityFactor) private var factor

	var body: some View {
		Defaults.Toggle(String(localized: "Dim while another app is in front"), key: .dimWhenUnfocused)
			.help("Fades the wallpaper back while you work elsewhere, and brings it up again when you click the desktop. A page bright enough to enjoy when you look at it is often too loud behind a document you are reading.")

		if isEnabled {
			Slider(
				value: $factor,
				in: 0.1...0.9,
				step: 0.1
			) {
				Text("Dimmed to")
			}
		}
	}
}

private struct ShowOnAllSpacesSetting: View {
	var body: some View {
		Defaults.Toggle(
			String(localized: "Show on every Space"),
			key: .showOnAllSpaces
		)
		.help("Spaces are the desktops you switch between in Mission Control, not your displays. Off means the wallpaper stays on whichever Space was in front when Nifro started. Which display a website goes on is set on the website itself, not here.")
	}
}

private struct BringBrowsingModeToFrontSetting: View {
	var body: some View {
		// TODO: Find a better title for this.
		Defaults.Toggle(
			String(localized: "Bring browsing mode to the front"),
			key: .bringBrowsingModeToFront
		)
		.help("Keep the website above all other windows while browsing mode is active.")
	}
}

private struct OpenExternalLinksInBrowserSetting: View {
	var body: some View {
		Defaults.Toggle(
			String(localized: "Open external links in default browser"),
			key: .openExternalLinksInBrowser
		)
		.help("If a website requires login, you should disable this setting while logging in as the website might require you to navigate to a different page, and you don't want that to open in a browser instead of Nifro.")
	}
}

private struct OpacitySetting: View {
	@Default(.opacity) private var opacity

	var body: some View {
		Slider(
			value: $opacity,
			in: 0.1...1,
			step: 0.1
		) {
			Text("Opacity")
		}
		.help("Browsing mode always uses full opacity.")
	}
}

private struct ReloadIntervalSetting: View {
	private static let defaultReloadInterval = 60.0
	private static let minimumReloadInterval = 0.1

	@Default(.reloadInterval) private var reloadInterval
	@FocusState private var isTextFieldFocused: Bool

	// TODO: Improve VoiceOver accessibility for this control.
	var body: some View {
		LabeledContent("Reload every") {
			HStack {
				TextField(
					"",
					value: reloadIntervalInMinutes,
					format: .number.grouping(.never).precision(.fractionLength(1))
				)
				.labelsHidden()
				.focused($isTextFieldFocused)
				.frame(width: 40)
				.disabled(reloadInterval == nil)
				Stepper(
					"",
					value: reloadIntervalInMinutes.didSet { _ in
						// We have to unfocus the text field because sometimes it's in a state where it does not update the value. Some kind of bug with the formatter. (macOS 12.4)
						isTextFieldFocused = false
					},
					in: Self.minimumReloadInterval...(.greatestFiniteMagnitude),
					step: 1
				)
				.labelsHidden()
				.disabled(reloadInterval == nil)
				Text("minutes")
					.textSelection(.disabled)
			}
			.contentShape(.rect)
			Toggle("Reload every", isOn: $reloadInterval.isNotNil(trueSetValue: Self.defaultReloadInterval))
				.labelsHidden()
				.controlSize(.mini)
				.toggleStyle(.switch)
		}
		.accessibilityLabel("Reload interval in minutes")
		.contentShape(.rect)
	}

	private var reloadIntervalInMinutes: Binding<Double> {
		$reloadInterval.withDefaultValue(Self.defaultReloadInterval).secondsToMinutes
	}

	// TODO: We don't use this binding as it causes the toggle to not always work because of some weirdities with the formatter. (macOS 12.4)
//	private var hasInterval: Binding<Bool> {
//		$reloadInterval.isNotNil(trueSetValue: Self.defaultReloadInterval)
//	}
}

private struct HideMenuBarIconSetting: View {
	@State private var isShowingAlert = false

	var body: some View {
		Defaults.Toggle(String(localized: "Hide menu bar icon"), key: .hideMenuBarIcon)
			.onChange {
				isShowingAlert = $0
			}
			.alert2(
				String(localized: "If you need to access the Nifro menu, launch the app again to reveal the menu bar icon for 5 seconds."),
				isPresented: $isShowingAlert
			)
	}
}

private struct DisplaySetting: View {
	@ObservedObject private var displayWrapper = Display.observable
	@Default(.display) private var chosenDisplay

	var body: some View {
		Picker(
			selection: $chosenDisplay.getMap(\.?.withFallbackToMain)
		) {
			ForEach(displayWrapper.wrappedValue.all) { display in
				Text(display.localizedName)
					.tag(display)
					// A view cannot have multiple tags, otherwise, this would have been the best solution.
//					.if(display == .main) {
//						$0.tag(nil as Display?)
//					}
			}
		} label: {
			Text("Show on")
			Link("Multi-display support ›", destination: "https://github.com/PathGao/nifro/issues/2")
		}
		.task(id: chosenDisplay) {
			guard chosenDisplay == nil else {
				return
			}

			chosenDisplay = .main
		}
	}
}

private struct ClearWebsiteDataSetting: View {
	@State private var hasCleared = false

	var body: some View {
		// Not marked as destructive as it should mostly be used when it's together with other buttons.
		Button("Clear all website data") {
			Task {
				hasCleared = true
				WebsitesController.shared.thumbnailCache.removeAllImages()
				await WKWebsiteDataStore.clearAllWebsiteData()
			}
		}
		.help("Clears all cookies, local storage, caches, etc.")
		.disabled(hasCleared)
	}
}

#Preview {
	SettingsScreen()
}

fileprivate enum SettingsTabType {
	case general
	case advanced
	case shortcuts
	case about

	fileprivate var label: some View {
		switch self {
		case .general:
			Label("General", systemImage: "gearshape")
		case .advanced:
			Label("Advanced", systemImage: "gearshape.2")
		case .shortcuts:
			Label("Shortcuts", systemImage: "command")
		case .about:
			Label("About", systemImage: "info.circle")
		}
	}
}

extension View {
	/**
	Make the view a settings tab of the given type.
	*/
	fileprivate func settingsTabItem(_ type: SettingsTabType) -> some View {
		tabItem { type.label }
	}
}
