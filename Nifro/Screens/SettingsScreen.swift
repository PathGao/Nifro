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
				LanguageSetting()
			}
			Section {
				UpdateSetting()
			}
			Section {
				ReloadIntervalSetting()
				OpacitySetting()
			}
			Section {
				KeepWallpaperWhenDisplayUnpluggedSetting()
			}
		}
	}
}

/**
Checking for a new version, and being able to stop it.

An app that reaches the network on its own has to be an app that can be told not to, so the automatic
check is a switch. The button beside it is what the switch leaves missing: somebody who turned the
daily check off, or who has just heard a release is out, needs a way to ask now.

It says what it found. A check whose only outcome is silence cannot be told apart from one that
failed — the same reason the clear-data button reports how much it freed.
*/
private struct UpdateSetting: View {
	private enum Progress: Equatable {
		case ready
		case checking
		case upToDate
		case available(version: String)
		case failed
	}

	@State private var progress = Progress.ready

	var body: some View {
		Defaults.Toggle(key: .checksForUpdatesAutomatically) {
			Text("Check for updates automatically")
				.explained(String(localized: "Once a day. Nifro mentions a newer version in the menu and nowhere else — it does not interrupt, and it never installs anything."))
		}

		LabeledContent {
			HStack(spacing: 8) {
				switch progress {
				case .ready:
					EmptyView()
				case .checking:
					ProgressView()
						.controlSize(.small)
				case .upToDate:
					Text("Up to date")
						.foregroundStyle(.secondary)
				case .available(let version):
					Button(String(localized: "Get \(version)…")) {
						Constants.latestReleaseURL.open()
					}
				case .failed:
					Text("Could not check")
						.foregroundStyle(.secondary)
				}

				Button("Check Now") {
					check()
				}
				.disabled(progress == .checking)
			}
		} label: {
			Text("Version \(SSApp.version)")
		}
	}

	private func check() {
		progress = .checking

		Task {
			switch await AppState.shared.refreshLatestKnownVersion() {
			case .unreachable:
				progress = .failed
			case .upToDate:
				progress = .upToDate
			case .newer(let version):
				progress = .available(version: version)
			}
		}
	}
}

/**
The language the interface is drawn in, as a plain picker — which is where every app that offers this
puts it.

macOS has a per-app language of its own, three levels into System Settings. It works, and the
complaint recorded against it was that nobody finds it; sending people there answers a
discoverability problem with a longer walk.

It asks before relaunching rather than restarting under the user.
*/
private struct LanguageSetting: View {
	@State private var language = Localization.pending
	@State private var isConfirmingRelaunch = false

	var body: some View {
		Picker(selection: $language) {
			Text("Follow the system").tag(nil as AppLanguage?)
			Divider()
			ForEach(AppLanguage.allCases) {
				Text($0.displayName).tag($0 as AppLanguage?)
			}
		} label: {
			Text("Language")
				.explained(String(localized: "Nifro follows your Mac's language unless you pick one here. A language that is only half translated falls back to English rather than showing anything raw."))
		}
		.onChange(of: language) { previous, new in
			guard previous != new else {
				return
			}

			Localization.request(new)
			isConfirmingRelaunch = true
		}
		.confirmationDialog(
			String(localized: "Reopen Nifro to change the language?"),
			isPresented: $isConfirmingRelaunch
		) {
			Button(String(localized: "Reopen Now")) {
				Localization.relaunch()
			}

			Button(String(localized: "Later"), role: .cancel) {}
		} message: {
			Text("The wallpaper comes back up on its own.")
		}
	}
}

private struct ShortcutsSettings: View {
	var body: some View {
		Form {
			Section {
				ForEach(Shortcut.allCases, id: \.self) {
					KeyboardShortcuts.Recorder($0.title, name: $0.name)
				}
			} footer: {
				// Worth saying once, here, because it is invisible on one display and surprising on two:
				// a shortcut is pressed by somebody looking at a screen, and this is how it knows which.
				Text("These act on the display your pointer is on. Automations and nifro:// commands act on the main display, since they can run with nobody at the Mac.")
					.font(.callout)
					.foregroundStyle(.secondary)
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

private struct KeepWallpaperWhenDisplayUnpluggedSetting: View {
	var body: some View {
		Defaults.Toggle(key: .keepWallpaperWhenDisplayUnplugged) {
			Text("Keep a wallpaper when its display is unplugged")
				.explained(String(localized: "For a website pinned to a particular display. On, it moves to the main display until that one is plugged back in — which is what Nifro has always done, and what macOS does with an ordinary window. Off, it goes away with its display, the way the desktop picture on that screen does. Either way the website keeps the display you chose for it."))
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

/**
Clearing takes a moment and used to say nothing about it.

The button disabled itself the instant it was pressed and stayed that way, with no sign of work
happening, no sign of it finishing, and no way to tell whether anything had gone. It is a button whose
whole purpose is an effect you cannot see, so it has to report one: it says how much it freed, which
is the only answer to "did that do anything" that does not require taking the app's word for it.
*/
private struct ClearWebsiteDataSetting: View {
	private enum Progress: Equatable {
		case ready
		case clearing
		case cleared(bytes: Int64)
	}

	@State private var progress = Progress.ready

	var body: some View {
		HStack(spacing: 8) {
			// Not marked as destructive as it should mostly be used when it's together with other buttons.
			Button("Clear all website data") {
				clear()
			}
			.disabled(progress == .clearing)

			switch progress {
			case .ready:
				EmptyView()
			case .clearing:
				ProgressView()
					.controlSize(.small)
			case .cleared(let bytes):
				// Zero is a real answer and a common one — pressing it twice frees nothing the second
				// time — so it says "nothing left to clear" rather than "0 bytes freed", which reads
				// like a failure.
				Text(bytes > 0 ? String(localized: "Freed \(bytes.formatted(.byteCount(style: .file)))") : String(localized: "Nothing left to clear"))
					.foregroundStyle(.secondary)
			}
		}
		.help("Clears cookies, local storage, caches, page thumbnails, and what each page had remembered: where it was scrolled or moved to, and how far it was zoomed in. Your websites and their settings are kept.")
	}

	private func clear() {
		progress = .clearing

		Task {
			let before = await DiskBudget.storedBytes(of: [.homeDirectory])

			WebsitesController.shared.thumbnailCache.removeAllImages()
			AppState.shared.forgetWherePagesWere()
			await WKWebsiteDataStore.clearAllWebsiteData()

			let after = await DiskBudget.storedBytes(of: [.homeDirectory])
			progress = .cleared(bytes: max(0, before - after))
		}
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
