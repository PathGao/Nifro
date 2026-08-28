import Foundation
import Testing

/**
The guardrail on "the icon fetch always lets go of its web view".

`WebsiteIconFetcher` waits for a whole page navigation on a `WKWebView` it owns, and the wait is a
checked continuation. Both halves of that are unforgiving. A continuation that is resumed twice traps
the process, and one that is never resumed strands the task that is waiting on it, which strands the
fetcher, the web view and the web content process behind it for as long as the app runs. The page
that does the stranding is not an exotic one here: a live stream or a dashboard that polls forever
loads its main frame and simply never reaches `didFinish`, and `IconView` starts one of these per
row.

Shape rather than behaviour, for the reason `SwitchedOffTests` gives at length. The SwiftPM target
next door compiles nothing from `Sites/WebsiteIconFetcher.swift`, and there is no version of this
that runs without a live `WKWebView` and a window server: the paths worth checking are the ones where
a page never answers at all. What is left that a test can hold is the shape the argument rests on —
one place that resumes, and the two things that reach it when the page does not.
*/
@Suite("An icon fetch cannot strand its web view")
struct IconFetchLifetimeTests {
	private static let fetcher = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "Nifro/Sites/WebsiteIconFetcher.swift")

	/**
	The file with its prose taken out. It argues for itself at length and the argument names the very
	things being looked for.
	*/
	private static func source() throws -> String {
		let block = try Regex("/\\*.*?\\*/", as: AnyRegexOutput.self).dotMatchesNewlines()
		let line = try Regex("//[^\\n]*")

		return try String(contentsOf: fetcher, encoding: .utf8)
			.replacing(block, with: "")
			.replacing(line, with: "")
	}

	@Test("Everything that ends the load ends it in one place")
	func oneResume() throws {
		let source = try Self.source()

		// Five callers, one resume. Counting them is the point: the delegate callbacks used to resume
		// directly, and a second ending arriving from the ceiling or from cancellation would then have
		// been a trap rather than a no-op. A new ending added later has nowhere else to go.
		#expect(
			source.ranges(of: ".resume(").count == 1,
			"A continuation is resumed somewhere other than `end`, so two endings can both get through"
		)
	}

	@Test("A page that never finishes is let go of anyway")
	func theWaitIsBounded() throws {
		let source = try Self.source()

		// The two ways out that do not need the page's cooperation. `withTaskCancellationHandler` is
		// what makes the scrolled-away row release its web view — `withCheckedThrowingContinuation`
		// alone never hears that the task was cancelled — and the sleeping ceiling covers the fetch
		// nobody cancels.
		#expect(source.contains("withTaskCancellationHandler"))
		#expect(source.contains("Task.sleep"))

		// Ending the wait is only half of either one. Both have to stop the page as well, or the load
		// carries on in a web view nothing will ever read.
		#expect(source.ranges(of: "stopLoading()").count == 2)
	}
}
