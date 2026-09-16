import AppKit
import KeyboardShortcuts

/**
Every keyboard shortcut, in one table.

A shortcut used to be written in four places: its name and default here, its handler in `Events`, its
recorder row in Settings, and `setShortcut(for:)` on the menu item. Four places is four chances to
add a shortcut that records but never fires, or fires but shows no key next to the command — and both
of those happened. One row now carries all of it, and the other three read the table.

The defaults all live on Control-Option-Command. These are global hotkeys: they fire whatever app is
in front, so a default is a claim on a key combination in every app the user owns. That corner is the
one macOS itself barely uses and almost no app defaults into, which makes it the only place a claim
can be staked without taking something away. Shipping no default at all was worse than staking one —
the menu then has nothing to show beside the command, and nobody discovers the shortcut exists.
*/
enum Shortcut: String, CaseIterable {
	case toggleEnabled
	// Its stored key is still `toggleBrowsingMode`, from when toggling was all it did. Renaming the
	// case would rename the `KeyboardShortcuts.Name` behind it and silently drop every binding anyone
	// has recorded.
	case browsingMode = "toggleBrowsingMode"
	case toggleSound
	case chooseRegion
	case reload
	case nextWebsite
	case previousWebsite
	case randomWebsite

	/**
	The key this shortcut is bound to out of the box, on Control-Option-Command.
	*/
	private var defaultKey: KeyboardShortcuts.Key {
		switch self {
		case .toggleEnabled:
			.w
		case .browsingMode:
			.b
		case .toggleSound:
			.s
		case .chooseRegion:
			.c
		case .reload:
			.r
		case .nextWebsite:
			.rightBracket
		case .previousWebsite:
			.leftBracket
		case .randomWebsite:
			.k
		}
	}

	/**
	What the row in Settings is called.
	*/
	var title: String {
		switch self {
		case .toggleEnabled:
			String(localized: "Turn Nifro on or off")
		case .browsingMode:
			String(localized: "Browsing Mode — hold to use, tap to toggle")
		case .toggleSound:
			String(localized: "Turn sound on or off")
		case .chooseRegion:
			String(localized: "Choose region")
		case .reload:
			String(localized: "Reload website")
		case .nextWebsite:
			String(localized: "Next website")
		case .previousWebsite:
			String(localized: "Previous website")
		case .randomWebsite:
			String(localized: "Random website")
		}
	}

	var name: KeyboardShortcuts.Name {
		.init(rawValue, default: .init(defaultKey, modifiers: [.control, .option, .command]))
	}

	/**
	The action it runs, or `nil` when the shortcut is not a press-and-release at all.

	`browsingMode` is the one exception: how long the key is held is the whole difference between its
	two behaviours, so it acts on the key going down and again on it coming up, and
	`BrowsingModeShortcut` installs it rather than driving it from here. It still belongs in the table
	— it needs a default and a row in Settings like every other one.
	*/
	var action: Action? {
		switch self {
		case .browsingMode:
			nil
		case .toggleEnabled:
			.toggleEnabled
		case .toggleSound:
			.toggleSound
		case .chooseRegion:
			.chooseRegion
		case .reload:
			.reload
		case .nextWebsite:
			.nextWebsite
		case .previousWebsite:
			.previousWebsite
		case .randomWebsite:
			.randomWebsite
		}
	}

	/**
	Start listening for all of them.
	*/
	@MainActor
	static func install() {
		for shortcut in allCases {
			guard let action = shortcut.action else {
				continue
			}

			KeyboardShortcuts.onKeyUp(for: shortcut.name) {
				// The one entry point with a pointer behind it.
				action.run(from: .pointer)
			}
		}
	}

	/**
	Every shortcut's name, for turning them all off while the display panel is open.

	These are global hotkeys, so putting a window in front of the user does not stop them arriving —
	and the panel is the one window where that matters, because it is a column of per-display controls
	drawn over the very displays those controls act on. A shortcut that acts on a display resolves which
	one from where the pointer is, through `Action.run(from: .pointer)`, and while the panel is up the
	pointer is on the panel — which hangs off the menu bar and so belongs to whichever screen carries
	it. So the answer comes out the same wherever somebody was aiming: a key pressed with the panel
	open skips the column under the pointer and acts on the main display's wallpaper instead.
	`DisplayPanelController` is where the disable and the re-enable are, and it re-enables through the
	popover's delegate rather than beside its own dismissal, because a transient popover also closes
	itself on an outside click and on Escape — a route that missed the re-enable would leave every
	shortcut dead for the rest of the session.

	This was written for the menu the panel replaced and the reasoning was `NSMenu`'s tracking mode,
	which is not what happens here and would send the next reader looking for the wrong symptom. A
	popover runs no tracking loop of its own, and `disable` unregisters the hotkeys rather than
	withholding their events, so a press while the panel is up is delivered to whatever is in front —
	the app itself, by then — and is over. Nothing is buffered and nothing fires late.
	*/
	@MainActor
	static var allNames: [KeyboardShortcuts.Name] { allCases.map(\.name) }
}
