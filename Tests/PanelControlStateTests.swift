import Foundation
import Testing

/**
The panel uses button-shaped toggles for state that is already in effect.  Their colour is the
quick reading of that state, so treating one selected mode or an audible page as unselected makes
the panel contradict itself even though its actions still work.
*/
@Suite("Panel controls show enabled state")
struct PanelControlStateTests {
	private static let repository = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	@Test("The current rotation mode is always highlighted, including Pin")
	func currentRotationModeIsHighlighted() throws {
		let controls = try Self.rotationControls()

		#expect(
			controls.contains("isOn: true"),
			"Pin is a selected rotation mode, so it must be highlighted just like Loop and Random."
		)
	}

	@Test("Sound is highlighted only while it is playing")
	func playingSoundIsHighlighted() throws {
		let controls = try Self.pictureControls()

		#expect(
			controls.contains("isOn: !column.isMuted"),
			"The speaker control must be highlighted when sound is playing and unhighlighted when it is muted."
		)
	}

	private static func rotationControls() throws -> Substring {
		try controls(between: "private var rotationControls: some View", and: "private var modeButtons: some View")
	}

	private static func pictureControls() throws -> Substring {
		try controls(between: "private var preview: some View", and: "private func reading(")
	}

	private static func controls(between start: String, and end: String) throws -> Substring {
		let source = try String(
			contentsOf: repository.appending(path: "Nifro/Screens/DisplayPanel.swift"),
			encoding: .utf8
		)

		guard let range = source.range(of: start)?.lowerBound, let end = source.range(of: end)?.lowerBound else {
			throw CocoaError(.fileReadCorruptFile)
		}

		return source[range..<end]
	}
}
