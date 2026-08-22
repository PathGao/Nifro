# 清理候选分析（只读，未改动任何代码）

范围：`Nifro/` 全部 41 个 Swift 文件（10,766 行，含 Tests 与 ShareExtension）。
工具：`periphery scan --quiet`、`xcodebuild build`、`swift test`、`graphify`（已装，未用，理由见 Verified）、
自写的引用普查脚本（跨文件符号计数 + 传递可达闭包）。

**先给结论**：过闸门的净减约 **150 行**，占全仓 1.4%、占 `Extensions.swift` 的 3.9%。
你想要的「大幅度简化」在这个仓库里拿不到 —— 不是因为没有肥肉，而是因为肥肉都在
「只服务一个调用点的 200 行上游子系统」那一类里，而那一类全部被 N1/N2 拦下（详见 Not done 的 R 组）。
**最值钱的三条在文末。**

---

## Done 的候选（通过闸门，建议执行）

### D1 · 删掉 5 个 Support 文件里用不到的 import · W1 · 净减 47 行

`E6 拆 Utilities.swift` 那一刀（commit `45f7c0f`）把同一段 13 行 import 块原样复制进了 5 个新文件：

```
Extensions.swift    13 行 ┐
MenuSupport.swift   13 行 │  IOKit.ps / IOKit.pwr_mgt / WebKit / SwiftUI / Combine /
Display.swift       13 行 ├─ Network / SystemConfiguration / CryptoKit / StoreKit /
AppInfo.swift       13 行 │  UniformTypeIdentifiers / LinkPresentation / Defaults / os
SystemEvents.swift  13 行 ┘  —— 五份逐字相同
```

对照：我们自己写的 36 个文件，每个 1–3 行 import。全仓 118 行 import 里有 65 行在这 5 个文件。

按模块特征符号扫描（`WK*`、`NW*`、`LP*`、`SHA256`、`UTType`、`IOPS*`、`Logger` 等）统计每个文件实际用到的模块：

| 文件 | 现有 | 有符号命中 | 可删 |
|---|---|---|---|
| Extensions.swift | 13 | WebKit(83) SwiftUI(156) Combine(16) CryptoKit(1) UniformTypeIdentifiers(1) LinkPresentation(5) Defaults(12) | **6** |
| MenuSupport.swift | 13 | 0（只用 NSMenu/NSMenuItem/NSEvent/objc_*，需要 AppKit） | **12**（13 → `import AppKit`） |
| Display.swift | 13 | Combine(2) Defaults(2) + NSScreen | **10** |
| AppInfo.swift | 13 | SwiftUI(1) + NSApp/NSPasteboard + `.sink` | **10** |
| SystemEvents.swift | 13 | IOKit.ps(9) IOKit.pwr_mgt(3) Combine(7) | **9** |

- 闸门 1：import 是纯冗余，不是换说法。**过**
- 闸门 2：删多了 `xcodebuild build -scheme Nifro` 直接 `cannot find 'X' in scope` 失败。这是项目已有的验证命令，不是「能编译」的托词——它是唯一的判据，而且逐行精确。**过**
- 闸门 3：import 不可能被动态引用（不存在按名字构造的模块导入）。零引用就是零引用。**过**
- ⚠ 表格里「有符号命中」是**推理**（正则扫符号前缀），不是观测。删除必须一次删一行、跑一次编译，别按表格批量删。

### D2 · 删掉 23 个空的 extension 块 · W1 · 净减 63 行

前三轮死代码清理把成员删干净了，壳留在原地：

```
Nifro/Support/Extensions.swift   20 处   （Collection ×2, Data, Font, KeyedDecodingContainer,
                                          Numeric, ObjectAssociation, RangeReplaceableCollection,
                                          Sequence, String, Timer, URL, UUID, View ×8）
Nifro/Support/MenuSupport.swift   1 处   extension NSMenuItem {}     L234-235
Nifro/Support/AppInfo.swift       1 处   extension SSApp {}          L185-187
Nifro/Support/Extensions.swift 之外还有  extension CharacterSet 等
```

