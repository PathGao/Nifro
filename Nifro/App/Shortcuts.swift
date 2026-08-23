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
	case toggleBrowsingMode
	case holdToInteract
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
		case .toggleBrowsingMode:
			.b
		case .holdToInteract:
			.h
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
			String(localized: "Toggle enabled state")
		case .toggleBrowsingMode:
			String(localized: "Toggle browsing mode")
		case .holdToInteract:
			String(localized: "Hold to use the page")
		case .toggleSound:
			String(localized: "Toggle sound")
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

	`holdToInteract` is the one exception: it acts on the key going down and again on it coming up, so
	`HoldToInteract` installs it rather than driving it from here. It still belongs in the table — it
	needs a default and a row in Settings like every other one.
	*/
	var action: Action? {
		switch self {
		case .holdToInteract:
			nil
		case .toggleEnabled:
			.toggleEnabled
		case .toggleBrowsingMode:
			.toggleBrowsingMode
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
				action.run()
			}
		}
	}

	/**
	Every shortcut's name, for turning them all off while a menu is open.

	`NSMenu` puts the thread in tracking mode, which stops the global hotkeys being delivered and
	buffers the key events instead. They then all fire at once when the menu closes, which reads as
	the app doing something nobody asked for.
	*/
	@MainActor
	static var allNames: [KeyboardShortcuts.Name] { allCases.map(\.name) }
}
