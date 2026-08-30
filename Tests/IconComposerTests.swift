import Foundation
import Testing

/**
The app icon is a compiled product, not a source image loaded by Swift. This guardrail holds the
two project facts together: the Icon Composer source exists in the app target's folder, and both
build configurations select that source by its filename. Without either half, Xcode silently falls
back to the old asset-catalog icon.
*/
@Suite("Nifro Icon Composer source")
struct IconComposerTests {
	private static let repository = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()

	@Test("Both build configurations use the checked-in Nifro icon")
	func usesNifroIconComposerSource() throws {
		let source = Self.repository.appending(path: "Nifro/Nifro.icon/icon.json")
		let project = Self.repository.appending(path: "Nifro.xcodeproj/project.pbxproj")
		let projectSource = try String(contentsOf: project, encoding: .utf8)

		#expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
		#expect(projectSource.ranges(of: "ASSETCATALOG_COMPILER_APPICON_NAME = Nifro;").count == 2)
	}
}