最典型的一处，`Extensions.swift:600-603`：

```swift
// MARK: - Data
extension Data {          // ← 601-602，空壳
}
extension Data {          // ← 603，真正有内容的那份
	struct HexEncodingOptions: OptionSet { ... }
```

数字：23 个块 = 54 行块体 + 9 行紧随其后的空行 = **63 行**。

- 闸门 1：空块声明零个符号，删它是拿掉没有价值的东西。**过**
- 闸门 2：若误删了相邻的**非空** extension，`xcodebuild` 立刻红（成员找不到）。**过**
- 闸门 3：空 extension 没有成员，不存在任何运行时可达路径。**过**

### D3 · 删 `NonInteractiveView` · W1（孤儿副本） · 净减 8 行

`Nifro/Support/Extensions.swift:3042-3049`

```swift
/**
A view that doesn't accept any mouse events.
*/
class NonInteractiveView: NSView {
	override var mouseDownCanMoveWindow: Bool { true }
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
	override func hitTest(_ point: CGPoint) -> NSView? { nil }
}
```

- 数字：全仓 `NonInteractiveView` 出现 **1 次**（就是这行声明）。`mouseDownCanMoveWindow` 同样 1 次。
  这是全仓唯一一个「只出现在自己声明处」的类型（`Intents.swift` 的 App Intent、各 delegate 回调、
  `Tests/` 的 21 个 `@Test` 也在这个名单里，但它们全部被框架按名字调用 —— 见 Not done N4 组）。
- **这就是「陈旧副本」最值钱的形态**：活着的那份是 `Visibility/MenuBarBand.swift:27`
  的 `MenuBarBandView.hitTest → nil`，它带着注释解释为什么必须吞掉点击。
  留着这个躯壳，下一个要做「不吃鼠标事件的视图」的人会复用它 —— 然后拿到一个
  `acceptsFirstMouse: false` 的版本，而 `SSWebView:4` 和 `CropSelectionView` 都明确要 `true`。
- 闸门 1：无调用者的类型，纯删。**过**
- 闸门 2：`xcodebuild` 会红（如果它其实被引用了）。项目**没有任何 .xib / .storyboard**
  （`find . -name "*.xib" -o -name "*.storyboard"` → 空），所以不存在 IB 按类名实例化的路径。**过**
- 闸门 3：非 `@objc`，无 `#selector`，无 App Intent，无 Defaults 键。零引用在这里是真证据。**过**

### D4 · 删 `AppState.applyOpacity`，唯一调用点改指 `primaryScene` · W1（陈旧副本） · 净减 17 行

`Nifro/Visibility/DimWhenUnfocused.swift:37-53` 与 `Nifro/Wallpaper/WallpaperScene.swift:236-253`
是同一个函数，`diff` 之后只差变量名：

```
AppState 版                         WallpaperScene 版
  let target = targetOpacity          let target = AppState.shared.targetOpacity
  desktopWindow.alphaValue            window.alphaValue
  desktopWindow.animator()            window.animator()
```

而 `AppState.desktopWindow` 的定义就是 `primaryScene.window`（`AppState.swift:42`）。
两者在 primary scene 上**逐字等价**。

git 证据：`git log -S "func applyOpacity"` → 两份都在 `8b989db`（R1 场景化 + F3 多显示器）。
那次搬迁把实现搬进了 `WallpaperScene` 并让它**按 scene 逐个生效**，AppState 的旧壳留在原地。

- 调用点数：`AppState.applyOpacity` 只剩 **1 个**（`Crop/CropSelection.swift:51`）。
  另外 5 处（`AppState.swift:53,187`、`Events.swift:118,126,134,142`）都是 `scene.applyOpacity()`。
- 建议动作：删 17 行，把 `CropSelection.swift:51` 改成 `primaryScene.applyOpacity(animated: false)`。
- 闸门 1：删完全相同的重复。**过**
- 闸门 2：⚠ **这条最弱**。红的只有 `xcodebuild`（删掉后调用点符号不存在），
  没有任何测试守 opacity —— `swift test` 只覆盖 `Geometry.swift` + `Schedule.swift`。
  我之所以仍然放进 Done：目标表达式 `primaryScene.applyOpacity` 与被删的 body 在
  **类型层面可证同一**（`desktopWindow` 就是 `primaryScene.window`），所以「改错」这个可能性本身不成立。
  如果你要更保守，把它降级到 Not done 是合理的。
