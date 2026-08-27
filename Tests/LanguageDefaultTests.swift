import Foundation
import Testing

/**
The guardrail on "Nifro is in English until you pick something else".

There is no behavioural seam to test this through, and it is worth being plain about why rather than
inventing one. The interface language is not a value the app computes; it is a preference CFBundle
reads once, before `main`, out of a domain belonging to a bundle identifier. Exercising it means a
process with that identifier, a fresh preferences domain and a `.lproj` — an app, in other words.
The SwiftPM target next door compiles nine files out of `Sites` and `Support`, does not include
`Support/Language.swift` (which needs `AppKit`, the `Defaults` package and `SSApp`), and has no
bundle of its own. Nothing here can ask the real mechanism what it did.

So this checks the shape of the three files the mechanism is spread across, and it checks the two
mistakes that actually happened rather than every mistake imaginable.

The first is the bug this replaced. `Localization.pending` read `AppleLanguages` with
`UserDefaults.standard.stringArray(forKey:)`, which walks the search list and falls through to
`NSGlobalDomain` — so on a Mac nobody had ever pointed at Nifro it came back holding the Mac's own
language list, and the picker drew a selection nobody had made. The read looks completely ordinary,
which is the whole problem with it: it is the line anybody would write, and the domain it silently
reaches is invisible at the call site.

The second is the ordering. Writing the default is only worth anything before the first localized
string in the process, because CFBundle resolves the bundle's language on that first lookup and
caches it for good. A call moved out of `AppMain.init()` — into `applicationDidFinishLaunching`, say,
where setup usually goes — still writes the key, still passes every other check, and gives the user
one launch in their Mac's language. There is no assertion that could catch that at runtime either,
so it is caught here, on where the call sits.
*/
@Suite("English is the default, and nothing quietly asks the Mac instead")
struct LanguageDefaultTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func source(_ path: String) throws -> String {
		try String(contentsOf: root.appending(path: path), encoding: .utf8)
	}

	/**
	The same file with its prose taken out.

	These files argue for themselves at length and the arguments quote the very calls the assertions
	look for — `stringArray(forKey:)` is named in `Language.swift` as the thing it does *not* do.
	Matching against the comments would fail on the explanation of why the code is right.
	*/
	private static func stripComments(_ source: String) throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")
		return source.replacing(block, with: "").replacing(line, with: "")
	}

	@Test("The chosen language is read from Nifro's own domain, never through the search list")
	func theLanguageIsReadFromTheAppsOwnDomain() throws {
		let code = try Self.stripComments(Self.source("Nifro/Support/Language.swift"))

		#expect(
			code.contains("UserDefaults.standard.persistentDomain(forName: SSApp.idString)?[key]"),
			"Language.swift no longer reads the choice out of Nifro's own preferences domain"
		)

		// Every shape of the fall-through read. `standard` walks arguments, then Nifro's domain, then
		// `NSGlobalDomain` — so any of these answers with the Mac's languages when Nifro has none, and
		// a caller cannot tell that from a choice.
		for read in ["stringArray(forKey: key)", "array(forKey: key)", "object(forKey: key)", "value(forKey: key)"] {
			#expect(
				!code.contains(read),
				"Language.swift reads AppleLanguages with \(read), which falls through to the Mac's own language list"
			)
		}
	}

	@Test("There is no way back to following the Mac")
	func nothingClearsTheChoice() throws {
		let language = try Self.stripComments(Self.source("Nifro/Support/Language.swift"))
		let settings = try Self.stripComments(Self.source("Nifro/Screens/SettingsScreen.swift"))

		#expect(
			language.contains("static let fallback = Self.english"),
			"The language Nifro falls back to is no longer English"
		)

		// Removing the key hands the language back to `NSGlobalDomain`, which is the state this design
		// does not have. `applyDefaultIfUnset` would put English back on the next launch, so the only
		// thing a removal buys is one launch in the Mac's language.
		#expect(
			!language.contains("removeObject(forKey: key)"),
			"Language.swift can clear the choice again, which puts the Mac's language back for a launch"
		)

		#expect(
			!settings.contains("nil as AppLanguage?"),
			"The picker offers a “follow the system” entry again, which is a state the app does not have"
		)
	}

	@Test("The default is written before anything in the app can ask for a string")
	func theDefaultIsAppliedFirst() throws {
		let code = try Self.stripComments(Self.source("Nifro/App/App.swift"))

		// Inside `init()`, by way of the one thing `init()` calls. Anything later — the delegate's
		// `applicationWillFinishLaunching`, `applicationDidFinishLaunching` — is after windows, menus
		// and every `String(localized:)` they contain, and CFBundle has already decided by then.
		let setUp = try #require(
			code.range(of: "private func setUpConfig() {"),
			"App.swift no longer has the setUpConfig that init calls"
		)

		let initBody = try #require(code.range(of: "init() {"), "AppMain no longer has an init")
		#expect(
			code[initBody.upperBound...].contains("setUpConfig()"),
			"setUpConfig is no longer called from init, so anything it does happens after SwiftUI has drawn"
		)

		let body = code[setUp.upperBound...]
		let call = try #require(
			body.range(of: "Localization.applyDefaultIfUnset()"),
			"Nothing writes the default language, so a Chinese Mac gets a Chinese Nifro nobody asked for"
		)

		let before = body[..<call.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
		#expect(
			before.isEmpty,
			"Something runs before the language is written (“\(before.prefix(80))”). CFBundle caches the language on the first string anything asks for, and there is no second chance."
		)
	}
}
