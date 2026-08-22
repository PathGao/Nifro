// swift-tools-version: 6.0
import PackageDescription

// 只为本地类型检查存在：把 Xcode 工程的 SPM 依赖编成 .swiftmodule，
// 供 swiftc -typecheck 使用。Xcode 到位后这套东西可以删。
let package = Package(
	name: "TypecheckDeps",
	platforms: [.macOS(.v15)],
	dependencies: [
		.package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.1"),
		.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
		.package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0")
	],
	targets: [
		.target(
			name: "TypecheckDeps",
			dependencies: [
				.product(name: "Defaults", package: "Defaults"),
				.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
				.product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern")
			]
		)
	]
)
