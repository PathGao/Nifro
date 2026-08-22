# Nifro 路线图与工作台账

> 这份文件是这个项目的事实来源。改了范围就改这里，不要在别处并列一份。
> 面向社区的英文版说明另写在 README，这份是我们自己的工作文档。

---

## 一、这是什么

Nifro 是 [sindresorhus/Plash](https://github.com/sindresorhus/Plash) 的开源分支。

```
2020-01  Plash 开源（MIT），把任意网页显示成 macOS 桌面壁纸
   │
   │     5 年，4k star，158 fork，0 个外部代码贡献
   │
2025-10-29  作者删源码 + 压缩 git 历史成一个 "Init" commit
   │         readme 原话：没收到贡献，还要应付 App Store 克隆，维护开源不划算
   │
2026-05-05  App Store v2.17.2，闭源状态下继续更新
   │
2026-08     我们从 fork 里捞出闭源前最后一版 MIT 快照，分出 Nifro
```

**基线**：`mattdanielbrown/Plash` @ `364f3e1`（2025-06-10，v2.16.0），MIT license 完整。这是上游闭源前的最终状态。

**名字**：暖簾 —— 日式店门口那道半透的布帘。挡一层、透一层、还是招牌。

**分发**：Homebrew cask + GitHub Release，不上 Mac App Store。

---

## 二、根本判断

这个 app 的问题不在代码质量，在两个结构性假设：

### 假设一：一直跑着的浏览器

它用一个常驻的 WebContent 进程去显示**一分钟才变一次**的内容（时钟、天气、日历、仪表盘）。

### 假设二：它不是真壁纸

它是一个 `.desktop` 层的透明无边框窗口。上游 FAQ 自己承认的后果：菜单栏取不到色。派生的还有 Stage Manager（#177）、触发台手势穿帮（#182）、以及 `DesktopWindow.swift` 里那一串 `collectionBehavior` 补丁。

### 解法：双后端

```
                    ┌─ Backend A「快照」← 默认
                    │    离屏 WKWebView ──takeSnapshot──┬─→ A1 桌面窗口的 CALayer
Website             │    渲染完立刻挂起 web 进程        │      （保留透明 / 裁切 / 多屏）
  backend: snapshot │                                  └─→ A2 NSWorkspace
        或 live ────┤                                         .setDesktopImageURL
                    │                                         ↑ 变成真·壁纸
                    └─ Backend B「实时」← 按需
                         现在这套 window + 常驻 webview
                         留给真需要动画 / 交互的页面
```

A2 一次性解决：菜单栏取色、Mission Control / Stage Manager 行为、退出后画面留存、空闲功耗真正为 0。代价是不能交互、刷新有下限。**这条路还没验证过，见 S1。**

sites/ 里 24 条真实条目已经按这个维度分好类：18 条 snapshot，6 条 live（屏保、WebGL 流体、连续 3D 场景这些）。

---

## 三、状态总览

```
本轮 commit 数        5
构建状态              BUILD SUCCEEDED（Swift 6 语言模式，macOS 15.0，Debug/Release）
测试                  15 条几何断言，swift test 全绿，变异验证过确实守得住
上游 issue 分诊       35 条 → DO 17 / LATER 13 / REJECT 1 / OBSOLETE 4
                      详见 UPSTREAM-ISSUES.md。35 条其实只压成 8 个机制
阻塞项                1（S1 需要改一次桌面壁纸，等你在场）
待你验收              遮挡冻结、裁切 —— 桌面上有构建产物和测试清单
```

---

## 四、已完成

| | 事项 | 证据 |
|---|---|---|
| ✅ E3 | 移除 Sentry | 原作者的 DSN，本分支不该上报。调用点 + helper + import 全清 |
| ✅ E12 | 移除 App Store 评分弹窗与商店链接 | 不上 MAS，`id1494023538` 是原作者的 app id |
| ✅ E13 | 移除原作者美术资产 | 图标 PNG、sketch 源文件、商店截图与文案。MIT 不覆盖美术资产。菜单栏图标换成原创占位（飘窗轮廓单色模板图） |
| ✅ E14 | 标识符归零 | bundle id `com.pathgao.nifro`，URL scheme `nifro://`，版本 0.1.0，反馈入口指向本仓库 issues |
| ✅ C1 | issue forms + PR 模板 | 参照 Markpad：全 `.yml` forms，英文，每个字段解释为什么问。含 **site submission** 类型 |
| ✅ C2 | CONTRIBUTING | 含与上游 Plash 关系的说明：独立分支，不接受任何冒充 Plash 或复用其商标图标的贡献 |
| ✅ C3 | sites/ 清单 | 24 条真实条目 + JSON Schema + 贡献说明。数据来自上游 discussion #136 五年积累 |
| ✅ E9 | release workflow + 签名方案 | 参照 AeroSpace。见第八节 |
| ✅ E10 | Homebrew cask | 仓库内 `Casks/`，CI 回写版本与 sha256，带 livecheck |
| ✅ E1 | Swift 6 语言模式 | 14 处并发错误全部按语义修，不是塞 `nonisolated(unsafe)` 了事 |
| ✅ E2 | 部署目标 macOS 15.0 | 见第七节，是量出来的不是拍的 |
| ✅ E4 | 清掉上游作者的 `DEVELOPMENT_TEAM` | |
| ✅ E5 | target / 目录 / 工程 / scheme 改名 | |
| ✅ E7 | 几何运算的接缝与测试 | 根目录 `Package.swift` 直接读 app 编译的源文件，一份实现 |
| ✅ E8 | CI | build / test / lint / sites 四个 job |
| ✅ P1–P4 | 遮挡时停止渲染 | 见第五节 |
| ✅ F1 | 裁切 | 见第六节。框选 UI（F2）还没做 |

兼容性决定：注入的 CSS 类名**新旧并存** —— `is-nifro-app` + `is-plash-app`，`nifro-is-browsing-mode` + `plash-is-browsing-mode`。社区五年攒下的 Plash 自定义样式片段可以直接用，这是我们最不该丢的资产。

---

## 五、功耗优化（P 系列）

上游的停机条件只有三个：手动禁用、锁屏、电池供电（`AppState.swift:125`）。**没有任何遮挡判断。**

| | 优化 | 状态 | 说明 |
|---|---|---|---|
| **P1** | 遮挡判定 | ✅ 已实现 | 见下方机制。功耗数字待上机实测 |
| **P2** | 遮挡时挂起媒体 | ✅ 已实现 | `setAllMediaPlaybackSuspended(true)`。上游只有 `muteAudio`，静音不省 CPU，视频照解码 |
| **P3** | 遮挡时停 reload timer | ✅ 已实现 | 恢复可见时若已过期立刻补一次 |
| **P4** | 遮挡时换成快照层 | ✅ 已实现 | webView 摘出视图树，WebKit 才会真的停渲染。**注意**：靠 CSS 动效/滤镜吃饭的页面会退化，上游 [#193](https://github.com/sindresorhus/Plash/issues/193) 正文是现成回归用例，将来要做成按站点可关 |
| **P5** | 快照后端（Backend A） | 待做 | 默认路径。多数网站根本不需要实时渲染。P2 的验收项：恢复可见后视频要自己接着播 |
| **P6** | 真壁纸路线（A2） | **阻塞，见 S1** | 收益最大，风险也最大 |
| **P7** | 内容铺满时不透明化 | 待做 | `isOpaque = true` + `drawsBackground = true`，省一层与桌面的合成 |
| **P8** | webview 真正销毁 | 待做 | 上游注释原文 "We never destroy the webview"，禁用时只 load about:blank + orderOut，进程还在 |
| **P9** | reload 策略可配 | 待做 | 现在写死 `reloadIgnoringLocalCacheData`，每次整页重建布局 |

### P1 的机制 —— 为什么不能用系统的 occlusionState

```
NSWindow.occlusionState 的判据是「有没有一丝可见」
        ↓
Dock 是半透明的，菜单栏那条也总是露着
        ↓
一个最大化窗口盖住整屏时，桌面窗口在 WindowServer 眼里仍然 visible
        ↓
任何挂在 occlusionState 上的逻辑，一次都不会触发
```

改成自己算可见面积：

```
CGWindowListCopyWindowInfo(.optionOnScreenOnly)   ← 无需任何权限，只读窗口 frame
        ↓ 过滤：layer >= 0、alpha > 0.9、排除自己、排除已知的全屏透明系统窗口
        ↓ 并集，栅格化到 64×40 网格
NSScreen.visibleFrame 未被覆盖的比例 < 2%  →  判定全遮挡
        ↑
   visibleFrame 本身就已经扣掉了菜单栏和 Dock，
   所以「只剩 Dock 和菜单栏露着」天然算全遮挡，不用单独写特例
```

触发时机：`NSWorkspace` 的应用激活 / 隐藏 / 切换空间通知，外加 5 秒兜底轮询（别的 app 移动窗口不发任何我们能收到的通知）。一次判定是一次窗口列表快照加一次网格填充。

实现在 `OcclusionMonitor.swift`。

---

## 六、功能（F 系列）

| | 功能 | 上游 issue | 状态 |
|---|---|---|---|
| **F1** | 裁切：选网页的一块显示，规避导航栏和边框 | [#138](https://github.com/sindresorhus/Plash/issues/138) [#162](https://github.com/sindresorhus/Plash/issues/162) [#93](https://github.com/sindresorhus/Plash/issues/93) | ✅ 已实现 |
| **F2** | 框选 UI：浏览模式下拖一个框存成 crop | #138 原话「可视化选取像素范围」 | 待做 |
| **F3** | 多显示器 | [#2](https://github.com/sindresorhus/Plash/issues/2)，47 👍 / 36 评论，全表第一需求，2026-08 仍在 bump | 待做，需 R1。**主流诉求是每块屏不同 URL**，不是同屏铺满；社区已自建 `plash-cloner` 克隆 app 绕路 |
| **F4** | 静态模式 | [#15](https://github.com/sindresorhus/Plash/issues/15) | 等价于 P5 |
| **F5** | 播放列表 | [#4](https://github.com/sindresorhus/Plash/issues/4) | 待做，需 R1。评论里还要求**按时间排班**（早晚不同页面） |
| **F6** | app 内图库：从 sites/ 一键添加，带推荐设置 | — | 待做 |
| **F7** | 保留**会话状态**：URL + 滚动位置 + 缩放，`WKWebView.interactionState` 一次拿下；配「唤醒时重新加载」开关 | [#39](https://github.com/sindresorhus/Plash/issues/39) [#127](https://github.com/sindresorhus/Plash/issues/127) [#154](https://github.com/sindresorhus/Plash/issues/154) | 待做，S–M |
| **F8** | 显示器选择进主菜单 | [#195](https://github.com/sindresorhus/Plash/issues/195) | 待做，S。F3 落地后菜单形态要改，二选一别做一半 |
| **F9** | 桌面失焦时变暗 / 去色 | [#177](https://github.com/sindresorhus/Plash/issues/177) | 待做，S。挂在 P1 的判定上，别另造一套 |
| **F10** | 自定义 CSS 注入健壮性：SPA 改写 documentElement 后重新注入 | [#173](https://github.com/sindresorhus/Plash/issues/173) | 待做，S–M。**真 bug**，命中 Google 日历、zoom.earth |
| **F11** | 用户代理策略：别再钉死 `Version/18.3` | [#169](https://github.com/sindresorhus/Plash/issues/169) | 待做，S。写死的版本号让 Google 日历常年报「浏览器过旧」 |
| **F12** | 双 webview 交换加载：成功才淡入，失败保留旧内容 | [#9](https://github.com/sindresorhus/Plash/issues/9) [#11](https://github.com/sindresorhus/Plash/issues/11) [#21](https://github.com/sindresorhus/Plash/issues/21) [#41](https://github.com/sindresorhus/Plash/issues/41) [#47](https://github.com/sindresorhus/Plash/issues/47) | 待做，M。**一个机制关掉 5 条**，作者五年前写好方案没做 |
| **F13** | 修饰键点击时在默认浏览器打开链接 | [#140](https://github.com/sindresorhus/Plash/issues/140) | 待做，S。约十行 |
| **F14** | 进入浏览模式时真正取得键盘焦点 | [#114](https://github.com/sindresorhus/Plash/issues/114) | 待做，S。缺的是 `SSApp.forceActivate()` |
| **F15** | 桌面层有限交互（点击 / 鼠标移动），按站点开 | [#50](https://github.com/sindresorhus/Plash/issues/50) [#16](https://github.com/sindresorhus/Plash/issues/16) | 待做，L。功耗代价必须写进文档 |
| **F16** | 内容规则加载入口（cookie 横幅 / 广告），不自维护规则源 | [#37](https://github.com/sindresorhus/Plash/issues/37) | 待做，M |

### F1 必须两侧同时改，这是上游踩的坑

```
① 网页侧   clip-path: inset(...)      只裁视觉
② 窗口侧   window.setFrame(cropRect)  裁掉命中区域
```

上游只教人写 ①（discussion #139 里 sindresorhus 给的两段 JS），所以 [#162](https://github.com/sindresorhus/Plash/issues/162) 那位用户缩小了 Google 日历之后，**空白区照样挡住桌面、照样吃鼠标事件**。只做视觉不做窗口，等于没做。

顺带：窗口变小 → 合成面积变小，跟 P7 是同一笔收益。

还有一层上游没人说破：**CSS 侧永远改不了 `@media` 查询**。用 `:root { width: 420px }` 缩小的页面，窗口还是整屏，所以站点仍然按桌面断点排版，拿不到移动端布局（[#93](https://github.com/sindresorhus/Plash/issues/93)）。只有窗口侧 `setFrame` 真的把窗口缩小，媒体查询才会跟着变。

**已实现**：`CropView` 原生剪裁 + `DesktopWindow.cropRect` 缩小窗口，页面仍按整屏布局。所以连 `clip-path` 都没用上，而且鼠标事件被吞的问题自动没了。

### R1 场景化 —— F3/F5/P5 共同的前置

```
现在                                   改成
AppState.shared                        AppState
  ├─ desktopWindow      (lazy, 单例)     └─ scenes: [WallpaperScene]
  └─ webViewController  (lazy, 单例)
        ↑                              protocol WallpaperScene {
    当前网站靠全局                          window / website / display
    WebsitesController.shared.current      + 两个实现：Live 和 Snapshot
    到处读                               }
```

两个真实现（Live / Snapshot），不是为抽象而抽象。

---

## 七、工程（E 系列）

| | 事项 | 状态 |
|---|---|---|
| **E1** | Swift 6 语言模式 | pbxproj 已改 `SWIFT_VERSION = 6.0`，**迁移错误还没清** |
| **E2** | 部署目标 macOS 26.0 | 已改（上游是 15.2） |
| **E4** | 清掉 `DEVELOPMENT_TEAM = YG56YK5RN5` | 待做。那是上游作者的 team id |
| **E5** | target / 目录 / xcodeproj 改名 Plash → Nifro | 待做 |
| **E6** | 拆 `Utilities.swift` | 待做。5745 行，全文只有 2 个 `// MARK`。这是新贡献者最大的一堵墙 |
| **E7** | 测试 target | 待做。上游 0 个 |
| **E8** | CI build workflow | 待做 |
| **E11** | `.gitignore` 补 `.release/`、`.xcode-build/` | 待做 |

E6 和 E7 的优先级不低于任何功能。上游 5 年零贡献不是社区不来，是 5745 行的单文件 + 没有测试 + 没有 CI 把人劝退了。我们要反过来做。

---

## 八、签名与分发

参照 [AeroSpace](https://github.com/nikitabobko/AeroSpace) 的实际做法调查结果：

| | AeroSpace | Nifro | 理由 |
|---|---|---|---|
| 签名 | 本机自签名证书 | Developer ID / ad-hoc | 自签名对 Gatekeeper 和 ad-hoc 完全等价，白搭一步 |
| 公证 | 不做 | 有账号就做 | Nifro 是沙盒 GUI app，用户不像平铺 WM 用户那样习惯敲 `xattr` |
| 发布 | 本机脚本 + 人工拖 zip | tag 触发 Actions | 本机发版不可复现 |
| cask | 单独 tap 仓库 | 本仓库 `Casks/`，CI 回写 | 少维护一个仓库 |
| livecheck | 无 | 有 | 将来投 homebrew-cask 主仓也用得上 |

**设计**：一个 workflow，靠 `secrets.MACOS_CERTIFICATE_P12` 存不存在自动分路径。现在没付费账号也能直接发版；将来买了账号只需填 6 个 secret + 删掉 cask 里的 `postflight` 块，YAML 一行不改。

用户体验差异：

| | brew 安装 | 下载 zip 双击 |
|---|---|---|
| 有账号（公证） | 无提示 | 一句「从互联网下载」确认 |
| 没账号（ad-hoc） | 无提示（postflight 去隔离属性） | **被拦死**，只有「移到废纸篓 / 取消」 |

所以没账号期间，README 的安装章节必须把 brew 放第一位。完整手册在 `docs/RELEASE.md`。

---

## 九、需要你本人做的

| | 事项 | 何时 |
|---|---|---|
| **S1** | 批准 `setDesktopImageURL` 沙盒验证 —— 会改一次桌面壁纸再改回来 | 这个结果决定 P6 是不是主路线，比其他都重要 |
| **S2** | 图标与视觉 | 说好明天一起 |
| **S3** | 决定要不要买 Apple Developer Program（99 美元/年） | 决定用户下载后看到什么 |
| **S4** | 建 GitHub 仓库、建 `site-submission` label、确认 tap 形态 | 推之前 |
| **S5** | 证书类操作：Developer ID 证书、导出 p12、App Store Connect API key | 只在选了 S3 的「买」之后 |

---

## 十、明确不做（不要再提）

| | 方案 | 否掉的理由 |
|---|---|---|
| **X1** | 换 Web 引擎（Electron / Tauri / CEF） | WKWebView 是系统进程、与 Safari 共享，换任何东西都更贵。问题在调度不在引擎 |
| **X2** | 重写成纯 SwiftUI | 现有 `NSMenu` + `NSWindow` 又快又对，`MenuBarExtra` 换过去是退步 |
| **X3** | Tuist / XcodeGen | `project.pbxproj` 只有 694 行，还不到冲突成灾的规模 |
| **X4** | 依赖注入框架、插件系统 | 没有第二个实现，抽象没有依据 |
| **X5** | 只用 CLT 做类型检查门禁 | **试过，失败**：KeyboardShortcuts 里用了 `#Preview`，那个宏插件只随 Xcode 发货，Command Line Tools 编不出依赖模块。必须装 Xcode |
| **X7** | 摄像头 / 屏幕采集输入（`getUserMedia`、`getDisplayMedia`） | entitlement 是进程级的，等于给一个 24 小时渲染任意用户 URL 的进程永久配上取摄像头的能力；壁纸 app 的权限列表越短越可核查。采集卡合成走 OBS，监控走 NVR 客户端。上游 [#125](https://github.com/sindresorhus/Plash/issues/125)。注意它**技术上做得到**，拒的理由不是难度 |
| **X6** | 名字带原名（Plash-Neo 之类） | 正面撞上作者闭源的理由（App Store 克隆）。候选里 shoji 撞 ShojiWM（552★ 窗口管理器）、ukiyo 撞 ukiyo-js、yohaku 撞同名排版系统、mado 和 byobu 撞 Homebrew formula |

---

## 十一、执行顺序

```
✅ E5 改名 → E1 Swift 6 → E8 CI → E7 几何测试
✅ P1..P4 遮挡链路 → F1 裁切
   ↓
你验收 + 实测功耗数字        ← 现在在这
   ↓
F10 / F11 / F14 / F13（四条 S，都是真 bug 或十几行）
   ↓
F12 双 webview 交换加载（一个机制关掉 5 条 issue）
   ↓
S1 验证 → 定 P6 走不走 → P5 快照后端
   ↓
R1 场景化 → F3 多显示器 / F5 播放列表
   ↓
E6 拆 Utilities → 开门收 issue
```

功耗那一刀排在裁切前面，因为它是你自己在用时感觉到的问题。但如果 S1 验证通过、P6 可行，P5 会顶掉 P1..P4 的大部分价值 —— 到那时遮挡判定只剩 Backend B 那条路需要。
