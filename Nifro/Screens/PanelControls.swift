import SwiftUI

/**
The panel's own controls.

These were all drawn by hand: a `.plain` `Button` with its own fill, its own hover wash, its own press
dip, its own corner radius and the app icon's orange for the lit state. The argument was that a
wallpaper control acts on something the user is not looking at — the page is behind their windows — so
the button has to be the whole of the feedback.

That is still true, and stock styles already do all of it. They dip when pressed, they stay lit while
what they turn on is on, and they light in the accent colour the user picked for their Mac. They also
bring focus rings, Full Keyboard Access, Increase Contrast, Reduce Transparency and the right
VoiceOver traits, none of which the drawn ones had. So the buttons and the interval field are stock
now, and the metrics that described their size, radius, font and colour are gone with the drawing.

What is given up is the orange, which said *this is running* where the accent says *this is
selected*. The panel says it the way the rest of macOS says it now, and which control is lit still
carries the fact.

SF Symbols throughout: they carry the meanings already, they follow the user's own text size, and they
are the vocabulary the rest of the system uses for exactly these verbs.
*/
enum PanelMetrics {
	/**
	The gap between two stock controls in a row.

	The rows used to set 10 by hand, around buttons that drew themselves edge to edge. The stock styles
	bring their own padding, so the gap that reads right between them is smaller. It is the only thing
	left here that is about a control rather than about the column: their size, radius, font and
	colours are the system's answers now, and a name for a value the app no longer chooses is a name
	that can drift out of step with what is drawn.
	*/
	static let controlSpacing = 4.0

	/**
	The column: its width, the card behind it, and the picture inside it.

	Three radii rather than one. The card is the hover target and wants to read as a card; the picture
	is a screenshot and takes the radius a screenshot takes; they are nested, not siblings, so making
	them agree would make the inner one look wrong against the outer.
	*/
	static let columnWidth = 260.0
	static let cardRadius = 12.0
	static let pictureRadius = 8.0

	/**
	How wide the playlist chooser may get, and how wide Quit is asked to match.

	A ceiling rather than a width. A stock pull-down sizes itself to its label, which is what these two
	do now, so a short name gets a short control and only a long one is stopped here — and stopping it
	is what keeps the widest title inside the column instead of pushing the column out. Three quarters
	of the picture above it, derived rather than written as 195, because it was prose before and prose
	does not change when the column does.
	*/
	static let chooserWidth = columnWidth * 0.75

	/**
	The website chooser's ceiling, higher than the playlist chooser's above it.

	It is the name that wants the room: a playlist is something the user named and kept short, and a
	website's title is whatever the page calls itself. Halfway between that control and the picture over
	both of them, so the widest a title can get still reads as narrower than the picture.
	*/
	static let websiteChooserWidth = columnWidth * 0.875
}

/**
One symbol, in the stock bordered style at the large control size.

Large, like everything else in the panel. The whole panel was a size smaller than the settings windows
and read as harder to hit; one size for the panel means a row of icon buttons, a text field and a
pull-down all stand the same height, which is what a row of controls does in a system window.

Bordered rather than `accessoryBar`, which is the quieter style a popover would otherwise reach for.
Two reasons, both measured against a rendering of each rather than argued: an accessory bar draws no
bezel until the pointer is over it, and what is behind this panel is a web page the user chose, so a
control that is invisible at rest is invisible over whatever that page happens to be showing. And its
lit state is a grey wash unless `tint` is set by hand, where `bordered` fills with the user's accent
colour on its own — which is the whole of what "lit" has to say here.
*/
struct PanelButton: View {
	let symbol: String
	let label: String

	/**
	Whether this control is lit, or `nil` for one that has no lit state at all.

	The third state is the point, and it is not cosmetic: a control with a lit state is a `Toggle`, so
	VoiceOver reads it as a switch and says which way it is set, and one without is a `Button`,
	announced as an action. Defaulting to `false` instead is what would have had the app claim its five
	footer icons could be switched off.
	*/
	// swiftlint:disable:next discouraged_optional_boolean
	var isOn: Bool?

	var isEnabled = true
	let action: () -> Void

	var body: some View {
		Group {
			if let isOn {
				Toggle(isOn: .init(get: { isOn }, set: { _ in action() })) {
					icon
				}
				.toggleStyle(.button)
			} else {
				Button(action: action) {
					icon
				}
			}
		}
		.buttonStyle(.bordered)
		.controlSize(.large)
		.disabled(!isEnabled)
		.help(label)
		.accessibilityLabel(label)
	}

	/**
	A fixed slot for the symbol, so a row of these keeps its spacing whatever glyphs are in it.

	The symbol's box, not the button's: the style puts its own padding around it.
	*/
	private var icon: some View {
		Image(systemName: symbol)
			.frame(width: 18, height: 16)
	}
}

