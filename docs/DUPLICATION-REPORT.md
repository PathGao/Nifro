# 重复事实盘点（只读，未改动任何代码）

范围：`Nifro/` + `ShareExtension/` + `Tests/` 共 45 个 Swift 文件，
外加 `docs/ROADMAP.md`、`readme.md`、`CONTRIBUTING.md`、`sites/README.md`、`.periphery.yml`、
`Casks/nifro.rb`、`.github/workflows/`、`Nifro.xcodeproj/project.pbxproj`。

验证手段：`grep -rn` 找字面量、`git log -S <字面量>` 判同源、`swift test`（21 条全绿）、
逐处打开两侧代码读过。没有跑 `xcodebuild`（未改代码）。

判据：每条都问过「这两处会因为同一个原因一起改吗」。答不上来的一律进最后一节。

统计：真重复 **13** 条 · 代码与文档不一致 **11** 条 · 机制漏成员 **7** 条 · 明确不要动 **7** 条。
另有 **2** 条在盘点期间被别人修掉，列在最后备查。

> ⚠️ **并发改动提示**。盘点期间另一个 agent 在同一个 checkout 上落了一次重构并提交为
> `ca4846d`「把壁纸内容做成深模块：一个值，一处应用」，触及
> `WallpaperScene.swift`、`VisibilityPolicy.swift`、`SnapshotBackend.swift`、
> `SwapLoading.swift`、`ScrollRestoration.swift`、`CropSelection.swift` 六个文件
> （引入 `WallpaperContent` / `RenderingMode` 两个枚举和 `pageLayoutSize`）。
> 那批改动正好收口了本报告最初写下的两条，见文末「盘点期间被别人修掉的两条」。
> **下面的行号已按 `ca4846d` 全部重新核对过。**
> 那次提交同时把本报告的第一版一并 commit 了，当前文件是修订版。

---

## 真重复（建议收口）

### R0 · 页面坐标的**原点**还是两个答案（尺寸刚被统一，原点没跟上）· 形状③ · 最危险的一条

工作树里新加的 `WallpaperScene.pageLayoutSize`（`Wallpaper/WallpaperScene.swift:112-118`）
把「页面排版**尺寸**」收成了一处，并且是**条件的**：

```swift
return Defaults[.extendBelowMenuBar] ? screen.frame.size : screen.frameWithoutStatusBar.size
```

但「页面坐标的**原点**是哪个矩形」仍然三处各写一遍，而且全是**无条件的 `screen.frame`**：

| 处 | 代码 |
|---|---|
| `Crop/CropSelection.swift:72` | `onScreen.pageFrame(inScreen: screen.frame).integral` |
| `Visibility/VisibilityPolicy.swift:85` | `region.integral.pageFrame(inScreen: screen.frame)` |
| `Wallpaper/DesktopWindow.swift:104` | `setFrame(cropRect.screenFrame(inScreen: screen.frame), ...)` |

- **为什么必须一致**：`Geometry.swift` 的 `pageFrame(inScreen:)` / `screenFrame(inScreen:)` /
  `contentFrame(pageSize:)` 三个函数互为逆运算，前提是原点矩形和尺寸矩形**是同一个**。
  `CropView` 拿 `pageLayoutSize` 排版，`DesktopWindow` 拿 `screen.frame` 定位，两者已经分叉。
- **后果**：`extendBelowMenuBar` **关**（默认值，`Constants.swift:37`）时，
  页面 y=0 实际在 `screen.frame.maxY - statusBarThickness`，而这三处把它当成 `screen.frame.maxY`。
  裁切区在垂直方向整体偏一个菜单栏高度（约 24–38pt）——用户框的和最终显示的不是同一块。
  开着 `extendBelowMenuBar` 时两者恰好重合，所以这个 bug 只在默认设置下出现。
- **为什么测试抓不到**：`Tests/NifroGeometryTests/GeometryTests.swift:62-78` 的 `roundTrip`
  两侧传的是同一个 `screen` 常量，结构上把这个分歧消掉了。它测的是函数互逆，不是调用方一致。
- **收口**：`pageLayoutSize` 旁边补一个 `pageLayoutOrigin`（或直接给 `pageLayoutFrame: CGRect?`），
  三处 `screen.frame` 全换成它。顺带解决 `DesktopWindow.swift:109` `frame.size.height += 1`
  那 1pt 和 `pageLayoutSize` 对不上的问题。
- 注：`WallpaperScene.swift:110` 的新注释已经写明「`renderOnly` used to answer this with
  `screen.frame.size` while `installContentView` answered with `screen.frameWithoutStatusBar.size`」——
  **尺寸那半修了，原点那半留在原地**。