- 闸门 3：普通 Swift 方法，无动态路径。**过**
- 顺带（不在本次动作范围内）：多显示器下 `AppState.applyOpacity` 只恢复主 scene 的透明度，
  其余 scene 不动 —— 这是个真 bug，但修它是行为改动，不是清理。

### D5 · 删 `AppState.handleAppReopen()` · W3（纯转发） · 净减 4 行

`Nifro/App/AppState.swift:151-153`

```swift
func handleAppReopen() {
	handleMenuBarIcon()
}
```

- 调用点数：**1 个**（`App.swift:66`，在 `applicationShouldHandleReopen` 里）。
  N3 说「≥2 个调用点说明它是单一事实来源」—— 这里是 1，不适用。
- `handleMenuBarIcon` 本身有 3 个调用点（`AppState.swift:152`、`Events.swift:111`、`SSWebView.swift:117`），
  即真正的单一事实来源是 `handleMenuBarIcon`，这层只是别名。
- 闸门 2：`xcodebuild`（`App.swift:66` 直接引用它）。**过** ／ 闸门 1、3 同 D3。**过**

### D6 · 删 `WallpaperScene.adoptWebView(_:)` · W3（纯转发） · 净减 4 行

`Nifro/Wallpaper/WallpaperScene.swift:122-124` → `webViewController.adopt(replacement)`

- 调用点数：**1 个**（`SwapLoading.swift:81`，本身就在 `extension WallpaperScene` 里，
  同一个文件里已经在直接用 `webViewController.*`）。
- 对照 `recreateWebView()`（117-120）和 `releaseWebView()`（129-137）：这两个**不是**纯转发
  （前者多一次 `installContentView()`，后者还清了 `pendingLoad` / `frozenView` / `cropRect`），
  所以只动 `adoptWebView` 这一个。
- 闸门 1、2、3 同 D5。**过**

### D7 · 收窄可见性 · W2 · 净减 0 行，导出面减少约 113 个符号

统计口径：**成员级**（缩进 ≤1 tab）、当前是 `internal`（无显式修饰符）、
排除 `override` 与已知框架要求名，**跨文件引用数为 0 且本文件内引用 ≥1**：

```
Nifro/Support/Extensions.swift          83
Nifro/Support/AppInfo.swift              6   （debugInfo, Device, osVersion, hardwareModel, runOnceShouldRun …）
Nifro/Support/Display.swift              5   （uuidFromID, hasStatusBar, statusBarThickness …）
Nifro/Sites/Playlist.swift               5   （isScheduled, eligible, advance, scheduled, advancePlaylist）
Nifro/App/Intents.swift                  5
Nifro/Sites/WebsitesController.swift     3
其余 12 个文件各 1–2                     ~16
────────────────────────────────────────────
                                       ~113（脚本报 129，扣掉约 16 个落在函数体内的局部 let 误判）
```

具体几条已手工核实：
`VisibilityPolicy.isVisibilityManagementEnabled`（2 处，同文件）、
`MenuBarBand.shouldShowMenuBarBand`（2 处，同文件）、
`DimWhenUnfocused.isDesktopFocused`（1 处）、`CropSelection.isSelectingCrop`（1 处）、
`SSWebView.zoomLevelDefaultsValue`（1 处）、`AppInfo.runOnceShouldRun`（1 处，`runOnce` 才是对外的）。

- 闸门 1：这是**收窄而不是删除**（W2 明列为免费的赢），不是把手写循环改成正则那种改写。**过**
- 闸门 2：收窄错了 `xcodebuild` 直接红（`is inaccessible due to 'private' protection level`），
  逐个符号精确定位。**过**
