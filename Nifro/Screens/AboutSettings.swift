import SwiftUI

/**
The bottom of the General pane: what this app is and where to take a problem with it.

It was a tab of its own, which put four rows and a licence notice on a page 400pt wide and left the
rest of it empty. Sections rather than a `Form`, so General owns the one form and this drops into the
end of it.

The version is not repeated here. It is one row up, beside the button that checks for a newer one,
which is the only place anybody reads a version number for a reason.
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

					Text(SSApp.name)
						.font(.title2)
						.fontWeight(.semibold)

					Spacer()

					// The gallery answers "what do I even put up there", which is the question somebody
					// has the minute the app is installed. Third in a stack of three plain rows it read
					// as documentation. Beside the icon and filled, it is the one thing on the page that
					// looks like it wants pressing — and nothing competes with it, because the two rows
					// below are both places you only go when something is wrong.
					Button("Site Gallery…") {
						Constants.openSiteGalleryWindow()
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
				}
				.padding(.vertical, 4)
			} footer: {
				Text("A list of pages that work well as wallpapers, each with the settings that make it work; adding one takes a single file.")
					.foregroundStyle(.secondary)
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
				Text("Paused, it costs next to nothing beyond a little memory.")
					.font(.callout)
					.foregroundStyle(.secondary)
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
