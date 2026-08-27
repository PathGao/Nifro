import Foundation
import Testing

/**
The guardrail on reaching into WebKit by string.

A key-value coding call names an instance variable that no compiler ever checks. It is not a
deprecation and not a warning: the day WebKit renames the ivar, `setValue(_:forKey:)` raises
`NSUnknownKeyException`, and it raises it from `createWebView` — so the failure is not "the inspector
stopped working", it is every wallpaper on every display gone at once, on an OS update nobody in this
repository shipped. Static analysis on the other side of App Review reads these the same way it reads
any other private-API access, and it cannot tell the two cases below apart either.

`developerExtrasEnabled` was one of these for years, against `WKPreferences`. It did not have to be:
Apple's answer to the very report the code linked to was `WKWebView.isInspectable`, public since macOS
13.3, and this app deploys to 15.0. The whole extension came out.

What is left is not a list of code to fix, it is one entry that has no public form, and the point of
this file is that a second one has to argue for itself here before it can compile.
*/
@Suite("WebKit is not reached into by string")
struct PrivateWebKitKeysTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	Every key-value coding key written in the app, with the file it is written in.

	Prose is taken out first, for the reason `ScopeTests` gives: this file argues its case by quoting
	the key it just deleted, and so does the commit that deleted it.
	*/
	private static func keys() throws -> [(file: String, key: String)] {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		// The two NSObject entry points, named rather than approximated by `forKey:` alone, so a
		// dictionary or a `UserDefaults` key is not read as a reach into a system class.
		let getter = try Regex("\\bvalue\\(forKey:\\s*\"([^\"]+)\"")
		let setter = try Regex("\\bsetValue\\([^\n]*?,\\s*forKey:\\s*\"([^\"]+)\"")

		return try FileManager.default
			.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "swift" }
			.sorted { $0.path < $1.path }
			.flatMap { url in
				let text = try String(contentsOf: url, encoding: .utf8)
					.replacing(block, with: "")
					.replacing(line, with: "")

				return (text.matches(of: getter) + text.matches(of: setter))
					.compactMap { $0[1].substring }
					.map { (url.lastPathComponent, String($0)) }
			} ?? []
	}

	/**
	The keys allowed to stay, each with the reason it is allowed.

	`drawsBackground` is the one WebKit still has no public form for. A wallpaper that paints its own
	white behind a transparent page is not a wallpaper, and every public route to it — the
	configuration, the preferences, `underPageBackgroundColor` — leaves the web view's own opaque layer
	in place. The report is https://github.com/feedback-assistant/reports/issues/81, and this line
	should be deleted on the day it is answered, exactly as its neighbour was.

	Nothing else belongs here. A key with a public equivalent is a bug, not an entry.
	*/
	private static let allowed = ["drawsBackground"]

	@Test("Only keys WebKit has no public form for are reached by name")
	func onlyTheUnavoidableKeyRemains() throws {
		for (file, key) in try Self.keys() where !Self.allowed.contains(key) {
			Issue.record(
				"""
				\(file) reaches an instance variable by name: `forKey: "\(key)"`. That is unchecked at \
				compile time and raises `NSUnknownKeyException` if the name ever moves. Use the public \
				API if there is one — `developerExtrasEnabled` had `WKWebView.isInspectable` waiting for \
				it. If there is genuinely none, add the key to `allowed` above with the reason and the \
				report it is waiting on.
				"""
			)
		}
	}
}