- 闸门 3：extension 成员非 `@objc` 时没有运行时按名访问路径。**过**
- ⚠ 已确认**不能**收窄的（别一把梭）：
  `SimpleImageCacheKeyable`（是 internal 泛型 `SimpleImageCache` 的约束）、
  `DecodableDefaultSource`（`Website.swift:128,132` 通过 `DecodableDefault.Source` 别名遵从）、
  `Display.Bridge` / `bridge`（Defaults 库按协议要求取）。
- 价值不在行数，在于：收窄之后 `.periphery.yml` 里 `retain_public: true` 的遮蔽面变小，
  下一轮扫描才能看见文件内部新长出来的死代码。

---

**Done 合计：净减约 143–150 行（D1 47 + D2 63 + D3 8 + D4 17 + D5 4 + D6 4，D7 计 0）。**

---

## Not done（拦下，记录但不动）

### R 组 —— 「200 行子系统只服务 1 个调用点」

这一组是全仓最大的一块肥肉（合计约 600 行，占 `Extensions.swift` 的 16%），全部拦下。

| | 候选 | 规模 | 外部调用点 | 拦下理由 |
|---|---|---|---|---|
| R1 | `SecurityScopedBookmarkManager`（`Extensions.swift:3054-3230`） | 176 行 | **1**（`AddWebsiteScreen.swift:346`） | **N1/N2**。换成直接 `URL.bookmarkData(options:.withSecurityScope)` 是等价改写，而且它守的是沙盒文件访问 —— 属于「信任边界上的输入校验」，永不简化。代码里还留着 `// TODO: I plan to extract this into a Swift Package`，是上游的意图不是我们的 |
| R2 | `SimpleImageCache` + `Cache` + 磁盘缓存（`3234-3505`） | 约 270 行 | **3**（`WebsitesController.swift:15,49`、`SettingsScreen.swift` 的 `removeAllImages`） | **N1**。换成 `NSCache` + `URLCache` 是重写，没有任何检查能证明缓存键、prewarm 顺序、磁盘落盘时机保持不变 |
| R3 | `WebsiteIconFetcher`（`3545-3745`） | 约 200 行 | **1**（`WebsitesScreen.swift:179`） | **N1/N2**。解析 web app manifest + 挑最大图标的逻辑没有框架替代品；`LPMetadataProvider` 拿不到同样的东西（`WebsitesController.swift:190` 的注释已经解释过为什么） |

数字的含义：删掉这三块能减 646 行，但每一块都要重写调用点，而**没有一条测试会红**。

### N1 —— 等价改写

| | 候选 | 数据 |
|---|---|---|
| N1a | `Duration.nanoseconds` + `toTimeInterval`（`765-774`，10 行）改成 `duration.components` 直算 | 1 个使用点（`delay()` L2727）。换个说法而已 |
| N1b | `targetDisplay?.screen ?? .main` 出现 **3 次**（`CropSelection.swift:15`、`DesktopWindow.swift:98`、`WallpaperScene.swift:86`） | 是「同一个表达式抄了 3 份」，但收口需要决定收到哪儿（scene 上已有 `screen`），是设计改动不是清理 |
| N1c | `SSWebView.zoomLevelDefaultsValue`（159-168，10 行）压成 `zoomLevelDefaultsKey.flatMap { Defaults[$0] }` | 1 行换 10 行，但语义完全一样，纯改写。（它的 W2 收窄部分已计入 D7） |
| N1d | `Data.hexEncodedString` / `String.sha256` 用标准库替代 | 标准库没有等价物；`hexEncodedString` 的 `unsafeUninitializedCapacity` 版本是有意的 |

### N2 —— 没有检查能抓住

| | 候选 | 数据 |
|---|---|---|
| N2a | 删 `CallbackMenuItem.validateCallback` + `NSMenuItemValidation` 一致性（`MenuSupport.swift:47` + `88-92`，共 6 行） | `validateCallback` 全仓 **2 次出现：1 次声明 + 1 次读取，零写入点**，所以 `validateMenuItem` 恒返回 `true`。但删掉一致性之后 AppKit 会回退到「target 是否响应 action」的默认验证 —— 在 `SSWebView.willOpenMenu` 里加的菜单项走的是 WebKit 给的 `NSMenu`（`autoenablesItems` 默认 true），行为等价性**只能靠推理**，没有菜单测试。**这是本次最接近通过又被拦下的一条** |
| N2b | `AppState.applyOpacity` 顺带修成对所有 scene 生效 | 是真 bug 修复不是清理，且没有多显示器测试 |

