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
		.onLongPressGesture(minimumDuration: 0) {
			// Nothing on completion: the press itself is the whole point, and the button's own action
			// already fires.
		} onPressingChanged: {
			isPressed = $0
		}
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

	@State private var overflow: CGFloat = 0
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
				.frame(width: outer.size.width, alignment: .leading)
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