/**
How many minutes this display waits between websites: a number to type in, and the unit beside it.

A typed field rather than the stepper Settings used to carry. The stepper was next to a checkbox that
was only ever set once, so walking a number up one minute at a time was tolerable; here it sits beside
the mode button in a popover, and somebody who wants ninety minutes wants to type "90" rather than
press an arrow ninety times.

Minutes and only minutes, so no unit picker — unlike `IntervalField`, which reloads pages and has to
reach from seconds to a day. Rotation below a minute is not offered, and above a day is not a
rotation, so the two ends the picker exists to reach are both outside the range.

`roundedBorder` at the same control size as the buttons beside it. A plain field with a drawn box
behind it was the app answering a question `NSTextField` already answers, and answering it without a
focus ring.
*/
struct PanelIntervalField: View {
	@Binding var minutes: Double

	var body: some View {
		HStack(spacing: PanelMetrics.controlSpacing) {
			TextField(
				"",
				value: $minutes,
				format: .number.grouping(.never).precision(.fractionLength(0))
			)
				.textFieldStyle(.roundedBorder)
				.multilineTextAlignment(.center)
				.frame(width: 52)
				.help(String(localized: "Minutes between websites"))
				.accessibilityLabel(String(localized: "Minutes between websites"))

			Text("min")
				.foregroundStyle(.secondary)
		}
		.controlSize(.large)
	}
}

/**
A button whose label is a word rather than a symbol, for the verbs no symbol says plainly.

Bordered at the large size, like everything else in the panel, so the pair under the picture stands as
tall as the choosers above them. The one with a lit state is a `Toggle`, for the reason
`PanelButton.isOn` gives.
*/
struct PanelWideButton: View {
	let title: String

	/**
	An optional symbol before the words, for the one button that cannot be undone.
	*/
	var symbol: String?

	// swiftlint:disable:next discouraged_optional_boolean
	var isOn: Bool?

	var isEnabled = true
	let action: () -> Void

	var body: some View {
		Group {
			if let isOn {
				Toggle(isOn: .init(get: { isOn }, set: { _ in action() })) {
					label
				}
				.toggleStyle(.button)
			} else {
				Button(action: action) {
					label
				}
			}
		}
		.buttonStyle(.bordered)
		.controlSize(.large)
		.disabled(!isEnabled)
	}

	private var label: some View {
		HStack(spacing: 5) {
			if let symbol {
				Image(systemName: symbol)
			}

			Text(title)
				.lineLimit(1)
		}
			// Centred when the button is given a width, and hugging when it is not.
			.frame(maxWidth: .infinity)
			.fixedSize(horizontal: false, vertical: true)
	}
}

extension RotationMode {
	/**
	The symbol for this mode.

	Each one is the symbol the system already uses for the idea, so nobody has to learn ours: the
	repeat arrows, the shuffle arrows, and a pin.
	*/
	var symbol: String {
		switch self {
		case .pinned:
			"pin.fill"
		case .loop:
			"repeat"
		case .random:
			"shuffle"
		}
	}

	var label: String {
		switch self {
		case .pinned:
			String(localized: "Staying on this website")
		case .loop:
			String(localized: "Rotating in order")
		case .random:
			String(localized: "Rotating at random")
		}
	}
}

/**
Text that slides when it does not fit, and sits still when it does.

A website's name is whatever the site put in its `<title>`, so the column has to hold anything from
"Windy" to a sentence. Truncating loses the end, which for a video is the part that says which video;
sliding shows all of it without making the column wider than its neighbours.

It only slides while the column is under the pointer. A panel with two names sliding at once, forever,
is a panel nobody can read the rest of — and the whole reason to look at a column is that you are
already pointing at it.
*/
struct MarqueeText: View {
	let text: String
	let isActive: Bool

	@State private var overflow = 0.0
	@State private var isSlid = false

	var body: some View {
		GeometryReader { outer in
			Text(text)
				.fixedSize()
				.background {
					GeometryReader { inner in
						Color.clear.onAppear {
							overflow = max(0, inner.size.width - outer.size.width)
						}
					}
				}
				.offset(x: isSlid ? -overflow : 0)
				// Centred while it fits, and left-aligned once it does not — a name that has to slide has
				// to start at its beginning, and centring one that overflows would cut both ends at once.
				.frame(width: outer.size.width, alignment: overflow > 0 ? .leading : .center)
				.clipped()
		}
		.onChange(of: isActive) {
			guard isActive, overflow > 0 else {
				// Back to the start rather than wherever it had got to, so the next look begins at the
				// beginning of the name.
				withAnimation(.easeOut(duration: 0.2)) {
					isSlid = false
				}

				return
			}

			// Paced by how far it has to go, so a name twice as long takes twice as long rather than
			// twice the speed. `autoreverses` walks it back instead of snapping.
			withAnimation(.linear(duration: overflow / 30).delay(0.4).repeatForever(autoreverses: true)) {
				isSlid = true
			}
		}
	}
}
