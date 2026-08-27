import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

struct SettingsScreen: View {
	var body: some View {
		TabView {
			GeneralSettings()
				.settingsTabItem(.general)
			BehaviorSettings()
				.settingsTabItem(.behavior)
			ShortcutsSettings()
				.settingsTabItem(.shortcuts)
			AdvancedSettings()
				.settingsTabItem(.advanced)
		}
		.formStyle(.grouped)
		.frame(width: 400)
		.fixedSize()
		.windowLevel(.floating + 1) // To ensure it's always above the Nifro browser window.
	}
}

/**
What Nifro is, rather than what it does.

The app's own affairs — how it starts, what language it speaks, which version it is, and who wrote
it. Everything that changes what appears on the desktop is one tab over in Behavior, so nothing here
needs a wallpaper on screen to make sense of.

About used to be a fourth tab. Three rows and a licence do not fill a pane, and a tab nobody opens
twice is a worse home for the version number than the pane that already asks whether to check for a
new one.
*/
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
				HideMenuBarIconSetting()
			}
			Section {
				LanguageSetting()
			}
			Section {
				UpdateSetting()
			}

			AboutSection()
		}
	}
}

/**
Everything that decides what the desktop shows and how it behaves while it is up.

Split out of General and Advanced, which between them had grown into one long list with no order to
it: a language picker, a reload interval and a content-blocking rule list are three different kinds
of question. Advanced keeps the two that are genuinely advanced; this is the rest.
*/
private struct BehaviorSettings: View {
	var body: some View {
		Form {
			Section {
				KeepWallpaperWhenDisplayUnpluggedSetting()
			}
			Section {
				OpacitySetting()
				DimWhenUnfocusedSetting()
				BringBrowsingModeToFrontSetting()
			}
			Section {
				ReloadIntervalSetting()
				Defaults.Toggle(key: .restoreScrollPosition) {
					Text("Restore the page position after a reload")
						.explained(String(localized: "A page that reloads on a timer starts over; this puts back where it was scrolled or moved to."))
				}
				Defaults.Toggle(String(localized: "Reload the page when the Mac wakes"), key: .reloadOnWake)
			}
			Section {
				OpenExternalLinksInBrowserSetting()
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
				.explained(String(localized: "Checks once a day in the background and puts a download button in the panel when there is something newer; nothing is ever downloaded or installed for you."))
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
			Text("Version \(SSApp.versionWithBuild)")
				.textSelection(.enabled)
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

**There is no "follow the system" entry, because there is no such state to draw.** Nifro starts in
English and stays in whatever was picked; `Localization` writes that down on the first launch rather
than leaving the question open, so the picker always has an answer and it is always the one the app
is actually running in. An entry handing the choice back to macOS would be a third state the rest of
the app no longer has.

It asks before relaunching rather than restarting under the user.
*/
private struct LanguageSetting: View {
	@State private var language = Localization.pending
	@State private var isConfirmingRelaunch = false

	var body: some View {
		Picker(selection: $language) {
			ForEach(AppLanguage.allCases) {
				Text($0.displayName).tag($0)
			}
		} label: {
			Text("Language")
				.explained(String(localized: "Nifro is in English until you pick a language here, and a half-translated language falls back to English rather than showing anything raw."))
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
				Text("Shortcuts act on the display the pointer is on.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}
}

/**
The two settings that can leave the app in a state its owner did not mean to reach, and the one that
undoes everything.

Content blocking takes an address off the internet and compiles it into every page; battery
deactivation makes the wallpaper disappear for a reason that is nowhere on screen. Both are worth
having and neither is worth meeting by accident, which is what an "advanced" pane is for.
*/
private struct AdvancedSettings: View {
	var body: some View {
		Form {
			Section {
				ContentRulesSetting()
				Defaults.Toggle(String(localized: "Deactivate while on battery"), key: .deactivateOnBattery)
			}
			Section {} // Padding
			Section {
				RestoreDefaultsSetting()
			}
		}
	}
}

/**
The only irreversible thing in the app, kept away from everything that adds.

Its own section under a spacer, at the very bottom of the last pane. Nothing sits next to it that
somebody could be reaching for — the workspace rule is that one slip must not turn "add" into
"delete", and a destructive control is only as safe as its nearest neighbour. Everything above it
changes a setting that can be changed back.

No ellipsis, though it does ask first and the convention says one belongs here. Read as a sentence
rather than as punctuation, "Restore All Settings…" trails off in a way that reads as hesitation from
the one control that should not sound hesitant. It says the same thing as the button in its own
dialog, which is what somebody comparing the two reads for.

What it asks is in `RestoreDefaults`, spelled out there and not repeated here: a second copy of those
four lists in this pane would be a second copy to keep in step, and the one the user actually reads
is the one in the dialog.
*/
private struct RestoreDefaultsSetting: View {
	var body: some View {
		Button("Restore All Settings", role: .destructive) {
			RestoreDefaults.confirmAndRun()
		}
	}
}

/**
An address that is fetched, compiled and applied where nobody can watch it happen, so it says what
became of it.

The one setting in the app whose effect is a thing that does *not* appear — an ad that is gone leaves
nothing behind to say the rules are working, and a page that still shows one is the same picture
whether the list is blocking and does not cover that ad, or never loaded at all. Everything went into
`ContentRules.compiled`, which no screen read, so all three ways of failing looked exactly like
success.

Same shape as `UpdateSetting` two panes over, and for the reason written there: a check whose only
outcome is silence cannot be told apart from one that failed. Secondary text beside the control, no
new setting, and nothing at all until there is something to report.

It says which failure, because the answers differ. "Could not download" is the address or the network;
"not a rule list" is the file, and is almost always the same mistake — the address of the page a list
is *displayed* on rather than of the raw file. It does not say whether last session's list is still
attached behind a failure. That is real — a failed fetch deliberately leaves the previous list in
place — but it would double the failure vocabulary to change nothing anybody would do about it, which
in both cases is to look at the address again.
*/
private struct ContentRulesSetting: View {
	@Default(.contentRulesURL) private var url
	@State private var status = ContentRules.Status.unset

	var body: some View {
		LabeledContent {
			VStack(alignment: .leading, spacing: 4) {
				TextField("", text: $url.withDefaultValue(""), prompt: Text("URL to a rule list"))
					.labelsHidden()

				Group {
					switch status {
					case .unset:
						EmptyView()
					case .loading:
						ProgressView()
							.controlSize(.small)
					case .blocking:
						Text("Blocking")
					case .unreachable:
						Text("Could not download")
					case .rejected:
						Text("Not a rule list")
					}
				}
				.foregroundStyle(.secondary)
			}
		} label: {
			Text("Content blocking rules")
				.explained(String(localized: "Paste the address of a raw WebKit content-blocking `.json` file — the content-blocker projects publish them — and Nifro applies it to every website; empty means no rules."))
		}
		// Sends its current value on subscribe, so opening Settings shows what the refresh at launch
		// made of the address rather than waiting for the next one.
		.onReceive(ContentRules.status) {
			status = $0
		}
	}
}

private struct DimWhenUnfocusedSetting: View {
	@Default(.dimWhenUnfocused) private var isEnabled
	@Default(.dimmedOpacityFactor) private var factor

	var body: some View {
		Defaults.Toggle(key: .dimWhenUnfocused) {
			Text("Dim while another app is in front")
				.explained(String(localized: "Fades the wallpaper back while you work elsewhere, and brings it up again when you click the desktop."))
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
			Text("Move to the main display when unplugged")
				.explained(String(localized: "Off, it goes away with its display and returns when you plug it back in; on, it moves to the main display and takes over there until its own returns."))
		}
	}
}

private struct BringBrowsingModeToFrontSetting: View {
	var body: some View {
		// TODO: Find a better title for this.
		Defaults.Toggle(key: .bringBrowsingModeToFront) {
			Text("Force browsing mode to the front")
				.explained(String(localized: "Keep the website above all other windows while browsing mode is active."))
  }
	}
}

private struct OpenExternalLinksInBrowserSetting: View {
	var body: some View {
		Defaults.Toggle(key: .openExternalLinksInBrowser) {
			Text("Open external links in default browser")
				.explained(String(localized: "Turn this off while logging in to a website, since the login may navigate to a page you want to stay in Nifro."))
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
			Text("Page opacity")
				.explained(String(localized: "How see-through the wallpaper is against the desktop behind it; Browsing Mode always draws it fully opaque."))
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

			Toggle("Page reload interval", isOn: $reloadInterval.isNotNil(trueSetValue: Self.defaultReloadInterval))
				.labelsHidden()
				.controlSize(.mini)
				.toggleStyle(.switch)
		} label: {
			Text("Page reload interval")
				.explained(String(localized: "For websites that do not set their own; one that does, in its own settings, ignores this."))
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
				String(localized: "Launch Nifro again to bring the menu bar icon back for 5 seconds."),
				isPresented: $isShowingAlert
			)
	}
}

#Preview {
	SettingsScreen()
}

fileprivate enum SettingsTabType {
	case general
	case behavior
	case shortcuts
	case advanced

	fileprivate var label: some View {
		switch self {
		case .general:
			Label("General", systemImage: "gearshape")
		case .behavior:
			Label("Behavior", systemImage: "slider.vertical.3")
		case .shortcuts:
			Label("Shortcuts", systemImage: "command")
		case .advanced:
			Label("Advanced", systemImage: "gearshape.2")
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
