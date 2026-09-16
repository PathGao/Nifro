// swift-tools-version: 6.0

// This is not how the app is built — the app is the Xcode project next to this file.
//
// It exists so the pure logic can be exercised by `swift test` without an Xcode test target, an app
// bundle or a window server: the crop and zoom geometry, the menu bar strip, schedule windows, which
// website is current on which display and how often it changes, video embedding, URL commands, the
// disk budget, the update check and the decoding of the site catalogue. It reads the same source files the app
// compiles, so there is one implementation and not a copy.
//
// Which is the whole point of the `Sites` files below. `sites/index.json` is published and fetched at
// runtime, and it had never once decoded, because nothing in the repository read it through the type
// that reads it in the app. A test can only catch that by running the app's own `SiteCatalog.Entry`
// against the committed file, so `SiteCatalog` is kept free of `Website`, `Defaults` and SwiftUI in
// order to be listed here.
//
// `PlaylistCopying` is listed for a different reason. Duplicating a playlist has to hand back new
// members rather than the ones it was given, and a copy that gets that wrong compiles, draws the
// right rows, and then edits both lists at once. Keeping `withFreshIDs` free of `Website` and
// `Defaults` is what lets that be run here at all.

import PackageDescription

let package = Package(
	name: "NifroLogic",
	platforms: [.macOS(.v15)],
	targets: [
		.target(
			name: "NifroLogic",
			path: "Nifro",
			sources: ["Sites/SiteCatalog.swift", "Sites/SiteCatalog.generated.swift", "Sites/PlaylistCopying.swift", "Support/FullscreenCompatibility.swift", "Support/ImageSampling.swift", "Support/DiskBudget.swift", "Support/Geometry.swift", "Support/UpdateCheck.swift", "Support/Rotation.swift", "Support/RotationInterval.swift", "Support/Schedule.swift", "Support/URLCommand.swift", "Support/VideoEmbed.swift"]
		),
		.testTarget(
			name: "NifroTests",
			dependencies: ["NifroLogic"],
			path: "Tests"
		)
	]
)
