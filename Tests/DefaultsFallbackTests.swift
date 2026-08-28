import Foundation
import Testing

/**
The guardrail on "falling back to a Settings default with `??` silently falls back to nothing".

`Website.effectiveReloadInterval` was `reloadInterval ?? Defaults[.reloadInterval]`. Both sides are
`Double?`, which reads like the optional fallback everybody writes — but `Defaults[.reloadInterval]`
comes through the package's generic subscript, and that resolves `??` to the `T ?? T` overload with
`T == Double?`. The left side is then not optional, so the right side can never run. The compiler
reports it, as a warning, in a build that also emits SwiftLint's own output.

What that cost: every website that named no reload interval of its own answered `nil`,
`WallpaperScene.resetTimer` returned at its `let reloadInterval =` guard, and no timer was armed. The
number in Settings was drawn, saved, published to every scene — and reached nothing. It survived
because it is not quite inert: turning on a website's own "Reload on its own schedule" seeds that
website's interval from it, so the setting still looked like it worked from the one place anybody
checks it.

The rule and not the instance, because the instance is one line and the shape is what is dangerous.
Any key declared without a `default:` has an optional value type, and any `??` fed from one has the
same dead right side — including the next one somebody writes.

Shape rather than behaviour, for the reason `TimerToleranceTests` and `ScopeTests` spell out: the
SwiftPM target next door compiles eleven pure files out of `Sites` and `Support` and is deliberately
kept free of `Website` and `Defaults`, so there is no `effectiveReloadInterval` here to call. The
keys are read out of `Constants.swift` rather than listed here, so a key added tomorrow is covered
without anybody editing this file.
*/
@Suite("A Settings default is not swallowed by ??")
struct DefaultsFallbackTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	private static func sources() throws -> [(name: String, text: String)] {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try FileManager.default
			.enumerator(at: root.appending(path: "Nifro"), includingPropertiesForKeys: nil)?
			.compactMap { $0 as? URL }
			.filter { $0.pathExtension == "swift" }
			.sorted { $0.path < $1.path }
			.map {
				(
					$0.lastPathComponent,
					try String(contentsOf: $0, encoding: .utf8)
						.replacing(block, with: "")
						.replacing(line, with: "")
				)
			} ?? []
	}

	/**
	The keys whose stored value is itself optional.

	`Key<Double?>` and `Key<String?>` are declared without a `default:` — that is what makes the value
	optional, and it is the whole condition for the trap. A key with a default has a non-optional value
	type and `??` behaves on it the way it reads.
	*/
	private static func optionalKeyNames() throws -> [String] {
		let declaration = try Regex("static let (\\w+) = Key<(.+)>\\(\"", as: AnyRegexOutput.self)
		let text = try String(contentsOf: root.appending(path: "Nifro/App/Constants.swift"), encoding: .utf8)

		return text.matches(of: declaration).compactMap { match in
			guard
				let name = match.output[1].substring,
				let type = match.output[2].substring,
				type.hasSuffix("?")
			else {
				return nil
			}

			return String(name)
		}
	}

	@Test("No optional key is read through ??")
	func noOptionalKeyIsReadThroughNilCoalescing() throws {
		let names = try Self.optionalKeyNames()

		// Not a count anybody has to keep up to date — it only has to stay above the point where this
		// test could pass by matching nothing at all, which is what a change to how keys are declared
		// would look like from here.
		#expect(names.count >= 2, "Found \(names.count) optional `Defaults` keys, which is fewer than this app declares.")

		for file in try Self.sources() {
			for name in names {
				let read = try Regex("\\?\\?\\s*Defaults\\[\\s*\\.\(name)\\b")

				#expect(
					file.text.firstMatch(of: read) == nil,
					"""
					\(file.name) falls back to `Defaults[.\(name)]` with `??`. That key's value is optional, \
					so the generic subscript resolves the operator to `T ?? T` with an optional `T`, the left \
					side stops being optional and the right side never runs. The setting reaches nothing. \
					Use `if let` on the left side and return the key on the other branch.
					"""
				)
			}
		}
	}
}
