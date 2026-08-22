import SwiftUI

/**
The About tab.

Everything here used to live in a "More" submenu hanging off the status item. Three items is not enough to justify a submenu — it made people click twice to reach things they were already looking for, and left the status menu with a dead end in the middle of it. A settings tab is where a Mac app without a menu bar of its own puts this.
*/
struct AboutSettings: View {
	var body: some View {
		Form {
			Section {
				HStack(spacing: 12) {
					// Not `SSApp.icon`: that force-unwraps, and the icon slot is deliberately empty until this fork has artwork of its own.
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
				}
				.padding(.vertical, 4)
			}

			Section {
				Button("Report a Problem or Request a Feature…") {
					SSApp.openSendFeedbackPage()
				}
				Button("Site Gallery…") {
					Constants.openSiteGalleryWindow()
				}
				Link("GitHub Repository", destination: Constants.repositoryURL)
			} footer: {
				Text("The site gallery is a list of pages that work well as wallpapers, each with the settings that make it work. Adding one is a single file — no Swift, no Xcode.")
					.foregroundStyle(.secondary)
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
