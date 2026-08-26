// swift-tools-version: 6.0

// This is not how the app is built — the app is the Xcode project next to this file.
//
// It exists so the pure logic can be exercised by `swift test` without an Xcode test target, an app
// bundle or a window server: the crop and zoom geometry, the menu bar strip, schedule windows, which
// website is current on which display, video embedding, URL commands and menu word wrapping. It reads
// the same source files the app compiles, so there is one implementation and not a copy.

import PackageDescription

let package = Package(
	name: "NifroLogic",
	platforms: [.macOS(.v15)],
	targets: [
		.target(
			name: "NifroLogic",
			path: "Nifro",
			sources: ["Support/DiskBudget.swift", "Support/Geometry.swift", "Support/Rotation.swift", "Support/Schedule.swift", "Support/URLCommand.swift", "Support/VideoEmbed.swift", "Support/Text.swift"]
		),
		.testTarget(
			name: "NifroTests",
			dependencies: ["NifroLogic"],
			path: "Tests"
		)
	]
)