### R1 · 遮挡阈值 40_000 在代码和测试里各写一遍 · 形状① · 护栏本身失效

- `Visibility/VisibilityPolicy.swift:31` `private static let minimumMeaningfulPatchArea = 40_000.0`
- `Tests/NifroGeometryTests/GeometryTests.swift:99` `private let meaningful = 40_000.0`

测试里那行的注释写着 ``matching `OcclusionMonitor.minimumMeaningfulPatchArea` ``——
这个常量不在 `OcclusionMonitor` 里，它是 `VisibilityPolicy.swift` 里 `WallpaperScene` 的扩展成员。
`git log -S "40_000"` → 两份同出 `f650e80`，同源。

- **为什么必须一致**：`onlyAStripShowing`、`scatteredSlivers`、`visibleDesktop`、
  `diagonalPatchesDoNotJoin` 四条测试全部拿 `meaningful` 当断言边界，它们守的就是这个阈值。
- **后果**：把代码里的 40_000 改成 400_000，21 条测试照样全绿。
  护栏和被守的值各写一份，护栏就不守了。
- **收口**：常量搬进 `Support/Geometry.swift`（已经在 `Package.swift` 的 SPM target 里，
  测试能直接 import），代码和测试都引用同一个符号。顺手改掉那条指错文件的注释。

### R2 · 页面加载超时 30 秒写了两遍 · 形状①

- `Wallpaper/SwapLoading.swift:21` `private static let swapTimeout = Duration.seconds(30)`
- `Wallpaper/SnapshotBackend.swift:56` `try await webView.loadAndWait(resolved, timeout: .seconds(30))`

两处喂的是**同一个函数** `SSWebView.loadAndWait(_:timeout:)`（`SwapLoading.swift:107`）。
`git log -S "seconds(30)"` → `b86dde8`（F12 交换加载）建了常量，`8e2b581`（P5 快照后端）抄了字面量。

- **为什么必须一致**：同一个问题「一个页面加载多久算放弃」，同一个实现，没有理由分叉。
- **收口**：`SnapshotBackend` 用 `Self.swapTimeout`，或把常量提到 `SSWebView` 上改名 `loadTimeout`。

### R3 · 「本地网站 = 目录里的 index.html」写了三遍 · 形状①

- `Wallpaper/WebViewController.swift:149`
- `Wallpaper/SwapLoading.swift:109`
- `Screens/AddWebsiteScreen.swift:340`

三处都是 `url.appendingPathComponent("index.html", isDirectory: false)`。
其中 `SwapLoading.swift:108-113` 整块是 `WebViewController.loadURL:147-156` 的复制
（file URL 分支 + `cachePolicy = .reloadIgnoringLocalCacheData`），**只漏了一行**——见 M4。

- **为什么必须一致**：`AddWebsiteScreen:340` 用它做「这个目录合不合格」的校验，
  另外两处用它做实际加载。校验和加载对同一个文件名的理解必须相同，否则能选上却打不开。
- **收口**：一行 `URL.localWebsiteEntry` 扩展，三处都调它。

### R4 · URL scheme `nifro` 写了三遍 · 形状①

- `Nifro/Info.plist:14` `<string>nifro</string>`
- `Nifro/App/URLCommands.swift:13` `guard urlComponents.scheme == "nifro"`
- `ShareExtension/ShareController.swift:13` `components.scheme = "nifro"`

- **为什么必须一致**：分享扩展造 URL、主 app 认 URL、系统按 plist 路由，三者说的必须是同一个词。
- **后果**：改任何一处，另两处静默失效。分享扩展把 URL 交给系统，系统找不到 handler，
  用户看到的是「什么都没发生」，**没有任何东西会红**。
  ROADMAP E14「标识符归零」正是改过这类字符串的一次，说明它会被改。
- **收口**：app 内两处走一个 `Constants.urlScheme`；跨 target 的第三处用源码形状测试断言
  plist 与常量一致（这属于「命题不可运行」，形状测试是对的工具）。

### R5 · 「Google 域名用空 User-Agent」的规则写了两遍 · 形状①

- `Wallpaper/WebViewController.swift:101` `if website.url.hasDomain("google.com")`
- `Wallpaper/WebViewController.swift:216-218` `host == "google.com" || host.hasSuffix(".google.com")`

同一个文件里，两种写法，还各配了一个不同的理由注释
（`:100`「Google Sheets 会报错」/ `:215`「accounts.google.com 和 docs.google.com 有防伪 UA 保护」）。