### N3 —— 先数调用点，≥2

| | 候选 | 调用点 |
|---|---|---|
| N3a | `WebViewController.makeReplacementWebView()`（112-114）纯转发到 private 的 `createWebView()` | **2**（`SwapLoading.swift:45`、`SnapshotBackend.swift:89`）。它是 private 实现的对外面孔，就是单一事实来源 |
| N3b | `AppState.toggleBrowsingMode()`（220-222）body 只有 `Defaults[.isBrowsingMode].toggle()` | **2**（`Intents.swift:213`、`URLCommands.swift:46`）。顺带记录：另有 2 处**内联**了同一表达式（`Events.swift:189`、`Menus.swift:81`），4 处答同一个问题而没有东西要求它们一致 —— 统一它们是改写，不是清理 |
| N3c | `AppState.resetTimer` / `installContentView` / `reloadWebsite` / `recreateWebViewAndReload` | 各 2–4 个调用点，且 body 是 `for scene in scenes` 扇出，不是转发 |

### N4 —— 「扫描说零引用所以是死的」

这一组占了我自建可达图报的全部 39 个「dead」候选中的 34 个。全部**不是**死代码：

| | 被误判的东西 | 真正的调用者 |
|---|---|---|
| N4a | `Intents.swift` 的 11 个 `AppIntent` 结构体 + `WebsiteAppEntity.Query` | 系统按 Shortcuts 元数据实例化。`.periphery.yml` 已 `report_exclude` 掉，但我的脚本没有 |
| N4b | `makeNSView` / `updateNSView` / `makeCoordinator` / `NSViewType`（`CocoaButton`、`ScrollableTextView`、`WindowAccessor`、`OnDoubleClickRepresentable`） | `NSViewRepresentable` 协议要求，SwiftUI 调 |
| N4c | `extension Display: Defaults.Serializable` 的 `Bridge` / `bridge`（`Display.swift:185-204`，20 行） | Defaults 库按协议要求取 |
| N4d | `extension CallbackMenuItem: NSMenuItemValidation`（`MenuSupport.swift:88-92`） | AppKit 调 |
| N4e | `OcclusionMonitor.timer`、`MenuSupport.swift:83,247` 的 `sender`、`SystemEvents.swift:119` 的 `replyEvent` | **Periphery 本轮唯一的 4 条输出**，`.periphery.yml` 已逐条写明为什么不是死的（`timer` 不被持有就不会触发；后三个是 `#selector` 签名要求的参数）。这是项目本地约定，不动 |
| N4f | `ScrollRestoration.scrollPositionKey`（`"scrollPosition_" + base64(url)`）与 `SSWebView.zoomLevelDefaultsKey`（`"zoomLevel_" + base64(url)`） | **动态构造的 Defaults 键**。任何关于「这些 UserDefaults 键没人引用」的静态结论都无效，闸门 3 直接否 |
| N4g | `ControlActionClosureProtocol.onAction` 经 `objc_setAssociatedObject` + `#selector(ActionTrampoline.handleAction)` 派发 | 跨语言（ObjC runtime）调用，静态图看不见 |

### N5 —— 引入抽象的去重

