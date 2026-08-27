import AppKit
import Defaults

/**
The language the interface is drawn in.

Adding a language is one case here plus its column in `Localizable.xcstrings` — the name shown in
the picker is asked of the system, so there is nothing to write twice and nothing to keep in step.
*/
enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
	case english = "en"
	case simplifiedChinese = "zh-Hans"

	/**
	What Nifro is drawn in until somebody picks otherwise.

	Deliberately not the Mac's language — see `Localization` for why the platform's own answer is
	turned down and what it costs to turn it down.
	*/
	static let fallback = Self.english

	var id: String { rawValue }

	/**
	The language's own name in its own script, the way macOS lists them.
	*/
	var displayName: String {
		let locale = Locale(identifier: rawValue)
		let name = locale.localizedString(forIdentifier: rawValue) ?? rawValue

		// Some come back lower-cased — "português (Brasil)" — and only the first letter should rise, by
		// that language's own rule. A no-op for a script with no case, which is most of them.
		guard let first = name.first else {
			return name
		}

		return String(first).uppercased(with: locale) + name.dropFirst()
	}
}

/**
Which language the app's own strings are read in.

`AppleLanguages`, in the app's own defaults, which is the one mechanism that reaches everything:
`String(localized:)`, SwiftUI's `Text`, the AppKit menus, and the strings that come out of packages.
The tidier-looking alternative — swapping the class of `Bundle.main` so string lookup goes to a
chosen `.lproj` — was written and measured, and it does not work: `String(localized:)` resolves
through Foundation's own path rather than `Bundle.localizedString(forKey:)`, so every string stayed
in the system language while the override sat there being ignored.

**English needs no translation to fall back to.** It is the development language, so the keys in the
catalogue are the English text; a string missing from another language comes back as its key, which
is the English one. There is no `en.lproj` in the built app at all — `CFBundleDevelopmentRegion`
puts `en` in `Bundle.main.localizations` next to the one `zh-Hans.lproj` that is really there.

**Nifro does not follow the Mac, and making that true takes a write.** Left alone, CFBundle matches
the Mac's preferred languages against those two and a Chinese Mac gets Chinese — which is the
platform default and not what this app wants. Neither Info.plist key can turn it off:
`CFBundleDevelopmentRegion` is only the last-resort fallback for a Mac that matches nothing, and
`CFBundleLocalizations` is *additive* — it was measured, and setting it to `["en"]` alone leaves
`zh-Hans` in the negotiation and a Chinese Mac still comes up Chinese. The only lever is the
preference itself, so `applyDefaultIfUnset` puts `en` in Nifro's own domain, which sits ahead of
`NSGlobalDomain` in the search list, before anything has asked for a string.

The cost is a relaunch when the choice *changes*: `AppleLanguages` is read once, as the first string
is resolved, and nothing re-reads it. That is why choosing a language asks, rather than silently
doing nothing until the next launch.
*/
enum Localization {
	private static let key = "AppleLanguages"

	/**
	What is written in Nifro's own preferences, or `nil` when nobody has picked yet.

	`persistentDomain(forName:)` rather than `UserDefaults.standard.stringArray(forKey:)`, and the
	difference is the whole of this file. A plain read walks the search list — arguments, then Nifro's
	own domain, then `NSGlobalDomain` — so on a Mac where nobody has opened the picker it comes back
	holding the Mac's own language list, indistinguishable from a choice. That is what the picker used
	to draw: a selection nobody had made. Asking Nifro's domain directly leaves `nil` saying one
	thing.

	The slot rather than a type, for the same reason `RestoreDefaults` reads it that way: what is in
	the key is not always one of ours. The per-app language in System Settings writes regional forms
	such as `zh-Hans-US`, and a restore puts back whatever it found. Both are choices, `nil` is the
	only answer that is not, and narrowing here would turn anything unexpected into "nobody has
	picked" — which `applyDefaultIfUnset` would then overwrite with English.
	*/
	private static var stored: Any? {
		UserDefaults.standard.persistentDomain(forName: SSApp.idString)?[key]
	}

	/**
	What the app will be drawn in the next time it starts.

	Run through the same negotiation CFBundle uses rather than `AppLanguage(rawValue:)`, so the
	regional forms above land on the language they are a form of instead of falling off the end. With
	nothing stored it answers `en`, which is what `applyDefaultIfUnset` is about to write anyway.
	*/
	static var pending: AppLanguage {
		let known = AppLanguage.allCases.map(\.rawValue)
		let best = Bundle.preferredLocalizations(from: known, forPreferences: stored as? [String] ?? []).first
		return best.flatMap(AppLanguage.init) ?? .fallback
	}

	/**
	Make English the answer on a Mac that has never been asked.

	**This has to run before the first localized string in the process.** CFBundle resolves the
	bundle's language once, on the first lookup, and caches it for the life of the app — so this is
	called from `AppMain.init()`, which is ahead of every window, menu and `String(localized:)` in
	this app. Called late it would still write the key, and the user would get one launch in the Mac's
	language before it took: measured, it works from `init()` and that is the only place it is called.

	Writing rather than reading is what makes the rest of the app consistent for free. There is one
	place the interface language lives, the picker reads it back out, and "nothing chosen" is a state
	that only exists on the first launch.
	*/
	static func applyDefaultIfUnset() {
		guard stored == nil else {
			return
		}

		UserDefaults.standard.set([AppLanguage.fallback.rawValue], forKey: key)
	}

	/**
	Ask for `language` from the next launch.
	*/
	static func request(_ language: AppLanguage) {
		UserDefaults.standard.set([language.rawValue], forKey: key)
	}

	/**
	Quit and come back, so the new language is in place.
	*/
	@MainActor
	static func relaunch() {
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.createsNewApplicationInstance = true

		NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
			Task { @MainActor in
				SSApp.quit()
			}
		}
	}
}