- **为什么必须一致**：它们决定同一个属性 `webView.customUserAgent` 的同一种取值。
  `:101` 在创建时生效，`:218` 在每次导航时覆盖它——后者判定不同，前者的设置就被抹掉。
- **收口**：一个 `URL.needsBlankUserAgent`，两处调，两条注释合成一条。

### R6 · 「Update Website to Current」菜单项写了两遍 · 形状① · 代码里自己承认了

- `App/Menus.swift:62-74`
- `Wallpaper/SSWebView.swift:94-106`

条件（`website.url.normalized() != url.normalized()`）、闭包体
（`all.modifying(elementWithID:) { $0.url = url }`）、tooltip 文案
（"Points the stored website at the URL currently loaded"）全部逐字相同。
`Menus.swift:61` 自己挂着 `// TODO: DRY this up with the one in SSWebView when everything is in SwiftUI.`

- **为什么必须一致**：同一个用户动作的两个入口（状态栏菜单 / 页面右键菜单），行为必须相同。
- **收口**：一个 `NSMenu.addUpdateWebsiteItemIfNeeded(currentURL:)`。那个 TODO 的前提
  （「等全部搬到 SwiftUI」）在 `App.swift:4-10` 的 TODO 里被推到 macOS 16，不构成等待的理由。

### R7 · 「浏览模式且置顶时先退出浏览模式」写了两遍 · 形状①

`Wallpaper/WebViewController.swift:185-187` 与 `:202-204`，同一个文件相隔 15 行，逐字相同：

```swift
if Defaults[.isBrowsingMode], Defaults[.bringBrowsingModeToFront] {
    Defaults[.isBrowsingMode] = false
}
```

只有第二处有注释（`// Hide Nifro if it's in front of everything.`）。
两个分支（修饰键点击 / 外链跳浏览器）在做同一件事：把链接交给外部浏览器之前让开。

### R8 · 「本 scene 对应的 NSScreen」写了三遍 · 形状①

- `Wallpaper/WallpaperScene.swift:103` `window.targetDisplay?.screen ?? .main`
- `Wallpaper/DesktopWindow.swift:98` `targetDisplay?.screen ?? .main`
- `Crop/CropSelection.swift:15` `desktopWindow.targetDisplay?.screen ?? .main`（`AppState` 上）

`WallpaperScene.screen` 就是这个表达式，另外两处绕过它自己写了一遍。

- **为什么必须一致**：「显示器拔了怎么办」只能有一个回退策略。今天三处都是 `?? .main`，
  哪天改成 `?? Display.main?.screen` 或加上 `isConnected` 检查，只会改到一处。
- **收口**：`DesktopWindow` 暴露 `resolvedScreen`，另两处都读它。

### R9 · 「某显示器上的网站集合」写了两遍 · 形状①

- `Sites/WebsitesController.swift:183` `all.filter { $0.effectiveDisplay == display }`
- `Sites/Playlist.swift:31` `all.filter { $0.effectiveDisplay == display }`

同一个过滤式，喂给两个回答同一问题却给出不同答案的函数（见 M6）。
`WebsitesController.swift:169-174` 的 `displaysInUse` 也在用 `effectiveDisplay` 做同一件事的另一半。

### R10 · 抓网页标题写了两份实现，超时值已经分叉 · 形状①

- `Screens/AddWebsiteScreen.swift:381-386`：`LPMetadataProvider()` + `shouldFetchSubresources = false`
  + **`metadataProvider.timeout = 5`**
- `Sites/WebsitesController.swift:214-218`：`LPMetadataProvider()` + `shouldFetchSubresources = false`
  + **没设 timeout**（`LPMetadataProvider` 默认 30 秒）

- **为什么必须一致**：同一个 API、同一个目的（网站没标题时补一个）。
  `WebsitesController.fetchTitleIfNeeded` 是 `add(_:title:)` 的后备路径，
  `AddWebsiteScreen.fetchTitle` 是输入框防抖后的路径，用户体验上是同一件事。
- **后果**：从 URL command / 分享扩展 / Shortcuts 添加网站时挂一个 30 秒的后台请求；
  从添加界面输入时是 5 秒。差异没有任何地方解释过。
- **收口**：`WebsitesController` 那份加上 `timeout = 5`，`AddWebsiteScreen` 调它。

### R11 · 「菜单栏图标露 5 秒」的数字写在代码和文案两处 · 形状①

- `App/AppState.swift:142` `delay(.seconds(5)) { ... statusItem.isVisible = false }`
- `Screens/SettingsScreen.swift:262` `"...launch the app again to reveal the menu bar icon for 5 seconds."`