| | 候选 | 数据 |
|---|---|---|
| N5a | `VisibilityPolicy.installFrozenView`（156-166）与 `SnapshotBackend.showSnapshot`（105-117）共有 4 行 `NSImageView` 构造（`contentLayoutRect` + `.scaleAxesIndependently` + `[.width,.height]`） | 重复只有 4 行，两边周围的状态赋值不同（一个清 `renderedRegion`，一个还要 `installMenuBarBandIfNeeded`）。抽出来要新建一个函数，净增复杂度 |
| N5b | `Menus.swift:62-74` 与 `SSWebView.swift:94-106` 的 "Update Website to Current"（各 13 行，逐字相同） | 代码里已有 `// TODO: DRY this up with the one in SSWebView when everything is in SwiftUI` —— 上游自己标了。收口要么建一个共享 builder（新抽象），要么等 SwiftUI 迁移。**这是全仓最实的一处逻辑重复，但它属于 N5** |
| N5c | 5 个 Support 文件那份重复的 import 块本身 | 「统一」它（做共享 header 之类）是 N5/N6；**只删各文件用不到的那几行**才是 D1，两者不是一回事 |

### N6 / N7

- **N6a**：`Extensions.swift` 里有 13 处连续空行（>2 行）、`MenuSupport.swift:218-221` 有 4 行连续空行。纯格式，不动。
- **N7a**：`Extensions.swift` 里带 `// TODO: Remove when targeting macOS 15.`（L1359）、
  `// TODO: Check if any of these can be removed when targeting macOS 15.`（L1100）的几个 shim。
  部署目标已经是 macOS 15.0（`docs/ROADMAP.md` E2），所以这些 TODO 到期了 ——
  但「TODO 过期」不等于「代码没人用」，逐个核实调用点是另一件事，不是「看起来没人维护就删」。
- **N7b**：`AutofocusedTextField` / `CocoaButton` / `ObjectAssociation` / `AssociationPolicy` / `Validators`
  看起来像上游遗留，实际都有活的内部调用链：
  `Validators → URL.isHostAnIPAddress → URL.isValid`，而 `isValid` 有 **7 个外部调用点**
  （`AddWebsiteScreen` 4 处 + `URLCommands.swift:30` + `WallpaperScene.swift:168`）——
  **它是 URL 输入校验，在信任边界上，永不简化**。
  `URL.isLocal` 同理：唯一使用点是 `defaultAuthChallengeHandler` 的
  `allowSelfSignedCertificate || url.isLocal`（`Extensions.swift:2848`），这是自签名证书的放行条件，属于安全措施。

### 明确排除（下一轮不要重新提）

- 把 `Extensions.swift` 按主题再拆成多个文件：不减一行，只换位置，且 `.periphery.yml` / `Package.swift` 都要跟着改。
- 给 `applyOpacity` / `installContentView` 这类「AppState 扇出 + scene 实现」的成对方法建协议或基类：
  `docs/ROADMAP.md` X4 已经否过（「没有第二个实现，抽象没有依据」）。
- 删 `Tests/NifroGeometryTests` 里任何一条：21 条全绿且做过变异验证（ROADMAP E7），
  删之前要先把它守的代码改坏确认还有别的东西红 —— 没有别的东西。

---

## Verified

| 命令 | 结果 |
|---|---|
| `periphery scan --quiet` | **4 条输出**，全部是 `.periphery.yml` 已逐条写明理由的已知保留项：`MenuSupport.swift:83` 与 `:247` 的 `sender`、`SystemEvents.swift:119` 的 `replyEvent`、`OcclusionMonitor.swift:43` 的 `timer`。**声明层面没有死代码** |
| `xcodebuild build -project Nifro.xcodeproj -scheme Nifro -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath .xcode-build` | `** BUILD SUCCEEDED **`（exit 0）。这是本报告所有候选的基线 |
| `swift test` | **21 tests / 3 suites passed**（Crop geometry、Coverage detection、Schedule），0.004s。⚠ `docs/ROADMAP.md` 第三节写「15 条几何断言」、第七节 E7 写「几何部分 18 条」，实际 21 —— 文档与代码不一致，是「两处独立回答同一个问题」的第三种形状，建议顺手改文档 |
| `which graphify` | `/Users/gaoyanbo/.local/bin/graphify`，**已装但未使用**：`graphify update <path>` 会在项目里写 `graphify-out/`，与「只写 `docs/TIDY-REPORT.md`」的硬约束冲突。改用自写脚本 + `grep -rn` 数调用点 |
| `find . -name "*.xib" -o -name "*.storyboard"` | 空。**D3 的闸门 3 依赖这个观测** —— 没有 Interface Builder 文件，就不存在按类名实例化 `NonInteractiveView` 的路径 |
| `git log -S "func applyOpacity"` | 两份 `applyOpacity` 都出自 `8b989db`（R1 场景化 + F3 多显示器）。**D4「陈旧副本」的直接证据** |

