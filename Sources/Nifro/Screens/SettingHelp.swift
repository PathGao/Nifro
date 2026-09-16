import SwiftUI

/**
The explanation for one setting, behind a help button next to its name.

Not a tooltip. A tooltip appears only if you hover over the right thing and then wait, so a setting
whose explanation lives in one is a setting most people never read the explanation of. Every setting
in the website dialog needs one — none of them is guessable from three words, and several of them
have a cost that is invisible until you have paid it, like a page that has to keep rendering because
it was made clickable.

An `info.circle` rather than the round `?`. The `?` bezel is AppKit's help button, which in Apple's
own apps opens the Help book — so a row of them promises documentation that does not exist here. The
ⓘ is what a modern settings pane uses for "there is more to say about this one", and it is what
people reach for. The tooltip is kept as well, so hovering still works for anyone who expects that.
*/
struct SettingHelp: View {
	let text: String

	@State private var isPresented = false

	var body: some View {
		Button {
			isPresented = true
		} label: {
			Image(systemName: "info.circle")
				.foregroundStyle(.secondary)
		}
		.buttonStyle(.plain)
		.help(text)
		.popover(isPresented: $isPresented) {
			Text(text)
				.frame(width: 300, alignment: .leading)
				.multilineText()
				.padding()
		}
		.accessibilityLabel("More information")
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
