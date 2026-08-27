import AppKit
import Defaults
import KeyboardShortcuts

/**
Putting the whole app back to the state it shipped in.

The one action in Nifro that cannot be undone, which is why it asks first, why the question spells
out all four of what resets, what comes back, what goes, and what stays, and why it lives on its own
at the bottom of Advanced rather than next to a control that adds something.

**It wipes the domain rather than a list of keys.** There are twenty-three `Defaults.Keys` today.
Written out here, that is a second place answering "what are the app's preferences", with nothing
making the two agree — and the way it fails is silent. Somebody adds a preference, never finds this
list, and their key survives a restore for as long as it takes another person to sit down and count.
That is the same defect this codebase keeps finding: a mechanism whose members have to volunteer.
`Defaults.removeAll()` has no members. A preference added tomorrow is covered by existing.

The price of that is reach: it also clears things that are not `Defaults.Keys` — where each page was
scrolled to, the one-off tips, the flag that first launch checks. All of that is the app's own state
and all of it is part of "how it shipped", so the reach is wanted, with one exception.

**The interface language is lifted out of the wipe and put back.** It is an exception for a reason
that is about *when it is read*, not about how much it matters: `AppleLanguages` is consulted once
while the process starts, so a restore that cleared it would leave every window in the old language
until the user quit and reopened — and the only honest way to finish would be a second dialog asking
them to do that. Every other preference in the domain applies the moment it changes, so nothing else
here needs a relaunch and this file does not offer one. The exception is `preservedKey`: one key,
named once, guarded by a test that fails the moment a second one joins it.

Website data is not in `UserDefaults` at all. Cookies, logins and the WebKit cache live in the data
store, so keeping the user signed in takes nothing but this file never reaching for
`WKWebsiteDataStore`. Whether Nifro launches at login is not here either — that is a login item
registered with the system through `SMAppService`, and silently unregistering it would stop the
wallpaper coming back after a reboot, which is not something anybody asks for by restoring settings.
*/
@MainActor
enum RestoreDefaults {
	/**
	The one preference the wipe is not allowed to take.

	Not because the language is precious, but because it is read once as the process starts and never
	again: resetting it would be a change the running app cannot show, and a restore that has to ask
	the user to quit and reopen is a worse thing to own than this one line. Nothing else in the domain
	is read that way, which is why this is a single constant rather than a collection — adding a
	second exception means changing the shape of this file, and that is what brings somebody back to
	`RestoreDefaultsTests` to argue for it.
	*/
	private static let preservedKey = "AppleLanguages"

	/**
	Ask, and do it if the answer is yes.

	Cancel is the default button, so Return on a dialog nobody read leaves everything alone. The other
	one is marked destructive, which is the only thing in this app drawn in red.
	*/
	static func confirmAndRun() {
		let alert = NSAlert(
			title: String(localized: "Restore Nifro to how it shipped?"),
			message: String(localized: """
				Reset: every setting, every keyboard shortcut, which display each website is on, and which displays are grouped together.

				Reinstalled: the websites Nifro comes with, in the order it comes with them.

				Lost: the websites you added yourself, and every change you made to any website — the region you framed, the CSS and JavaScript you wrote, how often it reloads, and whether it plays sound. There is no undo.

				Kept: your logins and cookies, so no site asks you to sign in again. The language you picked for Nifro and whether Nifro launches at login are kept too.
				"""),
			buttonTitles: [
				String(localized: "Restore All Settings"),
				String(localized: "Cancel")
			],
			defaultButtonIndex: 1
		)

		alert.buttons.first?.hasDestructiveAction = true

		guard alert.runModal() == .alertFirstButtonReturn else {
			return
		}

		perform()
	}

	private static func perform() {
		// The app's own persistent domain, deliberately not `UserDefaults.standard.object(forKey:)`.
		// A plain read walks the search list, so a user who never picked a language would get the Mac's
		// own language list back from the global domain — and writing that into the app's domain below
		// would pin Nifro to today's system language for good, which is the opposite of leaving the
		// setting alone. Asking the same domain the wipe empties means `nil` says exactly one thing:
		// there was nothing here to preserve.
		let chosenLanguage = UserDefaults.standard.persistentDomain(forName: SSApp.idString)?[preservedKey]

		// Before the wipe, and the order is the whole point. `Defaults.removeAll` deletes the
		// `KeyboardShortcuts_` entries as raw keys, which tells the package nothing: a shortcut the
		// user had changed would stay registered with the system for the rest of the session, firing on
		// a combination the app no longer shows anywhere. Going through the package first unregisters
		// the old combination and puts the default back in its place. The wipe then deletes the default
		// it just wrote — and an absent entry already means "the default", so the two still agree, and
		// `Name` writes it back the next time anything asks for the shortcut.
		//
		// `Shortcut.allNames` rather than a list written here, for the same reason as the keys below:
		// the table is `CaseIterable`, so a shortcut added later is in this reset by existing.
		KeyboardShortcuts.reset(Shortcut.allNames)

		Defaults.removeAll()

		// After the wipe, or the wipe would take it straight back out again. Written back as it was
		// read rather than through `Localization.request`, which only knows the languages Nifro ships:
		// System Settings can put a regional form such as "zh-Hans-US" in this key, and normalising it
		// would quietly change a choice the user made somewhere else. Nothing is written when there was
		// nothing to read, which is a Mac that has never been asked: `Localization` puts English back
		// in the key on the next launch, the same as it does on a fresh install.
		if let chosenLanguage {
			UserDefaults.standard.set(chosenLanguage, forKey: preservedKey)
		}

		// The entry point first launch uses, now that the flag guarding it went with everything else.
		// Nothing else has to be driven from here: writing the website list is what the rest of the app
		// already watches, so the scenes are rebuilt, the shipped pages load on the displays they were
		// seeded onto, and every preference that has a publisher took its default on the way past.
		// Restoring through the same path as launching means there is one path, not a second one that
		// has to be kept in step with it.
		WebsitesController.shared.installFeaturedWebsitesIfNeeded()
	}
}
