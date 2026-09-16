import SwiftUI

/**
The bottom of the General pane: what this app is, what it costs to leave running, and where to take a
problem with it.

It was a tab of its own, which put four rows and a licence notice on a page 400pt wide and left the
rest of it empty. Sections rather than a `Form`, so General owns the one form and this drops into the
end of it.

The version lives here, under the app's name, with the button that asks for a newer one beside it.
Those three answer one question between them — what am I running, and is there anything newer — and
they used to be a row in the update section with the automatic-check switch, which is a different
question: whether the app is allowed to ask at all. That switch stayed there.
*/
struct AboutSection: View {
	var body: some View {
		Group {
			Section {
				HStack(spacing: 12) {
					// Not `SSApp.icon`. That force-unwraps, and the icon slot stays empty until this fork has artwork of its own.
					if let icon = NSApp.applicationIconImage {
						Image(nsImage: icon)
							.resizable()
							.frame(width: 56, height: 56)
					}

					VStack(alignment: .leading, spacing: 2) {
						// One `Text` rather than two in an `HStack`, so the author sits on the name's own
						// baseline and wraps with it rather than being a second column that has to be kept
						// from colliding with the button on the right.
						Text(SSApp.name)
							.font(.title2)
							.fontWeight(.semibold)
							+ Text(verbatim: " ")
							+ Text("by PathGao")
							.font(.callout)
							.foregroundStyle(.secondary)

						Text("Version \(SSApp.versionWithBuild)")
							.font(.callout)
							.foregroundStyle(.secondary)
							.textSelection(.enabled)
					}

					Spacer()

					UpdateCheckButton()
				}
				.padding(.vertical, 4)
			}

			// Measured, not asserted, because a performance sentence in an About pane is the kind that is
			// written once and never checked again. Paused — every scene suspended, whether by the app
			// switch or by every display being switched off, both of which reach the same `suspend()` —
			// there are no timers, no pending load and no web view: two displays off with eight websites
			// configured, sampled over 90 and 120 second intervals from CPU-time deltas, came to 0.03% of
			// one core, which is the six-hour disk sweep and the daily update check rather than a page.
			// "beyond a little memory" is the part that must not be dropped: roughly 180 MB stays
			// resident because the process and WebKit's three helpers are still alive and the emptied
			// WebContent processes are not reaped, and two further minutes of idling did not move it.
			Section {
				Text("When paused, Nifro stops active work but still uses some memory.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}

			// The gallery answers "what do I even put up there", which is the question somebody has the
			// minute the app is installed. It is the one thing on the page that looks like it wants
			// pressing, and nothing competes with it, because the two rows below are both places you only
			// go when something is wrong. The sentence is beside the button rather than a section footer
			// under it, so what the button opens is read at the moment the button is looked at.
			Section {
				HStack(spacing: 12) {
					Button("Site Gallery…") {
						Constants.openSiteGalleryWindow()
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
					.fixedSize()

					Text("Wallpaper-ready pages with their recommended settings.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}

			Section {
				HStack {
					Button("Report a Problem or Request a Feature…") {
						SSApp.openSendFeedbackPage()
					}

					Spacer()

					// "GitHub", not "GitHub Repository". The settings window is a fixed 400pt, which
					// leaves 340pt across a row; the English button wants 270 of that, and the longer
					// label overruns what is left and truncates the button rather than itself. The
					// Chinese label has room for either, so the shorter source string is the one that
					// works in both.
					Link("GitHub", destination: Constants.repositoryURL)
				}
			}

			Section {
				Text("Nifro is open source under the MIT licence.")
				Text("Inspired by [Plash](https://github.com/sindresorhus/Plash) by Sindre Sorhus.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}
}

/**
Ask for the latest version now, and say what came back.

It says what it found. A check whose only outcome is silence cannot be told apart from one that
failed — the same reason the clear-data button reports how much it freed. The answer sits above the
button rather than beside it: this row already carries the icon, the name and the version, and
The update-check failure text next to "Check Now" is what pushes it past the 400pt window.
*/
private struct UpdateCheckButton: View {
	private enum Progress: Equatable {
		case ready
		case checking
		case upToDate
		case available(version: String)
		case failed
	}

	@State private var progress = Progress.ready

	var body: some View {
		VStack(alignment: .trailing, spacing: 4) {
			switch progress {
			case .ready:
				EmptyView()
			case .checking:
				ProgressView()
					.controlSize(.small)
			case .upToDate:
				Text("Up to date")
					.font(.callout)
					.foregroundStyle(.secondary)
			case .available(let version):
				Button(String(localized: "Get \(version)…")) {
					Constants.latestReleaseURL.open()
				}
			case .failed:
			Text("Couldn't check for updates")
					.font(.callout)
					.foregroundStyle(.secondary)
			}

			Button("Check Now") {
				check()
			}
			.disabled(progress == .checking)
		}
		.fixedSize()
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
