// swift-tools-version: 6.0

// This is not how the app is built — the app is the Xcode project next to this file.
//
// It exists so the pure geometry behind cropping and coverage detection can be
// exercised by `swift test` without an Xcode test target, an app bundle, or a
// window server. It reads the same source file the app compiles, so there is
// one implementation, not a copy.

import PackageDescription

let package = Package(
	name: "NifroGeometry",
	platforms: [.macOS(.v15)],
	targets: [
		.target(
			name: "NifroGeometry",
			path: "Nifro",
			sources: ["Support/Geometry.swift", "Support/Schedule.swift"]
		),
		.testTarget(
			name: "NifroGeometryTests",
			dependencies: ["NifroGeometry"],
			path: "Tests/NifroGeometryTests"
		)
	]
)
