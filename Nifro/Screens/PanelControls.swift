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
				.font(.system(size: 13, weight: .medium))
				.frame(width: 26, height: 22)
				.foregroundStyle(foreground)
				.background(background, in: RoundedRectangle(cornerRadius: 5))
				.contentShape(RoundedRectangle(cornerRadius: 5))
		}
		.buttonStyle(.plain)
		.disabled(!isEnabled)
		.opacity(isEnabled ? 1 : 0.35)
		.scaleEffect(isPressed ? 0.9 : 1)
		.animation(.easeOut(duration: 0.12), value: isPressed)
		.onHover { isHovering = $0 }
		// `onLongPressGesture` with no delay is the way to read "finger is down" from a SwiftUI button;
		// the button's own style gives nothing back once it is `.plain`.
		.onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
		.help(label)
		.accessibilityLabel(label)
	}

	private var foreground: some ShapeStyle {
		isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
	}

	private var background: some ShapeStyle {
		if isOn {
			// Lit, and lit in the accent colour the user chose rather than one of ours, so "this is on"
			// reads the same here as it does everywhere else on their Mac.
			AnyShapeStyle(.tint)
		} else if isHovering {
			AnyShapeStyle(.quaternary)
		} else {
			AnyShapeStyle(.clear)
		}
	}
}

/**
A button whose label is a word rather than a symbol, for the two verbs no symbol says plainly.
*/
struct PanelWideButton: View {
	let title: String
	var isOn = false
	var isEnabled = true
	let action: () -> Void

	@State private var isPressed = false
	@State private var isHovering = false

	var body: some View {
		Button(action: action) {
			Text(title)
				.font(.system(size: 11))
				.lineLimit(1)
				.padding(.horizontal, 10)
				.frame(height: 22)
				.foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
				.background(background, in: RoundedRectangle(cornerRadius: 5))
				.contentShape(RoundedRectangle(cornerRadius: 5))
		}
		.buttonStyle(.plain)
		.disabled(!isEnabled)
		.opacity(isEnabled ? 1 : 0.35)
		.scaleEffect(isPressed ? 0.96 : 1)
		.animation(.easeOut(duration: 0.12), value: isPressed)
		.onHover { isHovering = $0 }
		.onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
	}

	private var background: some ShapeStyle {
		if isOn {
			AnyShapeStyle(.tint)
		} else if isHovering {
			AnyShapeStyle(.quaternary)
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
		case .loop:
			"repeat"
		case .random:
			"shuffle"
		case .pinned:
			"pin.fill"
		}
	}

	var label: String {
		switch self {
		case .loop:
			String(localized: "Rotating in order")
		case .random:
			String(localized: "Rotating at random")
		case .pinned:
			String(localized: "Staying on this website")
		}
	}
}