### 观测 vs 推理

**观测**（跑了命令拿到的）：
- Periphery 的 4 条输出、`BUILD SUCCEEDED`、21 条测试全绿、无 IB 文件、git 历史。
- 所有调用点计数（`grep -rn` + 跨文件符号计数脚本），包括 D3 的「全仓 1 次出现」、
  D4 的「1 个调用点」、D5/D6 的「1 个调用点」、N3a/N3b 的「2 个调用点」、
  N7b 的「`isValid` 7 个外部调用点」、`validateCallback` 的「零写入点」。
- 23 个空 extension 块 / 54 行块体 / 9 行尾随空行 —— 脚本逐行匹配数出来的。
- 5 个 Support 文件的 import 块逐字相同 —— 直接对比。
- D4 两个 `applyOpacity` 的 `diff` 输出。

**推理**（没有实测，需要在动手时用编译验证）：
- D1 表格里「哪些 import 可删」：按模块特征符号扫描推出来的，**不是**编译器结论。
  必须一行一删一编译。特别是 `MenuSupport.swift` —— 它一个特征符号都没命中，
  说明 AppKit 是被其中某个 import 间接再导出的，具体是哪个只有编译器知道。
- D7 的 113 这个数字：脚本报 129，我扣掉约 16 个「落在顶层函数体内、缩进也是 1 tab」的局部变量误判。
  精确值要逐个看。
- N2a 里「删掉 `NSMenuItemValidation` 一致性后行为等价」：纯推理，这正是它被拦下的原因。
- Not done R 组的行数（176 / 270 / 200）：按 `// MARK:` 边界估的块大小，不是精确的可达闭包。

---

## 最值得先做的三条

**1. D1 —— 删 5 个 Support 文件里用不到的 import（47 行）。**
性价比最高：闸门 2 的答案是所有候选里最锋利的一个（`cannot find 'X' in scope`，逐行精确，
零推理空间），而且它顺手记录了 E6 那次拆分留下的痕迹。
副作用是干净的：`Extensions.swift` 少 6 行 import 之后，`import StoreKit` / `import Network`
不再在文件头上暗示「这个文件跟内购和网络有关」。

**2. D2 —— 删 23 个空 extension 块（63 行）。**
风险几乎为零（空块没有成员，不可能有运行时可达路径），但价值不只是 63 行：
这些空壳是前三轮清理的**残留物**，留着会让下一个人以为「这里本来该有东西，是不是删漏了」。
和 D1 一起做，一次编译验证两条。

**3. D3 + D4 —— 两个陈旧副本（25 行）。**
行数最少，但**风险回避的价值最高**，这也是任务里点名「W1 里最值钱的是陈旧副本」的原因：

- `NonInteractiveView` 是个看起来完全可复用的辅助类，下一个要做「不吃鼠标事件的视图」的人
  很可能直接用它，然后拿到 `acceptsFirstMouse: false` —— 而 `SSWebView` 和 `CropSelectionView`
  这两个活着的实现都明确要 `true`。这是「静默回退一个已合并的修复」的标准剧本。
- `AppState.applyOpacity` 更直接：它已经是一个 bug（多显示器下只恢复主屏），
  而且它长得跟 `WallpaperScene.applyOpacity` 一模一样，谁都不会怀疑它。

D4 有一个已标注的弱点（闸门 2 只有编译器，没有 opacity 测试）。如果你想再稳一点，
先做 D3（三道闸门全过，无争议），D4 放到下一轮跟多显示器 bug 一起修。

**建议顺序：D1 + D2 一起（一次编译）→ D3 → D5 + D6（两个转发包装，各 4 行）→ D4 → D7（逐个收窄，逐个编译）。**