- **为什么必须一致**：这是同一个承诺的实现和说明。改代码不会改文案，用户按文案去验会失败。
- **收口**：常量 `AppState.menuBarIconRevealDuration`，文案用插值。

### R12 · 注入的 CSS 类名写在三处 · 形状①

- `Wallpaper/WebViewController.swift:63` `'is-nifro-app', 'is-plash-app'`
- `Wallpaper/SSWebView.swift:133-134` `"nifro-is-browsing-mode"` / `"plash-is-browsing-mode"`
- `Sites/Website.swift:90-93` `starterCSS` 里把这四个名字**再抄一遍**给用户看

- **为什么必须一致**：`starterCSS` 是发给用户的契约文档，它列的类名必须是实际注入的类名。
  ROADMAP 第四节把「新旧并存」列为兼容性决定，这四个名字是对外承诺。
- **收口**：一个 `enum InjectedClass` 持四个字符串，注入脚本和 `starterCSS` 都插值它。

### R13 · 仓库 URL 手写了四遍，旁边就有常量 · 形状①

`App/Constants.swift:5-7` 已经有 `repositoryURL` / `siteGalleryURL` / `siteSubmissionURL`，但：

- `Support/AppInfo.swift:54` `URL("https://github.com/PathGao/nifro/issues/new")`
- `Sites/SiteCatalog.swift:40` `URL("https://raw.githubusercontent.com/PathGao/nifro/main/sites/index.json")`
- `Screens/SettingsScreen.swift:286` `"https://github.com/PathGao/nifro/issues/2"`
- `Screens/AddWebsiteScreen.swift:132` `"https://github.com/PathGao/nifro/discussions/136"`

ROADMAP S4「建 GitHub 仓库」还没做，仓库路径（组织名 / 仓库名）一旦定下来要改五个文件。
后两条还指向**不存在的资源**，见 D11。

---

## 代码与文档不一致

### D1 · ROADMAP 第五节 P1 机制图描述的是被推翻的实现

ROADMAP §五「P1 的机制」写：

> `NSScreen.visibleFrame` 未被覆盖的比例 **< 2%** → 判定全遮挡
> ↑ visibleFrame 本身就已经扣掉了菜单栏和 Dock，所以「只剩 Dock 和菜单栏露着」天然算全遮挡

代码 `Visibility/OcclusionMonitor.swift:100-101` 用的是 `screen.frame`，
旁边专门写了注释解释**为什么不用 visibleFrame**。判据也不是 2%，是两条：
`VisibilityPolicy.swift:26` `fullRenderFraction = 0.6`（高于它整屏渲染）和
`:31` `minimumMeaningfulPatchArea = 40_000.0`（低于它才冻结）。

`git log -p` 显示 `dd5aff7` 把 `screen.visibleFrame` 改成 `screen.frame` 并重写了代码注释，
**ROADMAP 没跟**。`GeometryTests.swift:142-153` 的 `scatteredSlivers` 就是在证明 2% 这个判据是错的。

**代码是对的，ROADMAP 该改。**

### D2 · ROADMAP 说 5 秒兜底轮询，代码是 2 秒

ROADMAP §五：「外加 **5 秒**兜底轮询」。
`Visibility/OcclusionMonitor.swift:20` `private static let pollInterval = 2.0`。
`git log -p` 里有明确的 `-private static let pollInterval = 5.0` / `+... = 2.0`。**代码是对的。**

### D3 · readme 说通用二进制，其余三处都说不做

`readme.md:37`：「Universal builds for Apple silicon and Intel.」

反面证据：
- ROADMAP 第七节 E16：「~~通用二进制~~ **不做**（你定的）。改成逐架构各出一份瘦包」
- `Casks/nifro.rb:8-9`「两个架构各发一份瘦二进制，不做通用包」，`:11` `arch arm:/intel:`，`:14-15` 两个 sha256
- `.github/workflows/release.yml:128-155`：`for arch in arm64 x86_64` 逐架构构建，
  `lipo -archs` 校验产物**只含一个架构**，不一致直接 `::error::` 失败

**readme 是错的。** 这句话直接影响用户下载哪个包。

### D4 · CONTRIBUTING 给的第一条命令打不开

`CONTRIBUTING.md:46-53`：

```
git clone https://github.com/PathGao/nifro.git
open nifro/Plash.xcodeproj
```
> Then build and run the `Plash` scheme. (The Xcode project, its targets and the
> source directory still carry the upstream name...)

