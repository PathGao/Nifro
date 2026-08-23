// swift-tools-version: 6.0

// This is not how the app is built — the app is the Xcode project next to this file.
//
// It exists so the pure logic behind cropping, occlusion, scheduling, video embedding and the
// activity classifier can be exercised by `swift test` without an Xcode test target, an app bundle
// or a window server. It reads the same source files the app compiles, so there is one
// implementation and not a copy.

import PackageDescription

let package = Package(
	name: "NifroLogic",
	platforms: [.macOS(.v15)],
	targets: [
		.target(
			name: "NifroLogic",
			path: "Nifro",
			sources: ["Support/Geometry.swift", "Support/Schedule.swift", "Support/VideoEmbed.swift", "Support/PageActivity.swift", "Visibility/Coverage.swift"]
		),
		.testTarget(
			name: "NifroTests",
			dependencies: ["NifroLogic"],
			path: "Tests"
		)
	]
)
