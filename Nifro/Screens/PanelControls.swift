import SwiftUI

/**
The panel's own buttons.

Made rather than reached for because the stock ones do not say enough. A wallpaper control acts on
something the user is not looking at — the page is behind their windows — so the button has to be the
whole of the feedback: it dips when pressed, so a press that reached a page nobody can see still
registered somewhere, and it stays lit while the thing it turns on is on.

SF Symbols throughout: they carry the meanings already, they follow the user's own text size, and they
are the vocabulary the rest of the system uses for exactly these verbs.
*/
enum PanelMetrics {
	/**
	The chrome the wide controls share: the website chooser, Crop, Browsing Mode and Quit.

	One definition, because "make Quit match the chooser" is a request that comes back every time one
	of them is adjusted on its own.

	`controlRadius` is the exception that reaches wider than this group: every control the panel draws
	uses it, 22-point squares and 28-point pills alike. It was two numbers — 5 written four times and
	6 written once — which is what stopped the question being asked at all. There is no system answer
	to borrow here: AppKit and SwiftUI expose no standard control radius, and `ConcentricRectangle`
	answers a different question (what an inner radius should be inside a known outer one) and needs
	macOS 26, above this app's floor.
	*/
	// swiftlint:disable:next hardcoded_font_size - This is the definition the rule redirects to.
	static let font = Font.system(size: 13)
	static let height = 28.0
	static let horizontalPadding = 15.0
	static let controlRadius = 5.0
	// swiftlint:disable:next hardcoded_font_size - This is the definition the rule redirects to.
	static let symbolFont = Font.system(size: 11, weight: .semibold)

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
	The width of the website chooser, and of Quit, which is asked to match it.

	Three quarters of the picture above it — derived rather than written as 195, because it was prose
	before and prose does not change when the column does.
	*/
	static let chooserWidth = columnWidth * 0.75

	/**
	The colour a control wears while what it turns on is on.

	Sampled from the app's own icon rather than taken from the system accent: the accent is whatever
	the user picked for their Mac, and a wallpaper app lighting one of its buttons in it says "this is
	selected" rather than "this is running". The icon's orange says the second.
	*/
	// swiftlint:disable:next hardcoded_ui_colour - This is the definition the rule redirects to.
	static let onTint = Color(red: 234 / 255, green: 115 / 255, blue: 63 / 255)

	/**
	The wash laid over the panel's own vibrancy.

	A popover is glass, and glass over a wallpaper is glass over whatever that page happens to be
	showing this second — a bright frame of a video puts the column labels on top of it. A thin coat
	of the window colour keeps the material and takes some of the page back out of it.

	`windowBackgroundColor` rather than a literal: it is already the colour that follows the
	appearance, so one value is a pale wash in light mode and a dark one in dark mode.
	*/
	static let glassWash = Color(nsColor: .windowBackgroundColor).opacity(0.35)

	/**
	What goes on top of `onTint`.

	Named because the tint was and this was not, so three call sites each decided separately that lit
	means white — which is a property of the tint, not of the control.
	*/
	// swiftlint:disable:next hardcoded_ui_colour - This is the definition the rule redirects to.
	static let onForeground = AnyShapeStyle(.white)

	/**
	What the pointer being over something looks like.

	One answer, because there were three: the buttons used `.quaternary`, the column used a fixed
	pale wash at fifteen percent that was invisible over a light popover, and the column's border used
	the accent. The resting fills are deliberately not named alongside it — `.quinary` and `.clear`
	never disagreed with each other, and a name that prevents nothing is a name to maintain.
	*/
	static let hoverFill = AnyShapeStyle(.quaternary)
}

struct PanelButton: View {
	let symbol: String
	let label: String
	var isOn = false
	var isEnabled = true
	let action: () -> Void