实际：工程是 `Nifro.xcodeproj`，scheme 是 `Nifro`
（`Nifro.xcodeproj/xcshareddata/xcschemes/Nifro.xcscheme`），源码目录是 `Nifro/`。
ROADMAP E5「target / 目录 / 工程 / scheme 改名」标 ✅ 已完成。
`CONTRIBUTING.md:110-111`「internal target and directory names are the one exception,
and are being renamed on their own schedule」同样过期。

**CONTRIBUTING 是错的**，而且这是新贡献者敲的第一条命令。

### D5 · CONTRIBUTING 说部署目标 macOS 26.0，实际 15.0

`CONTRIBUTING.md:58-59`：「**Deployment target: macOS 26.0.** New API is available and you should use it.」

实际全是 15.0：
- `Nifro.xcodeproj/project.pbxproj:576` 和 `:636` `MACOSX_DEPLOYMENT_TARGET = 15.0;`
- `Package.swift:14` `platforms: [.macOS(.v15)]`
- `readme.md:37` "Requires macOS 15 or later."
- `Casks/nifro.rb:28-29` 注释「工程的 MACOSX_DEPLOYMENT_TARGET = 15.0」+ `depends_on macos: ">= :sequoia"`
- ROADMAP E2 有整段论证为什么定在 15.0（「量出来的不是拍的」）

**CONTRIBUTING 是错的**，差 11 个大版本，而且它明确鼓励用新 API，照做会编不过。

### D6 · CONTRIBUTING 说没有测试目标

`CONTRIBUTING.md:69`：「There is no test target. That means the burden of showing a change works
falls on the description of what you ran」

实际：`Package.swift:21-25` 有 `NifroGeometryTests`，`swift test` 刚跑过
**21 tests in 3 suites passed**；`.github/workflows/ci.yml:43-54` 有独立的 `test` job；
`readme.md:49-53` 明写 `swift test`；ROADMAP E7 标 ✅。**CONTRIBUTING 是错的。**

### D7 · ROADMAP 的 snapshot/live 条数不对

ROADMAP 第二节：「sites/ 里 24 条真实条目已经按这个维度分好类：**18 条 snapshot，6 条 live**」

实测：`grep -h '^backend:' sites/*.yml | sort | uniq -c` → **17 snapshot / 7 live**；
`Nifro/Sites/SiteCatalog.generated.swift` 里 `isLive: true` 也是 **7** 条（总数 24 对得上）。
**数据是对的，ROADMAP 该改。**

### D8 · ROADMAP 说 CI 四个 job，实际五个

ROADMAP §三 和 E8：「CI：build / test / lint / sites **四个** job，外加生成物新鲜度检查」。
`.github/workflows/ci.yml` 实际五个：`build` / `test` / `lint` / **`unused`（Periphery 扫描）** / `sites`。
`unused` 是 `.periphery.yml` 那套护栏的执行面，ROADMAP 里完全没有它。

### D9 · sites/README 承诺了 per-site reloadInterval，代码只有全局

`sites/README.md:27`：

> `reloadInterval` | Seconds between reloads. For `snapshot` sites this is also how often the screenshot is retaken.

代码 `Nifro/Sites/SiteCatalog.swift:84-87`：

```swift
// The app has no per-site reload interval yet, so the catalogue's value goes to the global setting
// only when nothing has been chosen.
if let reloadInterval, Defaults[.reloadInterval] == nil {
    Defaults[.reloadInterval] = reloadInterval
}
```

`Defaults.Keys.reloadInterval`（`Constants.swift:29`）是全局键，`Website` 结构里没有这个字段。
从图库添加**第二个**站点时它的 `reloadInterval` 被完全忽略。

**代码是诚实的，文档在承诺一个不存在的行为。** 24 条 yml 里多条带 `reloadInterval`
（`bing-photo-of-the-day` 21600、`cocktails-interactive` 86400 等），贡献者按文档填的值大多不生效。

### D10 · sites/README 里指向「Plash readme」的链接指向了我们自己的 readme

`sites/README.md:14`：`the use-cases and tips in the pre-close [Plash readme](../readme.md)`。
`../readme.md` 是 Nifro 自己的 readme，不是 Plash 的。

### D11 · 两个 app 内链接指向本仓不存在的编号资源

- `Screens/SettingsScreen.swift:286` `Link("Multi-display support ›", "https://github.com/PathGao/nifro/issues/2")`
- `Screens/AddWebsiteScreen.swift:132` `Link("More ideas", "https://github.com/PathGao/nifro/discussions/136")`

`#2` 和 `discussion #136` 都是**上游 Plash 的编号**（ROADMAP F3 引的就是 Plash#2，
C3 引的就是 Plash discussion #136）。域名被机械替换成本仓后，这两个编号在 Nifro 仓里不存在——
ROADMAP S4 记着仓库本身都还没建。

