import SwiftUI

/**
The explanation for one setting, behind a help button next to its name.

Not a tooltip. A tooltip appears only if you hover over the right thing and then wait, so a setting
whose explanation lives in one is a setting most people never read the explanation of. Every setting
in the website dialog needs one — none of them is guessable from three words, and several of them
have a cost that is invisible until you have paid it, like a page that has to keep rendering because
it was made clickable.

The round `?` is what macOS uses for this. The tooltip is kept as well, so hovering still works for
anyone who expects that.
*/
struct SettingHelp: View {
	let text: String

	var body: some View {
		InfoPopoverButton {
			Text(text)
				.frame(maxWidth: 320, alignment: .leading)
		}
		.controlSize(.small)
		.help(text)
	}
}

extension View {
	/**
	Put a help button after this label.
	*/
	func explained(_ text: String) -> some View {
		HStack(spacing: 4) {
			self
			SettingHelp(text: text)
		}
	}
}
