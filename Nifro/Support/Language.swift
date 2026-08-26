import AppKit
import Defaults

/**
The language the interface is drawn in.

`nil` follows macOS, which is what the app did before there was a choice. Adding a language is one
case here plus its column in `Localizable.xcstrings` — the name shown in the picker is asked of the
system, so there is nothing to write twice and nothing to keep in step.
*/
enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
	case english = "en"
	case simplifiedChinese = "zh-Hans"

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
is the English one.

The cost is a relaunch: `AppleLanguages` is read as the process starts. That is why choosing a
language asks, rather than silently doing nothing until the next launch.
*/
enum Localization {
	private static let key = "AppleLanguages"

	/**
	What the app will be drawn in the next time it starts.
	*/
	static var pending: AppLanguage? {
		(UserDefaults.standard.stringArray(forKey: key)?.first).flatMap(AppLanguage.init)
	}

	/**
	Ask for `language` from the next launch, or hand the choice back to macOS.
	*/
	static func request(_ language: AppLanguage?) {
		guard let language else {
			UserDefaults.standard.removeObject(forKey: key)
			return
		}

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