额外一层：ROADMAP F3 多显示器标 ✅ 已实现，设置界面却还挂着一个「支持进展」外链。
这是同一类事故的第三例（前两例：注释说 visibleFrame、欢迎页指已删菜单项）。

---

## 机制有成员没加入

### M1 · `playlistInterval` 加了 Defaults 键，没接监听

机制：每个 `Defaults.Key` 在 `App/Events.swift` 里接一个 `Defaults.publisher`。
`Constants.swift:22-46` 的 20 个键里，`playlistInterval`（`:44`）**没有任何监听**。

对照：同性质的 `reloadInterval` 在 `Events.swift:147-151` 接了 → `resetTimer()`。

- **漏掉的后果**：在设置里改「轮播间隔」（`SettingsScreen.swift:113-131`），
  `Sites/Playlist.swift:70` 的 `resetPlaylistTimer()` 不会被调用，按旧间隔跑的 `playlistTimer` 继续跑。
  要等 `rebuildScenes()` / `isEnabled` 翻转 / `.websites` 变化才顺带生效。
  用户改了设置，看起来什么都没发生。

### M2 · `extendBelowMenuBar` 只接到窗口 frame，没接到色带、现在也没接到页面尺寸

- `Wallpaper/DesktopWindow.swift:89-93` 监听它 → `setFrame()` ✅
- `App/Events.swift:39-45` 只监听 `.solidColorUnderMenuBar` → `installMenuBarBandIfNeeded()`

两个还没加入的成员：

1. `Visibility/MenuBarBand.swift:42-46` 的 `shouldShowMenuBarBand` 是**两个键的与**
   （`extendBelowMenuBar && solidColorUnderMenuBar && menuBarHeight > 0`），
   但只有后者有监听。`solidColorUnderMenuBar` 已开时切换 `extendBelowMenuBar`，
   色带不出现也不消失。而 `SettingsScreen.swift:99` 用 `.disabled(!extendBelowMenuBar)`
   把两个开关绑在一起，正好让这条路径成为用户的常规操作顺序。
2. **新增**：工作树里的 `WallpaperScene.pageLayoutSize`（`:112-118`）现在也读这个键，
   而 `content` 不会因为它变化而重新赋值（`applyContent()` 只在 `content` 的 `didSet` 里跑）。
   一个带 crop 的网站在切换 `extendBelowMenuBar` 后，`CropView` 仍拿旧的 `pageSize` 排版，
   窗口却已经按新 frame 缩放了。

### M3 · `tearDown()` 没管 `OcclusionMonitor` 的轮询 Timer，注释也已经不成立

`Wallpaper/WallpaperScene.swift:324-331` 的 `tearDown()` invalidate 了 `reloadTimer`、
`playlistTimer`，cancel 了 `snapshotTask`、`pendingLoad`，置 `content = .empty`，
**没有碰 `occlusionMonitor`**。

`Visibility/OcclusionMonitor.swift:90` 的注释：

> No `deinit` invalidating the timer. **This object lives as long as the app does**...

这句话在 R1 场景化之后不成立：`WallpaperScene.swift:85` 每个 scene `new` 一个 `OcclusionMonitor`，
`AppState.swift:160-177` 的 `rebuildScenes()` 在插拔显示器 / `.websites` 变化 / `.display` 变化时
都会丢掉不再需要的 scene。

- **漏掉的后果**：每次重建泄漏一个每 2 秒空转的 runloop Timer
  （block 持弱引用，所以是空转不是内存泄漏，但永远不会停）。反复插拔外接屏会一直累加。
- **额外一层**：这条已经过期的理由同时写在 `.periphery.yml:35-36` 里，
  为 `OcclusionMonitor.timer` 的 retain 辩护。按护栏规则「理由过期时，那一行就该失败」。

### M4 · 交换加载路径漏了沙盒授权那一步

- `Wallpaper/WebViewController.swift:147-152`：file URL 分支先调
  `_ = url.accessSandboxedURLByPromptingIfNeeded()`，再 `loadFileURL`
- `Wallpaper/SwapLoading.swift:108-109`：同一条 file URL 分支，**直接 `loadFileURL`**，没有那一行

两处同源复制（见 R3），`loadAndWait` 是后加的。

- **漏掉的后果**：本地目录网站（`AddWebsiteScreen.swift:304-353` 的「Local Website…」，
  存了 security-scoped bookmark）在**交换加载**路径上可能拿不到访问权限。
  交换加载覆盖的正是所有 reload：`reloadTimer`、`reloadOnWake`、菜单里的 Reload、
  URL command `reload`、Shortcuts 的 `ReloadWebsiteIntent`。
