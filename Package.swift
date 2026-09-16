// swift-tools-version: 6.0

// Tests compile the app’s pure logic directly, without an app bundle or window server.

import PackageDescription

let package = Package(
	name: "NifroLogic",
	platforms: [.macOS(.v15)],
	targets: [
		.target(
			name: "NifroLogic",
			path: "Sources/Nifro",
			sources: ["Sites/SiteCatalog.swift", "Sites/SiteCatalog.generated.swift", "Sites/PlaylistCopying.swift", "Support/ImageSampling.swift", "Support/DiskBudget.swift", "Support/Geometry.swift", "Support/UpdateCheck.swift", "Support/Rotation.swift", "Support/RotationInterval.swift", "Support/Schedule.swift", "Support/URLCommand.swift", "Support/VideoEmbed.swift"]
		),
		.testTarget(
			name: "NifroTests",
			dependencies: ["NifroLogic"],
			path: "Tests"
		)
	]
)
