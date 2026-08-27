import SwiftUI


struct FatalReason: CustomStringConvertible {
	static let notYetImplemented = Self(String(localized: "Not yet implemented."))

	let reason: String

	init(_ reason: String) {
		self.reason = reason
	}

	var description: String { reason }
}


enum SSApp {
	static let idString = Bundle.main.bundleIdentifier!
	static let name = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
	static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
	static let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
	static let versionWithBuild = "\(version) (\(build))"
	static let url = Bundle.main.bundleURL

	@MainActor
	static func quit() {
		NSApp.terminate(nil)
	}

	static let isFirstLaunch: Bool = {
		let key = "SS_hasLaunched"

		if UserDefaults.standard.bool(forKey: key) {
			return false
		}

		UserDefaults.standard.set(true, forKey: key)
		return true
	}()

	static let debugInfo =
		"""
		\(name) \(versionWithBuild) - \(idString)
		macOS \(Device.osVersion)
		\(Device.hardwareModel)
		"""

	static func openSendFeedbackPage() {
		let query: [String: String] = [
			"labels": "bug",
			"body": "\n\n---\n\n\(debugInfo)"
		]

		URL("https://github.com/PathGao/Nifro/issues/new")
			.addingDictionaryAsQuery(query)
			.open()
	}

	@MainActor
	static func activateIfAccessory() {
		guard NSApp.activationPolicy() == .accessory else {
			return
		}

		forceActivate()
	}

//	@MainActor
	static func forceActivate() {
		NSApp.yieldActivation(toApplicationWithBundleIdentifier: idString)
		NSApp.activate()
	}
}

extension SSApp {
	/**
	Manually show the SwiftUI settings window.
	*/
	@MainActor
	static func showSettingsWindow() {
		// Run in the next runloop so it doesn't conflict with SwiftUI if run at startup.
		DispatchQueue.main.async {
			Self.activateIfAccessory()
			EnvironmentValues().openSettings()
		}
	}
}


extension SSApp {
	@MainActor
	static func setUpExternalEventListeners() {
		DistributedNotificationCenter.default.publisher(for: .init("\(Self.idString):showSettings"))
			.sink { _ in
				DispatchQueue.main.async {
					Self.showSettingsWindow()
				}
			}
			.storeForever()

		DistributedNotificationCenter.default.publisher(for: .init("\(Self.idString):openSendFeedback"))
			.sink { _ in
				DispatchQueue.main.async {
					Self.openSendFeedbackPage()
				}
			}
			.storeForever()

		DistributedNotificationCenter.default.publisher(for: .init("\(Self.idString):copyDebugInfo"))
			.sink { _ in
				DispatchQueue.main.async {
					NSPasteboard.general.prepareForNewContents()
					NSPasteboard.general.setString(Self.debugInfo, forType: .string)
				}
			}
			.storeForever()
	}
}


enum Device {
	static let osVersion: String = {
		let os = ProcessInfo.processInfo.operatingSystemVersion
		return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
	}()

	static let hardwareModel: String = {
		var size = 0
		sysctlbyname("hw.model", nil, &size, nil, 0)
		var model = [CChar](repeating: 0, count: size)
		sysctlbyname("hw.model", &model, &size, nil, 0)
		return String(cString: model)
	}()
}


extension SSApp {
	/**
	This is like `SSApp.runOnce()` but let's you have an else-statement too.

	```
	if SSApp.runOnceShouldRun(identifier: "foo") {
		// True only the first time and only once.
	} else {
	}
	```
	*/
	static func runOnceShouldRun(identifier: String) -> Bool {
		let key = "SS_App_runOnce__\(identifier)"

		guard !UserDefaults.standard.bool(forKey: key) else {
			return false
		}

		UserDefaults.standard.set(true, forKey: key)
		return true
	}

	/**
	Run a closure only once ever, even between relaunches of the app.
	*/
	static func runOnce(identifier: String, _ execute: () -> Void) {
		guard runOnceShouldRun(identifier: identifier) else {
			return
		}

		execute()
	}
}


extension Bundle {
	/**
	The first URL scheme this bundle registers.

	Read rather than repeated. The scheme is declared in `Info.plist`, which is what actually makes
	the system route a URL here, so a Swift copy of the string is a second answer that no compiler
	compares against the first. Getting them out of step shows up as the share extension doing
	nothing, with nothing going red.
	*/
	var urlScheme: String? {
		guard
			let types = object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
			let schemes = types.first?["CFBundleURLSchemes"] as? [String]
		else {
			return nil
		}

		return schemes.first
	}
}