- **为什么特别难发现**：`SwapLoading` 的设计就是失败时**保留旧画面**并把错误塞进 tooltip
  （`:57-64`）。这个失败模式在桌面上完全不可见。

### M5 · `didLoadPublisher` 只订阅了主 scene 一个

`App/Events.swift:10` 的 `webViewController` 是 `AppState.swift:43` 的
`primaryScene.webViewController`，在 `setUpEvents()` 里求值**一次**。

- **漏掉的后果**：多显示器下非主 scene 的加载失败不会进 `webViewError`
  （菜单栏 tooltip 不报错、菜单里不出现 "Error:" 行），它的 zoom 恢复
  （`Events.swift:17-20`）不会跑，tooltip 也不会更新。
  ROADMAP F3 把多显示器标为 ✅，这条通知链没跟着场景化。
- 注：`WebViewController.swift:239-240` 的 `scene?.refreshMenuBarBandColor()` /
  `scene?.restoreScrollPosition(in:)` 是**按 scene 走**的，说明这条链知道该怎么写，
  只有 `didLoadPublisher` 这一路还挂在 primary 上。

### M6 · 「这块屏该显示哪个网站」两条路径，一条不问排班

- `App/AppState.swift:180`（`rebuildScenes`）→ `WebsitesController.current(for:)`
  （`WebsitesController.swift:182-185`）：只按 `effectiveDisplay` 过滤，**完全不看 startHour/endHour**
- `Sites/Playlist.swift:103`（`advancePlaylist`）→ `scheduled(for:)`
  （`Playlist.swift:60-63`）→ `eligible(for:at:)`：过滤排班，且保证不清空

- **漏掉的后果**：插拔显示器、改 websites 列表、改默认显示器都会触发 `rebuildScenes()`，
  它会把一个**已经过了时段**的网站放回屏幕，要等下一次 `playlistTimer` 触发才纠正
  （最长 60 秒，或用户设的轮播间隔）。
- ROADMAP F5 承诺「排班永远不会把一块屏清空」——`eligible` 那半确实做到了，
  但 rebuild 这条路径压根不问排班，等于绕过了整个机制。

### M7 · 框选裁切只接管主 scene，恢复却遍历所有 scene

`Crop/CropSelection.swift`：
- `:15`、`:34-36`、`:39`、`:46-47`、`:54-55` 全部操作 `desktopWindow`
  （= `AppState.swift:42` 的 `primaryScene.window`）
- `:31` 新加的 `primaryScene.content = .live(crop: nil)` 也只动主 scene
- `:56-58` 恢复不透明度时却 `for scene in scenes`

被裁切的对象是 `WebsitesController.shared.current`（`:14`、`:62`），
它的 `effectiveDisplay` 未必是主 scene 的 display。

- **漏掉的后果**：多显示器下，在副屏上的网站按「Choose Crop Region…」，
  框选覆盖层出现在主屏上，用户框的是错的那块屏；`:72` 换算用的 `screen` 也是主屏的。
  刚加的 `:31` 那行把**主 scene** 的内容拉回实时页面，如果目标网站在副屏，
  副屏那张冻结静帧原封不动——正是这行注释要防的情况。

---

## 看着像重复但不是（明确不要动）

### N1 · 两个动画时长 0.25 / 0.35

`Wallpaper/WallpaperScene.swift:319` `$0.duration = 0.25`（不透明度渐变）与
`Wallpaper/SwapLoading.swift:91` `$0.duration = 0.35`（换页淡入）。

变化原因不同：前者跟 dim/opacity 的手感走，用户连续拖滑块会反复触发它；
后者跟「新页面替换旧页面要不要被察觉」走。合并会让调一个的理由绑架另一个。

### N2 · `fullRenderFraction = 0.6` 与 `minimumMeaningfulPatchArea = 40_000`

`Visibility/VisibilityPolicy.swift:26` 和 `:31`。一个是比例、一个是绝对面积，
回答两个不同问题：「值不值得把窗口缩小」vs「还剩的这块值不值得画」。

`GeometryTests.swift:142-153` 的 `scatteredSlivers` 正是在证明比例判据会误判
（四条 10pt 边 = 3.6% 的屏幕，过得了 2% 的比例线，却没有一块能看）。它们不能互相替代。

### N3 · `settleDelay = 2.0` 与 `pollInterval = 2.0`

`Wallpaper/SnapshotBackend.swift:19`（等页面稳定再拍）与
`Visibility/OcclusionMonitor.swift:20`（遮挡轮询周期）。

