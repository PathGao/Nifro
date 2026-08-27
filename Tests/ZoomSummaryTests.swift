import Foundation
import Testing
@testable import NifroLogic

/**
The guardrail on "a region reads the same wherever it is shown".

There are two surfaces that print a zoom: the Region row in a website's settings and the text a bug
report is copied from. They used to work the number out separately — the row with a `FormatStyle`,
the report with `(scale * 10).rounded() / 10` — and separate arithmetic on one number is the kind of
thing that agrees on the machine it was written on and nowhere else. It did: a `FormatStyle` follows
the system region and interpolating a `Double` never does, so a comma decimal separator gave `2,5×`
in the settings and `2.5×` in the report, off the same stored value.

Two tests, because the defect has two halves. The first is what the shared answer has to say, and it
runs. The second is that nobody works it out a second time, which is an absence and cannot be run —
`Website` is not in the SwiftPM target and there is no settings row to render here — so it is asserted
against the source, and against the arithmetic rather than against the name of the property that
replaced it. A rename is not a regression and must not read as one.
*/
@Suite("A region reads the same wherever it is shown")
struct ZoomSummaryTests {
	@Test("The magnification and the place on the page both survive")
	func whatItSays() {
		let framed: Zoom? = Zoom(center: CGPoint(x: 0.333, y: 0.5), scale: 2.5)
		let text = framed.summaryText

		#expect(text.contains("33%"))
		#expect(text.contains("50%"))

		// One fraction digit, always. Without it a whole magnification prints as `2×` next to a
		// `2.5×`, and — the reason it is pinned here — the two surfaces are only identical for as
		// long as they round the same way.
		let whole: Zoom? = Zoom(center: CGPoint(x: 0.5, y: 0.5), scale: 2)
		#expect(whole.summaryText.contains(2.0.formatted(.number.precision(.fractionLength(1)))))
	}

	@Test("No zoom is a sentence, not an empty line")
	func noZoom() {
		#expect(!Optional<Zoom>.none.summaryText.isEmpty)
	}

	@Test("Nothing works the number out a second time")
	func onlyOneDerivation() throws {
		let root = URL(filePath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()

		for path in ["Nifro/Sites/WebsiteReport.swift", "Nifro/Zoom/WebsiteSettings.swift"] {
			let source = try String(contentsOf: root.appending(path: path), encoding: .utf8)

			#expect(!source.contains("fractionLength"), "\(path) rounds a scale of its own")
			#expect(!source.contains("scale * 10"), "\(path) rounds a scale of its own")
			#expect(!source.contains(".scale)"), "\(path) reads a zoom's scale to print it")
		}
	}
}
