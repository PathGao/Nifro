import Foundation

/**
Turning two settings from "a number that goes missing" into a switch and a number, once, without
losing what the user had.

Both of them were an optional interval where `nil` meant off — the app-wide reload interval in
`Defaults`, and each website's own override inside its stored record. That shape has one
representation of off and it is still wrong, because the control that writes it destroys the value it
is switching: turning the reload off writes `nil` over thirty minutes, and turning it back on writes
the constant the switch was built with. A user gets an hour back and nothing says their number went.
The pair the app already had for dimming — a `Bool` for whether, a `Double` for how much — is what
both are now.

**The conversion has to happen exactly once, and the reason is the same for both: after this build
has written a record, the question can no longer be asked.** "Was the interval switched on" was
"is there an entry under this key", and this build writes an entry for everybody. "Did this website
override" was "does its record carry a `reloadInterval`", and this build's `Website` carries one
always, because the field is no longer optional. Run either conversion a second time against what it
produced and every user is reading their settings as though they had turned everything on.

So both are guarded by a flag of their own — `hasMigratedReloadIntervalToASwitch` and
`hasMigratedWebsiteReloadOverrides` — in the shape `migrateToPlaylistsIfNeeded` established: the flag
is set before the write, not after it. The flags stay with the callers, where the `Defaults` are;
what is here is the decision, and what a second run would decide is exactly what
`SettingsMigrationTests` runs it against.

**Reading the store rather than the decoded values, which is the whole of why these are here.** A
decoded `Website` cannot tell an absent `reloadInterval` from one that stored the same number the
field now defaults to; the raw record can, because the key is either there or it is not. The stand-ins
below decode only what the decision needs, which also keeps them free of `Website` — so `swift test`
can run this against a real stored payload, the way `PlaylistMigration.swift` is run against a real
website list. `Website`'s own decoding stays synthesised: `WebsiteMigrationTests` exists because a
hand-written `init(from:)` is the shape that empties somebody's list.
*/

/**
One record as an older build wrote it, read for the one field the conversion turns on.

`Defaults` stores an array of `Codable` values as an array of JSON strings, one per element, so this
is what a single element of `playlists` or `websites` deserializes from. Every other field is left
undeclared: a synthesised decoder asks for what it declares and never enumerates what it was given, so
a record with thirty keys in it decodes into these two.
*/
private struct StoredWebsite: Decodable {
	var id: UUID
	var reloadInterval: Double?
}

private struct StoredPlaylist: Decodable {
	var websites: [StoredWebsite]
}

/**
Whether the app-wide reload interval was switched on, decided from the settings actually written to
disk.

- Parameter storedSettings: the app's own persistent domain, and it has to be that rather than
`UserDefaults.object(forKey:)`. A plain read walks the search list, and `Key<Double>(default:)`
registers its default in the registration domain — so `object(forKey: "reloadInterval")` answers with
the default for a user who never set one, and every fresh install would be migrated as though they had
the reload switched on. `RestoreDefaults` reads the domain directly for the neighbouring reason.
- Parameter intervalKey: `Defaults.Keys.reloadInterval.name`, passed rather than written down here so
there is one spelling of it.

An entry under that name means an older build stored a number, which in the old shape was the only way
to be switched on. No entry means off, which is what the key defaults to anyway.

It answers only the switch. The number is never written by the conversion at all — a stored 1800 is a
`Double` on disk under both shapes, so it reads back as itself.
*/
func reloadIntervalSwitch(storedSettings: [String: Any], intervalKey: String) -> Bool {
	storedSettings[intervalKey] != nil
}

/**
The websites that had a reload interval of their own, read out of the records an older build wrote.

- Parameter storedPlaylists: the raw `playlists` entry, one JSON string per playlist.
- Parameter storedWebsites: the raw `websites` entry, one JSON string per website — the list as it
stood before playlists existed.

**The playlists win when there are any, and the reason is that the website list is frozen.**
`websites` is read once by `migrateToPlaylistsIfNeeded` and never written again, so it keeps saying
what it said on the day playlists arrived — including for a website whose override the user has since
switched off. Asking it first would put that override back.

**But it has to be asked at all, because on this build most people are still on the other side of that
migration.** No released version has the `playlists` key, so an upgrading user's records are in
`websites`, and `migrateToPlaylistsIfNeeded` converts them on the same launch — through this build's
`Website`, which is where the distinction is lost. That is what fixes the order at the caller: the raw
store is read before the playlists migration, and the answer is applied after it.

A record that will not decode is left out rather than allowed to throw the rest away. It cannot mean
"this website overrode": there is no website here at all, only a string that is not one.
*/
func websitesOverridingTheReloadInterval(
	storedPlaylists: [String],
	storedWebsites: [String]
) -> Set<UUID> {
	let decoder = JSONDecoder()

	let stored: [StoredWebsite] = storedPlaylists.isEmpty
		? storedWebsites.compactMap { try? decoder.decode(StoredWebsite.self, from: Data($0.utf8)) }
		: storedPlaylists.compactMap { try? decoder.decode(StoredPlaylist.self, from: Data($0.utf8)) }.flatMap(\.websites)

	return Set(stored.filter { $0.reloadInterval != nil }.map(\.id))
}