数值撞车。前者跟 WebKit 的字体 / 图片 / 首帧落地时机走，
后者跟「别的 app 挪了窗口，用户能忍多久才看到反应」走，而且它有功耗代价。
`git log` 显示后者已经从 5.0 调到 2.0，前者没动过——它们本来就在各自演化。

### N4 · 两处 `delay(.seconds(1))`

`Wallpaper/WallpaperScene.swift:252`（首次加载后取消隐藏，防白闪）与
`Screens/WelcomeScreen.swift:41`（首启弹完引导后自动点开菜单）。纯巧合。

### N5 · 每页存储键的构造方式（但缺一条注释）

- `Wallpaper/SSWebView.swift:149-156` zoom 键：`normalized(removeFragment: true, removeQuery: **true**)`
- `Wallpaper/ScrollRestoration.swift:17-22` scroll 键：`normalized(removeFragment: true, removeQuery: **false**)`

表达式链一模一样（`.absoluteString.removingSchemeAndWWWFromURL.toData.base64EncodedString()`），
但答案**故意不同**：缩放属于站点（`?date=2026-08-23` 不该换一档缩放），
滚动位置属于带参数的那个具体页面（日历翻到不同日期该记不同位置）。

**不要合并。但这条分叉现在没有任何注释解释它**，下一个人很可能当成 bug「修」掉。
建议两处各补一行说明——这属于 WORKSPACE_GUIDE 说的
「被排除掉的东西值得和成果一样正式地写下来」。

### N6 · `defaultCrop = 600×400` 与快照兜底 `1920×1080`

`Crop/CropSetting.swift:21` 是「打开裁切开关时给一个明显小于全屏的初值，让用户一眼看出生效」；
`Wallpaper/SnapshotBackend.swift:41` 是「拿不到 `pageLayoutSize` 时离屏渲染用多大」。
一个是 UI 初值，一个是失败兜底。

### N7 · `is-nifro-app` / `is-plash-app` 这类新旧并存的类名对

不是重复，是 ROADMAP 第四节写明的兼容性决定（保住社区五年攒的 Plash 自定义 CSS）。
**不要合并成一个。** 它们被抄在三个文件里是另一回事，见 R12。

---

## 盘点期间被别人修掉的两条（备查）

工作树里那批未提交改动已经收口了下面两条，本报告不再计入。列在这里是为了
「记住被排除掉的东西」，避免下一轮重新提出：

- **静止帧 `NSImageView` 的安装代码**曾在 `VisibilityPolicy.installFrozenView` 和
  `SnapshotBackend.showSnapshot` 各写一遍（`frame: window.contentLayoutRect` /
  `.scaleAxesIndependently` / `autoresizingMask [.width, .height]`）。
  现已收进 `WallpaperScene.stillView(_:)`（`:184-191`），
  且 `window.contentView` / `window.cropRect` 只有 `applyContent()`（`:132-157`）一个写入点。
- **三个互斥渲染开关的 `&&` 链**曾在 `VisibilityPolicy`、`SnapshotBackend`、`WallpaperScene`
  各写一遍，条件集合互有出入。现已收进 `RenderingMode`（`WallpaperScene.swift:375-421`），
  四个调用点（`VisibilityPolicy:35,119`、`SnapshotBackend:26`、
  `WallpaperScene:133,211,221`）全部读它。

---

## 最危险的三条

按「改对一处不会改对其余」排，不按行数：

1. **R0 页面坐标的原点还是三处各写一遍 `screen.frame`**，而尺寸刚被收成条件化的
   `pageLayoutSize`。这是唯一一条**现在就在产生错误结果**的：默认设置下
   （`extendBelowMenuBar` 关）裁切区垂直方向偏一个菜单栏高度。
   而且刚落地的那次重构在注释里宣布修好了这个类的 bug——只修了尺寸那半，
   这会让下一个人相信它已经不是问题了。

2. **R1 阈值 40_000 在代码和测试里各写一遍**。护栏和被守的值分成两份，护栏就不是护栏了：
   改代码里的阈值，21 条测试全绿。那条指错文件的注释
   （说它在 `OcclusionMonitor` 里）还会让下一个人先找错地方。

3. **R4 URL scheme `nifro` 三处字面量**（Info.plist / URLCommands / ShareExtension）。
   跨 target，编译器帮不上忙，失败形式是「分享扩展点了没反应」，没有任何东西会红。
   ROADMAP E14 已经改过一次这类标识符，说明它是会被改的。

紧随其后的是 **M4**（沙盒授权漏在交换加载路径上）：它同样无声，
而且失败会被 `SwapLoading` 的「保留旧画面」设计主动掩盖掉。
