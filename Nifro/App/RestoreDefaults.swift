import AppKit
import Defaults
import KeyboardShortcuts

/**
Putting the app's settings back to how they shipped.

The one action in Nifro that cannot be undone, which is why it asks first, why the question spells
out both of what resets and what stays, and why it lives on its own at the bottom of Advanced rather
than next to a control that adds something.

**The settings and not the websites, which is a line this file used to be on the wrong side of.** A
restore emptied the domain, `playlists` was in the domain, and `playlists` is the whole of where a
website is stored — so restoring settings deleted every website the user had, and the three
destructive-looking actions in Advanced were one action wearing three labels. They are three now.
This resets the settings. Clear All Website Data switches the displays off and takes every website
and every playlist. Add the Default Playlist puts the shipped list back. Somebody who wants their
opacity back does not have to spend their websites on it, and nothing here has to reinstall anything
to make up for what it took, because it takes nothing.

What that leaves on screen is the point of it: `currentPlaylists` and `currentWebsites` go with the
rest, an absent entry in each is "the default playlist" and "the top of the list", so every display
lands on the default playlist showing its first website — out of the websites the user still has.

**It wipes the domain rather than a list of keys.** Written out here, the keys would be a second
place answering "what are the app's preferences", with nothing making the two agree — and the way it
fails is silent. Somebody adds a preference, never finds this list, and their key survives a restore
for as long as it takes another person to sit down and count. That is the same defect this codebase
keeps finding: a mechanism whose members have to volunteer. `Defaults.removeAll()` has no members. A
preference added tomorrow is covered by existing.

**And no count of them either**, which this paragraph used to open with: "there are twenty-three
`Defaults.Keys` today", when there were twenty-two. A count is the shortest possible version of the
list and goes stale in exactly the way the sentence after it warns about, so correcting the number
would only have set the same trap one key further out.

The price of that is reach: it also clears things that are not `Defaults.Keys` — the one-off tips,
the flag that first launch checks. Both still go, and both are the app's own state rather than
anything the user made, so the reach is still wanted. What has come out from under it is the third
thing that used to be in this sentence, where each page was scrolled to: `ScrollRestoration` calls
those records website data in as many words, and Clear All Website Data is what deletes them.

**So the wipe now has a list of what it may not take, and that is a real cost stated rather than
argued away.** It is the defect above pointing the other way. A preference added tomorrow is covered
by `removeAll()` for free; a *website* key added tomorrow is covered by nothing, and somebody who
never finds `websiteKeys` below has their key eaten by a restore — which is worse than the failure
this file was built to avoid, because a setting that survives is an annoyance and a website that does
not is gone. Two things are done about it and neither is a promise to remember. The per-page records
are matched by prefix through `PerPageDefaults.allCases`, so a fourth kind of thing a page remembers
is preserved by existing, exactly as `Shortcut.allNames` covers a shortcut added later. And the four
named keys are pinned in `RestoreDefaultsTests` against the count of keys `Constants.swift` declares,
so adding any preference at all fails that test until somebody has said which side of this line it
falls on. The list cannot rot quietly; it can only rot in front of whoever added the key.

**The interface language is lifted out of the wipe and put back.** It is an exception for a reason
that is about *when it is read*, not about how much it matters: `AppleLanguages` is consulted once
while the process starts, so a restore that cleared it would leave every window in the old language
until the user quit and reopened — and the only honest way to finish would be a second dialog asking
them to do that. Every other preference in the domain applies the moment it changes, so nothing else
here needs a relaunch and this file does not offer one. The exception is `preservedKey`: one key,
named once, guarded by a test that fails the moment a second one joins it.

What a page *did* is not in `UserDefaults` at all. Cookies, logins and the WebKit cache live in the
data store, so keeping the user signed in takes nothing but this file never reaching for
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
	The websites, and the two flags that say what has already been done to them.

	`playlists` is the whole of where a website is stored and `websites` is the pre-playlist list it was
	built from — the only copy of that there will ever be, which `Constants.swift` argues for keeping
	and a settings reset is not a reason to burn.

	**The three flags are the half that has teeth, and they are neither a setting nor data.** Each one
	is a record of something already done *to* the data: the websites have been converted to playlists,
	each of them has been told whether it overrides the reload interval, the shipped websites have been
	installed. Reset one while what it describes survives and the app redoes
	the work on top of a result that is already there. `migrateToPlaylistsIfNeeded` assigns `playlists`
	outright, so a cleared `hasMigratedWebsitesToPlaylists` replaces every list the user has made with
	one list built from a `websites` key they stopped editing before the conversion — on the very next
	launch, silently, and with the playlists it overwrote already gone. A cleared
	`hasInstalledFeaturedWebsites` is the milder one and still wrong: the next launch lays the shipped
	eight back over the user's list, including the ones they deleted on purpose, and a second copy of
	the ones they kept.

	`hasMigratedWebsiteReloadOverrides` is the third and the sharpest. It guards a conversion that reads
	each stored record for whether it carries a reload interval of its own, and this build writes one on
	every record, because that field is no longer optional — so the question is answerable exactly once
	and answers "yes, all of them" for ever after. Cleared, the next launch marks every website in the
	user's list as overriding the reload interval, each with whatever number happens to be sitting in
	its field. The other two cost the user work they had done; this one changes what their wallpapers
	do. A flag travels with the data it is about.

	The reload interval's *own* migration flag is deliberately not here.
	`hasMigratedReloadIntervalToASwitch` decides an app setting from an app setting, so both go in the
	wipe together: the next launch finds no stored interval and switches reloading off, which is where a
	restore is meant to leave it.

	What is *not* here is the rest of what is filed under a website. `currentWebsites`,
	`currentPlaylists`, `rotationModes`, `rotationIntervals`, `disabledDisplays` and `browsingDisplays`
	describe screens rather than websites, and resetting them is what a restore visibly *is*.
	*/
	private static let websiteKeys = [
		"playlists",
		"websites",
		"hasMigratedWebsitesToPlaylists",
		"hasMigratedWebsiteReloadOverrides",
		"hasInstalledFeaturedWebsites"
	]

	/**
	Whether this raw key is one of the user's websites rather than one of the app's preferences.

	Two shapes because the storage has two. The keys above are written down once each; the per-page
	records — where a page was scrolled to, the fragment it had moved itself to, how far it was zoomed
	— are one key per website per kind, so there is nothing to write down and a prefix is the only way
	to ask. `PerPageDefaults.allCases` is the same table `forgetWherePagesWere` sweeps with, which is
	what makes these two agree: the button that deletes them and the wipe that has to skip them read
	one list, and a fourth kind of record is in both by being a case.
	*/
	private static func isWebsiteData(_ key: String) -> Bool {
		websiteKeys.contains(key) || PerPageDefaults.allCases.contains { key.hasPrefix($0.rawValue) }
	}

	/**
	Ask, and do it if the answer is yes.

	Cancel is the default button, so Return on a dialog nobody read leaves everything alone. The other
	one is marked destructive, which is the only thing in this app drawn in red.
	*/
	static func confirmAndRun() {
		let alert = NSAlert(
			title: String(localized: "Restore all settings?"),
			message: String(localized: "Reset: every setting, every keyboard shortcut, and what each display is showing. Every display goes back to the default playlist and its first website. There is no undo.\n\nKept: your websites and playlists, your logins, the language you picked, and whether Nifro launches at login."),
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

		// The same domain, read again rather than folded into the line above, because these two are
		// preserved for reasons that have nothing to do with each other: one is a key the running app
		// cannot be shown a new value for, and this is everything the user made. Sharing a read would
		// put them in one bucket and invite the next person to add to whichever bucket was nearer.
		let websiteData = UserDefaults.standard.persistentDomain(forName: SSApp.idString)?
			.filter { isWebsiteData($0.key) } ?? [:]

		// Before the wipe, and the order is the whole point. `Defaults.removeAll` deletes the
		// `KeyboardShortcuts_` entries as raw keys, which tells the package nothing: a shortcut the
		// user had changed would stay registered with the system for the rest of the session, firing on
		// a combination the app no longer shows anywhere. Going through the package first unregisters
		// the old combination and puts the default back in its place. The wipe then deletes the default
		// it just wrote — and an absent entry already means "the default", so the two still agree, and
		// `Name` writes it back the next time anything asks for the shortcut.
		//
		// `Shortcut.allNames` rather than a list written here, for the same reason as
		// `PerPageDefaults.allCases` above: the table is `CaseIterable`, so a shortcut added later is in
		// this reset by existing.
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

		// After the wipe for the same reason, and each entry exactly as it was read: these are encoded
		// blobs the wipe has already taken out, so there is nothing here to merge with and nothing to
		// decode. Writing `playlists` is also what finishes the restore visibly — it is the key the rest
		// of the app watches, so the scenes are rebuilt against the marks that just went, and every
		// preference with a publisher took its default on the way past.
		//
		// Nothing is installed afterwards. It used to be: `installDefaultPlaylist` forced
		// `hasInstalledFeaturedWebsites` back to false and put the shipped eight in, which was the only
		// way to leave a working desktop behind a wipe that had just deleted every website. With the
		// websites still here that same line lays the shipped list *over* the user's own — the ones they
		// deleted back again, the ones they kept in duplicate — to fix a problem this no longer causes.
		// Getting the shipped list back is Add the Default Playlist, in the same pane, which is the one
		// caller of that method now.
		//
		// And nothing is switched off either. Every deletion in this app switches off the displays
		// showing what it takes, because there is no replacement the app could pick that the user asked
		// for — see `WebsitesController.switchOffDisplaysShowing`. This deletes no website, so the rule
		// has nothing to say here: what each display is showing goes back to the default playlist's
		// first website, out of a list that is still the user's.
		for (key, value) in websiteData {
			UserDefaults.standard.set(value, forKey: key)
		}
	}
}
