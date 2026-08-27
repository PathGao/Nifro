import Foundation
import Testing

/**
The guardrail on "a page with no media on it is not scanned".

The audio control is injected into every page and every subframe, whatever the website's sound
setting is, because changing the setting has to be a message rather than a reload. Its
`MutationObserver` watches the whole document with `subtree: true`, and its rescan reads the whole
document — so on a live stream, whose chat fires mutations continuously, the cost scaled with the
chat and not with the video. Once per animation frame is the only brake the script had, and once per
frame on a page nobody is clicking is sixty full-document reads a second, per display, for as long as
the wallpaper is up. Pages with no `audio` or `video` element anywhere paid it too.

`sawMedia` is the second brake and it is one word, which is exactly what makes it worth a test: the
gate reads like a redundant condition next to `rescanQueued`, deleting it changes no behaviour anyone
can see, and the cost it prevents is invisible unless somebody is holding a sampler on a stream that
has been up for a day.

Shape rather than behaviour, for the reason `LoadingIndicatorTests` spells out: the script is
JavaScript in a string, injected into `WKWebView` at document start, and the SwiftPM target next door
has no web view and no window server. The assertions match the emitted script text, which is the
contract — the Swift constant holding it can be renamed freely.
*/
@Suite("The audio control does not scan a page that has no media")
struct AudioControlTests {
	private static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	/**
	The file the script is written in, with its prose taken out.

	The comments above the observer argue for the very thing the assertions look for, and name it, so
	matching against them would pass on an explanation with no code under it.
	*/
	private static func source() throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(
			contentsOf: root.appending(path: "Nifro/Support/Extensions.swift"),
			encoding: .utf8
		)
		.replacing(block, with: "")
		.replacing(line, with: "")
	}

	/**
	No rescan is scheduled until something has been claimed.

	Read backwards from the scheduling call rather than by matching the `if` as written, so
	rearranging the condition or renaming `rescanQueued` keeps passing and dropping the gate does not.
	*/
	@Test("The rescan is scheduled only once a media element has been claimed")
	func nothingIsScheduledBeforeTheFirstMediaElement() throws {
		let source = try Self.source()
		let calls = source.ranges(of: "requestAnimationFrame(")

		#expect(!calls.isEmpty, "The audio control no longer schedules a rescan, so this test is reading nothing.")

		for call in calls {
			let start = source.index(call.lowerBound, offsetBy: -240, limitedBy: source.startIndex) ?? source.startIndex

			#expect(
				source[start..<call.lowerBound].contains("sawMedia"),
				"""
				A rescan is scheduled without asking whether this page has ever held a media element. \
				The observer watches the whole document, so an ungated rescan reads every node of \
				every mutating page up to sixty times a second, on pages that have no audio or video \
				in them at all.
				"""
			)
		}
	}

	/**
	And the gate is armed where elements are actually claimed, not on the way in.

	Bounded by the two declarations either side of it rather than by counting braces: the point is
	that the flag is raised by `adopt`, which is the one place an element becomes ours, and not by
	something that runs whether or not the page has media.
	*/
	@Test("Claiming a media element is the only thing that arms the rescan")
	func onlyAdoptingArmsIt() throws {
		let source = try Self.source()

		guard
			let adopt = source.range(of: "const adopt = element => {"),
			let next = source.range(of: "const apply = () => {")
		else {
			Issue.record("The audio script's `adopt`/`apply` pair is no longer written that way.")
			return
		}

		#expect(
			source[adopt.upperBound..<next.lowerBound].contains("sawMedia = true"),
			"`adopt` no longer records that the page has media, so either the gate is stuck shut or something else is opening it."
		)

		#expect(
			source.ranges(of: "sawMedia = true").count == 1,
			"`sawMedia` is set somewhere other than `adopt`. Anything that runs on a page without media turns the gate back into no gate."
		)
	}
}
