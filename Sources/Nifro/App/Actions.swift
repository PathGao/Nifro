/**
Everything the app can be told to do, in one table.

There are four ways to ask for the same thing: the menu, a keyboard shortcut, a `nifro://` URL, and a
Shortcuts action. Each one used to carry its own copy of the body, so a change had to be made four
times and there was no way to notice when it was made three. It already went wrong: Browsing Mode
explains itself the first time it is switched on, and that explanation lived in the menu item, so
turning it on by shortcut, by URL, or from Shortcuts silently skipped it — which is the one route
where the explanation matters most, since the point of it is that the page may be hidden behind your
windows.

That explanation is no longer in here either, and for the same reason one step out: the panel
replaced the menu and switches Browsing Mode on without running an `Action`, so a table of four
entry points was the wrong place to keep a rule that now has five. It lives on the verb the entry
points share — `AppState.toggleBrowsingMode(on:)` — and `ScopeTests` fails when a sixth arrives
without it.

**Each one acts on one scene, and it is the scene `run` resolves — never the whole list.** Which scene
that is depends on where the request came from; see `Source`. Two cases used to resolve a scene and
then ignore it: Reload called `AppState.reloadWebsite()`, which loops every display, and Choose Region
re-resolved through `actingScene` inside itself. Measured: one `nifro://reload` re-fetched both sites
and restarted the other display's video from zero — so pressing Reload in front of the monitor threw
away the laptop's signed-in page as well, and the Shortcuts pane's own footer says it should not have.
There is no Reload button in the panel, so the menu, the shortcut and the URL are the only ways in and
all three did it.

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
	main display, the one with the menu bar.
	*/
	enum Source {
		case pointer
		case automation
	}

	@MainActor
	func run(from source: Source = .automation) {
		// Disable is the whole app rather than one display, so it resolves no scene — and it is the one
		// action that has to work when there is none, because switching everything back on is the way
		// out of that state.
		if self == .toggleEnabled {
			AppState.shared.isManuallyDisabled.toggle()
			return
		}

		// Every other action names a display. `primaryScene` used to build a scene sooner than answer
		// nothing, so this could not be reached empty; it can now, and nothing happening is the honest
		// outcome — the same answer `BrowsingModeShortcut.begin` gives when the pointer is nowhere.
		guard let scene = source == .pointer ? AppState.shared.actingScene : AppState.shared.primaryScene else {
			return
		}

		switch self {
		case .toggleEnabled:
			// Returned above. Listed because the switch is exhaustive, which is what makes a new case
			// say which half of this it belongs to.
			break
		case .toggleBrowsingMode:
			AppState.shared.toggleBrowsingMode(on: scene.display)
		case .toggleSound:
			// The scene's own verb, not a second copy of the flip. This one had no guard at all: the
			// panel's copy checked there was a website and this one checked the same, and neither asked
			// whether the page making the noise is the website being written to.
			scene.toggleSound()
		case .chooseRegion:
			// The scene resolved above, handed over rather than looked up again. `beginCropSelection`
			// falls back to `actingScene` when it is given nothing, which is the same answer today
			// because both callers are pointer-resolved — but it is the same answer by coincidence, and
			// the coincidence ends the first time an automation reaches this case.
			AppState.shared.beginCropSelection(on: scene)
		case .reload:
			scene.reload()
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
