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
				// The label has to be ours. `LaunchAtLogin.Toggle()` with no label supplies its own, out
				// of the package's bundle, so it stayed English in a Chinese settings window — and no
				// check would have caught it, since the string was never in our catalogue to be missing
				// a translation.
				LaunchAtLogin.Toggle {
					Text("Launch at login")
						.explained(String(localized: "Starts Nifro when you log in, so the wallpaper is already up when you reach the desktop."))
				}
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
			ForEach(Shortcut.allCases, id: \.self) {
				KeyboardShortcuts.Recorder($0.title, name: $0.name)
			}
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
				PlaylistIntervalSetting()
				Defaults.Toggle(key: .restoreScrollPosition) {
					Text("Put the page back where it was")
						.explained(String(localized: "A page that reloads on a timer starts over: a long page goes back to the top, and a map or a drawing goes back to wherever it opens. This puts it back — the scroll position after a reload, and the part of the page a site names after the “#” in its address, which also survives quitting. A site that saves its own position needs none of this and keeps working either way."))
				}
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

private struct ContentRulesSetting: View {
	@Default(.contentRulesURL) private var url

	var body: some View {
		LabeledContent {
			TextField("", text: $url.withDefaultValue(""), prompt: Text("URL to a rule list"))
				.labelsHidden()
		} label: {
			Text("Content blocking rules")
				.explained(String(localized: """
					A WebKit content-blocking rule list, for hiding cookie banners and ads. Paste the address of a \
					`.json` file and Nifro compiles it once and applies it to every website.

					Nifro keeps no rules of its own: a blocklist goes stale within weeks, and keeping one working \
					is a full-time job somebody else is already doing. Lists in WebKit's format are published by \
					the content-blocker projects — the one your Safari extension uses can usually be exported, \
					and several are on GitHub as a single raw `.json` file. The address has to be the raw file, \
					not the page it is displayed on.

					Leave it empty for no rules at all.
					"""))
		}
	}
}

private struct PlaylistIntervalSetting: View {
	@Default(.playlistInterval) private var interval

	private static let defaultInterval = 60.0 * 30

	var body: some View {
		Toggle(isOn: $interval.isNotNil(trueSetValue: Self.defaultInterval)) {
			Text("Rotate between websites every")
				.explained(String(localized: "Moves to the next website on each display in turn. Websites with hours set are skipped outside them."))
		}

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
		Defaults.Toggle(key: .dimWhenUnfocused) {
			Text("Dim while another app is in front")
				.explained(String(localized: "Fades the wallpaper back while you work elsewhere, and brings it up again when you click the desktop. A page bright enough to enjoy when you look at it is often too loud behind a document you are reading."))
		}

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
		Defaults.Toggle(key: .showOnAllSpaces) {
			Text("Show on every Space")
				.explained(String(localized: "Spaces are the desktops you switch between in Mission Control, not your displays. Off means the wallpaper stays on whichever Space was in front when Nifro started. Which display a website goes on is set on the website itself, not here."))
  }
	}
}

private struct BringBrowsingModeToFrontSetting: View {
	var body: some View {
		// TODO: Find a better title for this.
		Defaults.Toggle(key: .bringBrowsingModeToFront) {
			Text("Bring browsing mode to the front")
				.explained(String(localized: "Keep the website above all other windows while browsing mode is active."))
  }
	}
}

private struct OpenExternalLinksInBrowserSetting: View {
	var body: some View {
		Defaults.Toggle(key: .openExternalLinksInBrowser) {
			Text("Open external links in default browser")
				.explained(String(localized: "If a website requires login, you should disable this setting while logging in as the website might require you to navigate to a different page, and you don't want that to open in a browser instead of Nifro."))
  }
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
				.explained(String(localized: "How far back the wallpaper sits. Browsing Mode always uses full opacity, whatever this says, because a page you are about to click should not be half transparent."))
		}
	}
}

private struct ReloadIntervalSetting: View {
	private static let defaultReloadInterval = 60.0 * 60

	@Default(.reloadInterval) private var reloadInterval

	// TODO: Improve VoiceOver accessibility for this control.
	var body: some View {
		LabeledContent {
			if reloadInterval != nil {
				IntervalField(seconds: $reloadInterval.withDefaultValue(Self.defaultReloadInterval))
			}

			Toggle("Reload every", isOn: $reloadInterval.isNotNil(trueSetValue: Self.defaultReloadInterval))
				.labelsHidden()
				.controlSize(.mini)
				.toggleStyle(.switch)
		} label: {
			Text("Reload every")
				.explained(String(localized: "For websites that do not set their own. A website with its own schedule — set in its settings — ignores this."))
		}
		.accessibilityLabel("Reload interval")
		.contentShape(.rect)
	}
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
			Link("Multi-display support ›", destination: "https://github.com/PathGao/Nifro/issues/2")
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
				AppState.shared.forgetWherePagesWere()
				await WKWebsiteDataStore.clearAllWebsiteData()
			}
		}
		.help("Clears cookies, local storage, caches, page thumbnails, and where each page had been scrolled or moved to. Your websites and their settings are kept.")
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