	@State private var isPressed = false
	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			Image(systemName: symbol)
				.font(PanelMetrics.font.weight(.medium))
				.frame(width: 26, height: 22)
				.foregroundStyle(foreground)
				.background(background, in: RoundedRectangle(cornerRadius: PanelMetrics.controlRadius))
				.contentShape(RoundedRectangle(cornerRadius: PanelMetrics.controlRadius))
		}
		.buttonStyle(.plain)
		.disabled(!isEnabled)
		.opacity(isEnabled ? 1 : 0.35)
		.scaleEffect(isPressed ? 0.9 : 1)
		.animation(.easeOut(duration: 0.12), value: isPressed)
		.onHover { isHovering = $0 }
		// `onLongPressGesture` with no delay is the way to read "finger is down" from a SwiftUI button;
		// the button's own style gives nothing back once it is `.plain`.
		.onLongPressGesture(minimumDuration: 0) {
			// Nothing on completion: the press itself is the whole point, and the button's own action
			// already fires.
		} onPressingChanged: {
			isPressed = $0
		}
		.help(label)
		.accessibilityLabel(label)
	}

	private var foreground: some ShapeStyle {
		isOn ? PanelMetrics.onForeground : AnyShapeStyle(.primary)
	}

	private var background: some ShapeStyle {
		if isOn {
			AnyShapeStyle(PanelMetrics.onTint)
		} else if isHovering {
			PanelMetrics.hoverFill
		} else {
			AnyShapeStyle(.clear)
		}
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

Exactly as tall as `PanelButton`, because it shares a row with three of them and a field half a point
taller would make the whole column grow the moment the mode left `pinned`.
*/
struct PanelIntervalField: View {
	@Binding var minutes: Double

	var body: some View {
		HStack(spacing: 4) {
			TextField(
				"",
				value: $minutes,
				format: .number.grouping(.never).precision(.fractionLength(0))
			)
				.textFieldStyle(.plain)
				.multilineTextAlignment(.center)
				.font(PanelMetrics.font)
				.frame(width: 34, height: 22)
				.background(.quinary, in: RoundedRectangle(cornerRadius: PanelMetrics.controlRadius))
				.help(String(localized: "Minutes between websites"))
				.accessibilityLabel(String(localized: "Minutes between websites"))

			Text("min")
				.font(PanelMetrics.font)
				.foregroundStyle(.secondary)
		}
		.frame(height: 22)
	}
}

/**
A button whose label is a word rather than a symbol, for the two verbs no symbol says plainly.
*/
struct PanelWideButton: View {
	let title: String

	/**
	An optional symbol before the words, for the one button that cannot be undone.
	*/
	var symbol: String?

	var isOn = false
	var isEnabled = true
	let action: () -> Void

	@State private var isPressed = false
	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 6) {
				if let symbol {
					Image(systemName: symbol)
						.font(PanelMetrics.symbolFont)
				}

				Text(title)
					.font(PanelMetrics.font)
					.lineLimit(1)
					// Centred when the button is given a width, and hugging when it is not.
					.frame(maxWidth: .infinity)
					.fixedSize(horizontal: false, vertical: true)
			}
				.padding(.horizontal, PanelMetrics.horizontalPadding)
				.frame(height: PanelMetrics.height)
				.foregroundStyle(isOn ? PanelMetrics.onForeground : AnyShapeStyle(.primary))
				.background(background, in: RoundedRectangle(cornerRadius: PanelMetrics.controlRadius))
				.contentShape(RoundedRectangle(cornerRadius: PanelMetrics.controlRadius))
		}
		.buttonStyle(.plain)
		.disabled(!isEnabled)
		.opacity(isEnabled ? 1 : 0.35)
		.scaleEffect(isPressed ? 0.96 : 1)
		.animation(.easeOut(duration: 0.12), value: isPressed)
		.onHover { isHovering = $0 }
		.onLongPressGesture(minimumDuration: 0) {
			// Nothing on completion: the press itself is the whole point, and the button's own action
			// already fires.
		} onPressingChanged: {
			isPressed = $0
		}
	}

	private var background: some ShapeStyle {
		if isOn {
			AnyShapeStyle(PanelMetrics.onTint)
		} else if isHovering {
			PanelMetrics.hoverFill
		} else {
			AnyShapeStyle(.quinary)
		}
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
