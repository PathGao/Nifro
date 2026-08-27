import AppKit

/**
Everything the app can be told to do, in one table.

There are four ways to ask for the same thing: the menu, a keyboard shortcut, a `nifro://` URL, and a
Shortcuts action. Each one used to carry its own copy of the body, so a change had to be made four
times and there was no way to notice when it was made three. It already went wrong: Browsing Mode
explains itself the first time it is switched on, and that explanation lived in the menu item, so
turning it on by shortcut, by URL, or from Shortcuts silently skipped it — which is the one route
where the explanation matters most, since the point of it is that the page may be hidden behind your
windows.

Each one acts on the primary scene, the display Settings points at. An action reached from the menu
bar has no way to say which screen it means, and moving a screen the person is not looking at is the
worse of the two answers.

What is *not* in here is where each action sits in the menu, when it is greyed out, and what its
tooltip says. Those differ per item and per entry point, and pulling them in would turn this into a
table of exceptions. The table owns what an action *is*; the menu still owns what the menu looks
like.
*/
enum Action: String, CaseIterable {
	case toggleEnabled
	case toggleBrowsingMode
	case toggleSound
	case chooseRegion
	case reload
	case nextWebsite
	case previousWebsite
	case randomWebsite

	/**
	The `nifro://` path that runs it, when there is one.

	Only the five upstream commands are exposed. A URL command is a public interface that other
	people's scripts come to depend on, so adding one is a promise to keep it; the ones missing here
	are missing on purpose rather than by oversight.
	*/
	var urlCommand: String? {
		switch self {
		case .toggleBrowsingMode:
			"toggle-browsing-mode"
		case .reload:
			"reload"
		case .nextWebsite:
			"next"
		case .previousWebsite:
			"previous"
		case .randomWebsite:
			"random"
		case .toggleEnabled, .toggleSound, .chooseRegion:
			nil
		}
	}

	/**
	Where the request came from, because only one of them has a pointer behind it.

	A shortcut is pressed by somebody looking at a screen. A Shortcuts automation or a `nifro://` URL
	may fire from a cron job, a Focus change or a script with nobody at the machine at all, and
	"whichever display the mouse happens to be over" is then a coin toss. Those keep acting on the
	display named in Settings.
	*/
	enum Source {
		case pointer
		case automation
	}

	@MainActor
	func run(from source: Source = .automation) {
		let scene = source == .pointer ? AppState.shared.actingScene : AppState.shared.primaryScene
		switch self {
		case .toggleEnabled:
			AppState.shared.isManuallyDisabled.toggle()
		case .toggleBrowsingMode:
			Defaults[.isBrowsingMode].toggle()

			SSApp.runOnce(identifier: "activatedBrowsingMode") {
				DispatchQueue.main.async {
					NSAlert.showModal(
						title: String(localized: "Browsing Mode lets you temporarily interact with the website. For example, to log into an account or scroll to a specific position on the website."),
						message: String(localized: "If you don't currently see the website, you might need to hide some windows to reveal the desktop.")
					)
				}
			}
		case .toggleSound:
			guard let website = scene.website else {
				return
			}

			WebsitesController.shared.update(website.id) {
				$0.audio = $0.audio == .unmuted ? .muted : .unmuted
			}
		case .chooseRegion:
			AppState.shared.beginCropSelection()
		case .reload:
			AppState.shared.reloadWebsite()
		case .nextWebsite:
			WebsitesController.shared.makeNextCurrent(on: scene.display)
		case .previousWebsite:
			WebsitesController.shared.makePreviousCurrent(on: scene.display)
		case .randomWebsite:
			WebsitesController.shared.makeRandomCurrent(on: scene.display)
		}
	}

	/**
	The action a `nifro://` path asks for, if any.
	*/
	static func forURLCommand(_ command: String) -> Self? {
		allCases.first { $0.urlCommand == command }
	}
}
