import Foundation
import Testing
@testable import NifroLogic

/**
The guardrail on two conversions that can only be made once.

An optional interval where `nil` meant off has become a switch and an always-valid number, in the app
settings and inside every website. The numbers carry themselves across — a stored `1800` is the same
`Double` under both shapes — and the switches cannot, because both of their old answers were "is
there a value stored here" and this build stores one for everybody. Run either conversion against
what it produced and every user reads as though they had turned everything on: reloading switched on
for somebody who never wanted it, every website overriding an interval it was inheriting.

Which makes this the rare thing in this repository that is worth running rather than reading.
`SettingsMigration.swift` holds the whole decision as two functions over plain values, so the payloads
below are real stored ones and the answers are the answers. What is left to the source is the part
that needs `Defaults`: that the flag goes down before the write, that the store is read the one way
that still distinguishes absent from default, and the order of the two conversions against
`migrateToPlaylistsIfNeeded`.

The last of those is the one that would be silent. No released version has the `playlists` key, so on
the launch this build first runs, almost everybody's websites are still in `websites` and
`migrateToPlaylistsIfNeeded` converts them — decoding each record through this build's `Website`,
which carries a reload interval always. Read the store after that and every override is gone, with
the playlists it wrote looking perfectly correct.
*/
@Suite("An interval that meant off becomes a switch without losing the number")
struct SettingsMigrationTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func source(_ path: String) throws -> String {
		let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return text.replacing(block, with: "").replacing(line, with: "")
	}

	private static func body(of declaration: String, in source: String) throws -> String {
		guard
			let start = source.range(of: declaration),
			let open = source[start.upperBound...].firstIndex(of: "{")
		else {
			Issue.record("`\(declaration)` is gone, so this test is reading nothing.")
			return ""
		}

		var depth = 0

		for index in source.indices[open...] {
			if source[index] == "{" {
				depth += 1
			} else if source[index] == "}" {
				depth -= 1

				if depth == 0 {
					return String(source[open...index])
				}
			}
		}

		Issue.record("`\(declaration)` has no closing brace, so this test is reading nothing.")
		return ""
	}

	// MARK: - The app-wide reload interval

	/**
	A stored interval is somebody who had reloading switched on.

	The value beside it is deliberately not asserted, because the conversion cannot reach it: it
	answers a `Bool` and nothing else, and the number is left exactly where an older build wrote it.
	*/
	@Test("An older build's stored interval switches reloading on")
	func aStoredIntervalMeansItWasOn() {
		let stored: [String: Any] = ["reloadInterval": 1800.0, "opacity": 1.0]

		#expect(reloadIntervalSwitch(storedSettings: stored, intervalKey: "reloadInterval") == true)
	}

	/**
	No entry is somebody who had it off, which is what the key defaults to anyway.

	The case this exists to get right is the one underneath it: the new key has a default, so the
	*value* is an hour for this user too, and reading the value instead of the entry would switch
	reloading on for every install that had never touched the setting.
	*/
	@Test("No stored interval leaves reloading off")
	func anAbsentIntervalMeansItWasOff() {
		#expect(reloadIntervalSwitch(storedSettings: ["opacity": 1.0], intervalKey: "reloadInterval") == false)
	}

	/**
	Reading its own output gives the same answer, which is what makes the settings half safe.

	This one is idempotent on its own: the conversion never writes `reloadInterval`, so a second pass
	sees exactly the store the first pass saw. The flag is asserted below all the same, because "runs
	once" is a property worth holding whether or not today's decision happens to be repeatable — and
	the website half below is not.
	*/
	@Test("A second pass over what the first pass left decides the same thing")
	func theSettingsConversionRepeats() {
		var stored: [String: Any] = ["reloadInterval": 1800.0]
		let first = reloadIntervalSwitch(storedSettings: stored, intervalKey: "reloadInterval")

		// What the conversion writes, written back into the store it read.
		stored["reloadOnInterval"] = first
		stored["hasMigratedReloadIntervalToASwitch"] = true

		#expect(reloadIntervalSwitch(storedSettings: stored, intervalKey: "reloadInterval") == first)
	}

	/**
	The store is asked the one way that still tells an absent entry from a defaulted one.

	`Key<Double>("reloadInterval", default: 60 * 60)` registers its default with `UserDefaults`, and
	`object(forKey:)` walks the search list — so it answers with that default for a user who never set
	one, and the conversion would switch reloading on for every fresh install. The persistent domain
	holds only what was actually written. `RestoreDefaults` reads it the same way for the neighbouring
	reason and says so at length.

	Asserted on `Foundation`'s own two names, so nothing this repository could rename turns it red
	without the behaviour changing with it.
	*/
	@Test("The conversion reads what was written, not what the key defaults to")
	func theStoreIsReadThroughItsPersistentDomain() throws {
		let state = try Self.source("Nifro/App/AppState.swift")
		let migration = try Self.body(of: "private func migrateReloadIntervalToASwitch()", in: state)

		#expect(!migration.isEmpty)

		#expect(
			migration.contains("persistentDomain(forName:"),
			"The reload conversion no longer reads the app's own persistent domain. `object(forKey:)` finds the key's registered default, so every install that never set an interval is migrated as though it had reloading switched on."
		)

		#expect(
			!migration.contains("object(forKey:"),
			"The reload conversion asks `UserDefaults` for the value through the search list, which includes the registered default it is trying to tell apart from a stored one."
		)
	}

	// MARK: - The per-website override

	/**
	One playlist as `Defaults` stores it: an array holding one JSON string per playlist.

	Cut down to the fields the decision reads, with a spare key left in each website so that the
	stand-in in `SettingsMigration.swift` is exercised against a record wider than itself — which every
	real record is.
	*/
	private static func storedPlaylist(_ websites: String...) -> [String] {
		[#"{"id":"3F27B0F0-0000-4000-8000-000000000001","isDefault":true,"name":"Default","websites":[\#(websites.joined(separator: ","))]}"#]
	}

	private static let overriding = UUID(uuidString: "A0000000-0000-4000-8000-00000000000A")!
	private static let inheriting = UUID(uuidString: "B0000000-0000-4000-8000-00000000000B")!
	private static let atTheDefault = UUID(uuidString: "C0000000-0000-4000-8000-00000000000C")!

	private static func record(_ id: UUID, reloadInterval: Double?) -> String {
		let interval = reloadInterval.map { #""reloadInterval":\#($0),"# } ?? ""
		return #"{"allowsInteraction":false,"id":"\#(id.uuidString)",\#(interval)"title":"","url":"https://example.com","usePrintStyles":false}"#
	}

	@Test("A website that stored an interval of its own comes back overriding")
	func aStoredIntervalIsAnOverride() {
		let stored = Self.storedPlaylist(
			Self.record(Self.overriding, reloadInterval: 1800),
			Self.record(Self.inheriting, reloadInterval: nil)
		)

		let result = websitesOverridingTheReloadInterval(storedPlaylists: stored, storedWebsites: [])

		#expect(result == [Self.overriding])
	}

	/**
	The case the raw read exists for.

	`Website.reloadInterval` is no longer optional and defaults to an hour, so a record that stored
	exactly an hour and a record that stored nothing decode into the same number. Only the record can
	tell them apart, and only before this build has written one back. If this comes back inheriting,
	the conversion is reading decoded values and the approach is wrong.
	*/
	@Test("A stored interval equal to the new default is still an override")
	func anIntervalEqualToTheDefaultIsStillAnOverride() {
		let stored = Self.storedPlaylist(
			Self.record(Self.atTheDefault, reloadInterval: 60 * 60),
			Self.record(Self.inheriting, reloadInterval: nil)
		)

		let result = websitesOverridingTheReloadInterval(storedPlaylists: stored, storedWebsites: [])

		#expect(result == [Self.atTheDefault])
	}

	/**
	Before playlists, the records are in `websites`, and that is where nearly everybody is.

	No released version has the `playlists` key, so this is not the historical branch — it is the one
	the upgrade actually takes.
	*/
	@Test("A list stored before playlists is read from the key it is in")
	func thePrePlaylistListIsRead() {
		let result = websitesOverridingTheReloadInterval(
			storedPlaylists: [],
			storedWebsites: [
				Self.record(Self.overriding, reloadInterval: 900),
				Self.record(Self.inheriting, reloadInterval: nil)
			]
		)

		#expect(result == [Self.overriding])
	}

	/**
	The playlists win when there are any, because the website list is frozen and can be out of date.

	`websites` is never written again after the playlists migration reads it, so it goes on saying a
	website overrode long after the user switched that override off. Asked first, it would put the
	override back.
	*/
	@Test("The frozen website list does not override what the playlists say")
	func theLiveRecordsWin() {
		let result = websitesOverridingTheReloadInterval(
			storedPlaylists: Self.storedPlaylist(Self.record(Self.inheriting, reloadInterval: nil)),
			storedWebsites: [Self.record(Self.inheriting, reloadInterval: 1800)]
		)

		#expect(result.isEmpty)
	}

	/**
	Why the website half must never run twice, run rather than argued.

	A record this build has written carries a `reloadInterval` whether or not the website overrides,
	because the field is no longer optional. Fed that, the conversion answers that every website
	overrides — a wrong answer that looks entirely plausible, and the one a user would get if the flag
	guarding it were ever cleared or forgotten. Nothing about the decision itself can prevent that;
	only the flag can, which is why the flag is asserted below and why `RestoreDefaults` preserves it.
	*/
	@Test("A second pass over what this build writes would mark every website as overriding")
	func theWebsiteConversionMustNotRunTwice() {
		let alreadyMigrated = Self.storedPlaylist(
			#"{"id":"\#(Self.overriding.uuidString)","overridesReloadInterval":true,"reloadInterval":1800,"url":"https://example.com","usePrintStyles":false}"#,
			#"{"id":"\#(Self.inheriting.uuidString)","overridesReloadInterval":false,"reloadInterval":3600,"url":"https://example.com","usePrintStyles":false}"#
		)

		#expect(websitesOverridingTheReloadInterval(storedPlaylists: alreadyMigrated, storedWebsites: []) == [Self.overriding, Self.inheriting])
	}

	/**
	A record that will not decode is skipped rather than taking the rest with it.

	It cannot mean "this website overrode" — there is no website there at all — and a conversion that
	threw would leave every other website in the list unconverted.
	*/
	@Test("An unreadable record loses only itself")
	func rubbishIsSkipped() {
		let result = websitesOverridingTheReloadInterval(
			storedPlaylists: [],
			storedWebsites: ["not json", Self.record(Self.overriding, reloadInterval: 600)]
		)

		#expect(result == [Self.overriding])
	}

	// MARK: - What only the source can say

	/**
	The store is read before the playlists migration and applied after it.

	Both halves matter and each fails on its own. Read afterwards, the raw records have already been
	rewritten by this build and every website reads as overriding. Applied before, there is nothing to
	apply it to — a pre-playlists user's websites are not in `playlists` yet, and that is the state
	every upgrading user is in, since no released version has the key.
	*/
	@Test("The raw read comes before the playlists migration and the write comes after it")
	func theOrderAgainstThePlaylistsMigrationHolds() throws {
		let controller = try Self.source("Nifro/Sites/WebsitesController.swift")
		let prepare = try Self.body(of: "func prepareWebsiteStorage()", in: controller)

		guard
			let read = prepare.range(of: "websitesOverridingTheReloadInterval("),
			let playlists = prepare.range(of: "migrateToPlaylistsIfNeeded()"),
			let write = prepare.range(of: "markWebsitesOverridingTheReloadInterval(")
		else {
			Issue.record("`prepareWebsiteStorage` no longer runs all three, so this test is reading nothing.")
			return
		}

		#expect(
			read.lowerBound < playlists.lowerBound,
			"The stored records are read after `migrateToPlaylistsIfNeeded` has rewritten them, so every website comes back overriding an interval it was inheriting."
		)

		#expect(
			write.lowerBound > playlists.lowerBound,
			"The overrides are applied to `playlists` before the playlists exist, so an upgrading user's websites are never marked at all."
		)
	}

	/**
	Both conversions record that they ran before they write anything.

	The shape `migrateToPlaylistsIfNeeded` established, and the reason is the same: a conversion that
	sets its flag afterwards runs again if anything between the two goes wrong, and running either of
	these twice is what this whole suite is about.
	*/
	@Test("Each conversion sets its flag before it writes")
	func theFlagGoesDownFirst() throws {
		let sites = [
			("Nifro/App/AppState.swift", "private func migrateReloadIntervalToASwitch()", "hasMigratedReloadIntervalToASwitch", "reloadOnInterval"),
			("Nifro/Sites/WebsitesController.swift", "private func markWebsitesOverridingTheReloadInterval(_ overriding: Set<Website.ID>)", "hasMigratedWebsiteReloadOverrides", "playlists")
		]

		for (file, declaration, flag, written) in sites {
			let body = try Self.body(of: declaration, in: try Self.source(file))

			#expect(
				body.contains("guard !Defaults[.\(flag)]"),
				"`\(declaration)` no longer returns early on its own flag, so it runs on every launch."
			)

			guard
				let setsFlag = body.range(of: "Defaults[.\(flag)] = true"),
				let writes = body.range(of: "Defaults[.\(written)] =")
			else {
				Issue.record("`\(declaration)` no longer sets `\(flag)` and writes `\(written)`, so this test is reading nothing.")
				continue
			}

			#expect(
				setsFlag.lowerBound < writes.lowerBound,
				"`\(declaration)` writes `\(written)` before recording that it ran, so anything that interrupts it leaves the conversion to run a second time."
			)
		}
	}

	/**
	A website with no override of its own follows the app-wide pair, and follows both halves of it.

	The switch is the half that is easy to drop: read only the number and every website that inherits
	reloads on an hour the user switched off. `effectiveReloadInterval` returns `nil` for that case and
	`WallpaperScene.resetTimer` arms no timer on `nil`.
	*/
	@Test("An inheriting website reads both halves of the app-wide setting")
	func inheritingFollowsTheSwitchAsWellAsTheNumber() throws {
		let body = try Self.body(
			of: "var effectiveReloadInterval: Double?",
			in: try Self.source("Nifro/Sites/Website.swift")
		)

		#expect(body.contains("overridesReloadInterval"), "`effectiveReloadInterval` no longer asks whether this website overrides.")
		#expect(body.contains("Defaults[.reloadOnInterval]"), "A website that inherits no longer asks whether the app-wide reload is switched on, so it reloads on a number nobody turned on.")
		#expect(body.contains("Defaults[.reloadInterval]"), "A website that inherits no longer reads the app-wide number.")
	}
}
