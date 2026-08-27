import SwiftUI

/**
The About tab.

Everything here used to live in a "More" submenu hanging off the status item. Three items do not justify a submenu, and it cost two clicks to reach any of them. A settings tab is where a Mac app without a menu bar of its own puts this.
*/
struct AboutSettings: View {
	var body: some View {
		Form {
			Section {
				HStack(spacing: 12) {
					// Not `SSApp.icon`. That force-unwraps, and the icon slot stays empty until this fork has artwork of its own.
					if let icon = NSApp.applicationIconImage {
						Image(nsImage: icon)
							.resizable()
							.frame(width: 56, height: 56)
					}

					VStack(alignment: .leading, spacing: 2) {
						Text(SSApp.name)
							.font(.title2)
							.fontWeight(.semibold)
						Text("Version \(SSApp.versionWithBuild)")
							.foregroundStyle(.secondary)
							.font(.callout)
							.textSelection(.enabled)
					}

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
				Text("The site gallery is a list of pages that work well as wallpapers, each with the settings that make it work. Adding one takes a single file, no Swift and no Xcode.")
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
				Text("Derived from [Plash](https://github.com/sindresorhus/Plash) by Sindre Sorhus, from its last MIT-licensed release. Plash is still developed and still on the App Store; Nifro is a separate project and uses none of its branding or artwork.")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}
}
