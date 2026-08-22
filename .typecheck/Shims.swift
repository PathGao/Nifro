// Xcode 会从资源目录自动生成这些符号，swiftc 单独跑时没有。
// 只在类型检查时喂给编译器，不属于 app target。
import AppKit

extension NSImage {
	static let menuBarIcon = NSImage()
}
