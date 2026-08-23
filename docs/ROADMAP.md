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
本轮 commit 数        24
构建状态              BUILD SUCCEEDED（Swift 6 语言模式，macOS 15.0，Debug/Release）
测试                  21 条断言（几何 + 排班），swift test 全绿，两批都做过变异验证
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
| **P5** | 快照后端（Backend A） | ✅ 已实现 | 默认路径。多数网站根本不需要实时渲染。P2 的验收项：恢复可见后视频要自己接着播 |
| **P6** | 真壁纸路线（A2） | **阻塞，见 S1** | 收益最大，风险也最大 |
| ~~P7~~ | ~~内容铺满时不透明化~~ | **不做** | 省的量量不出来，而且需要一个用户开关，开在透明背景的页面上直接黑屏。收益不明的设置项不加 |
| **P8** | webview 真正销毁 | ✅ 已实现 | 上游在这儿留了条 TODO，实际是 load about:blank + orderOut，进程和它那一百多 MB 一直留着 |
| ~~P9~~ | ~~reload 策略可配~~ | **不做** | 没有任何 issue 提过，是我自己想的 |

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
| **F1** | 选网页的一块**放大填满屏幕**，规避导航栏和边框 | [#138](https://github.com/sindresorhus/Plash/issues/138) [#162](https://github.com/sindresorhus/Plash/issues/162) [#93](https://github.com/sindresorhus/Plash/issues/93) | ✅ 已实现，语义已改（见下） |
| **F2** | 框选 UI：拖一个框存成缩放 | #138 原话「可视化选取像素范围」 | ✅ 已实现。框锁定屏幕宽高比 |
| **F3** | 多显示器 | [#2](https://github.com/sindresorhus/Plash/issues/2)，47 👍 / 36 评论，全表第一需求，2026-08 仍在 bump | ✅ 已实现。**显示器是网站的属性**，不是全局设置 —— 读评论才发现主流诉求是每块屏不同页面 |
| **F4** | 静态模式 | [#15](https://github.com/sindresorhus/Plash/issues/15) | ✅ 等价于 P5，已实现 |
| **F5** | 播放列表 | [#4](https://github.com/sindresorhus/Plash/issues/4) | ✅ 已实现。轮播 + 按小时排班；排班永远不会把一块屏清空 |
| **F6** | 站点图库 | — | ✅ 已实现。GitHub 是权威来源与提交入口，app 内运行时拉取 `sites/index.json`，编进包里的那份只在没网时兜底 |
| **F7** | 保留**会话状态**：URL + 滚动位置 + 缩放，`WKWebView.interactionState` 一次拿下；配「唤醒时重新加载」开关 | [#39](https://github.com/sindresorhus/Plash/issues/39) [#127](https://github.com/sindresorhus/Plash/issues/127) [#154](https://github.com/sindresorhus/Plash/issues/154) | ✅ 已实现，但**用的是滚动位置而不是 `interactionState`**。后者靠驱动一次导航生效，数据过期就是白壁纸，交付前测不了；滚动是安全失败的。等能实测再换 |
| **F8** | 显示器选择进主菜单 | [#195](https://github.com/sindresorhus/Plash/issues/195) | ✅ 已实现。只在多于一块屏时出现 |
| **F9** | 桌面失焦时变暗 | [#177](https://github.com/sindresorhus/Plash/issues/177) | ✅ 已实现。「聚焦」定义为 Finder 在最前 —— 点桌面就是这个效果；暗到多少可调 |
| **F10** | 自定义 CSS 注入健壮性：SPA 改写 documentElement 后重新注入 | [#173](https://github.com/sindresorhus/Plash/issues/173) | ✅ 已实现。MutationObserver 在文档被改写后重新挂回样式 |
| **F11** | 用户代理策略：别再钉死 `Version/18.3` | [#169](https://github.com/sindresorhus/Plash/issues/169) | ✅ 已实现。版本号从运行时系统推导 |
| **F12** | 双 webview 交换加载：成功才淡入，失败保留旧内容 | [#9](https://github.com/sindresorhus/Plash/issues/9) [#11](https://github.com/sindresorhus/Plash/issues/11) [#21](https://github.com/sindresorhus/Plash/issues/21) [#41](https://github.com/sindresorhus/Plash/issues/41) [#47](https://github.com/sindresorhus/Plash/issues/47) | ✅ 已实现。**只覆盖「替换页面」**，会话内首次加载仍直接进窗口 —— 没理由把必须能工作的路径放到新机制后面 |
| **F13** | 修饰键点击时在默认浏览器打开链接 | [#140](https://github.com/sindresorhus/Plash/issues/140) | ✅ 已实现 |
| **F14** | 进入浏览模式时真正取得键盘焦点 | [#114](https://github.com/sindresorhus/Plash/issues/114) | ✅ 已实现。缺的就是 `SSApp.forceActivate()` |
| **F15** | 桌面层有限交互（点击 / 鼠标移动），按站点开 | [#50](https://github.com/sindresorhus/Plash/issues/50) [#16](https://github.com/sindresorhus/Plash/issues/16) | ✅ 已实现。按网站开，且与冻结/静止化互斥（会点的页面必须醒着） |
| **F16** | 内容规则加载入口（cookie 横幅 / 广告），不自维护规则源 | [#37](https://github.com/sindresorhus/Plash/issues/37) | ✅ 已实现。**不自维护规则**，只接受一个别人维护的列表 URL 交给 WebKit |

### F1 语义：不是裁掉周边，是把选中区放大成新的全屏

第一版按上游 issue 的字面做成了「只显示这一块，窗口缩到这一块，周围还桌面」。实际用下来
要的是另一件事：**选中的区域变成整张壁纸**。

```
第一版                          现在
┌────────────────┐              ┌────────────────┐
│   桌面          │              │                │
│   ┌────────┐   │              │   选中区放大    │
│   │ 选中区 │   │      →       │   填满整屏      │
│   └────────┘   │              │                │
│   桌面          │              │                │
└────────────────┘              └────────────────┘
窗口缩到选区大小                 窗口还是整屏
```

三个随之而来的决定：

1. **框锁定屏幕宽高比。** 画出来的东西要变成整张壁纸，别的形状只能靠加黑边或者偷偷多给一些
   来交付。不让画错形状是这两者的诚实版本。比例按本机去掉菜单栏之后的区域算。
2. **放大用 `WKWebView.magnification`，不是图层变换。** 变换是把已经画好的像素拉大，字会糊；
   magnification 让 WebKit 按那个倍率重画一遍。
3. **存的是「中心 + 倍率」，不是矩形。** 同一个网站可能同时在两块形状不同的屏上。矩形只合它
   被画出来的那一块屏；中心加倍率则每块屏各自算出自己形状的矩形，围着页面同一个地方。
   多屏问题就在这里解决，不需要按屏存多份。

页面仍然按整屏布局——站点必须相信自己拿到了整个屏幕，否则会重排，框出来的区域就不是拿到的
区域了。所以 `clip-path` 一直没用上，鼠标事件被吞的问题也不存在。

窗口缩小这条机制没删，只是换了主人：现在只有遮挡策略（P7）会缩窗口，缩到还露在外面的那一块。

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
| **E1** | Swift 6 语言模式 | ✅ 14 处并发错误逐条按语义修，不是塞 `nonisolated(unsafe)` |
| **E2** | 部署目标 | ✅ macOS 15.0。**量出来的**：编译器可用性报错在 26.0 和 15.0 都是 0，14.0 / 13.0 各 1 条且是同一条（`App.swift` 的 `.defaultLaunchBehavior`）。所有 M 系列 Mac 都能升到 macOS 26，所以硬件覆盖跟部署目标无关，15.0 只是多接住不升级系统的人 |
| **E3** | 移除 Sentry | ✅ 调用点 + helper + SPM 依赖 |
| **E4** | 清掉上游作者的 `DEVELOPMENT_TEAM` | ✅ |
| **E5** | 改名 Plash → Nifro | ✅ target / 目录 / 工程 / scheme / bundle id |
| **E6** | 拆 `Utilities.swift` | ✅ 已实现。拆成 Extensions / MenuSupport / Display / SystemEvents / AppInfo，参照 Ice 与 Rectangle 的形状 |
| **E7** | 测试 | ✅ 21 条：几何 18 条 + 排班 3 条，两批都做过变异验证。其余仍是 0 |
| **E8** | CI | ✅ build / test / lint / sites 四个 job，外加生成物新鲜度检查 |
| **E9** | release 流水线与签名 | ✅ 逐架构构建，`lipo` 校验产物只含一个架构 |
| **E10** | Homebrew cask | ✅ 按架构分发 |
| **E11** | `.gitignore` | ✅ |
| **E15** | 首启引导重写 | ✅ |
| ~~E16~~ | ~~通用二进制~~ | **不做**（你定的）。改成逐架构各出一份瘦包 |

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

## 十点五、审查过并决定不动的（附数据）

两轮机器审查（清理闸门、重复扫描）跑完之后留下的结论。**记住被排除的东西比记住
做了什么更容易丢**，所以这一节和「已完成」同等重要，它防止下一轮有人重新提出。
原始报告连同行号只存在于 git 历史里（曾是 `docs/TIDY-REPORT.md` 与 `docs/DUPLICATION-REPORT.md`，写成本节时删除），行号已经因为后续重构而过期，别照着它改代码。

| | 候选 | 数据 | 为什么不动 |
|---|---|---|---|
| R1 | `SecurityScopedBookmarkManager` 176 行 | 服务 1 到 3 个调用点 | 坐在沙盒信任边界上。替换是等价改写，而且没有检查能抓住写错 |
| R2 | `Cache` + `SimpleImageCache` 270 行 | 同上 | 同上 |
| R3 | `WebsiteIconFetcher` 200 行 | 同上 | 同上 |
| N1 | 一批手写循环换成正则或标准库 | — | 等价改写。被替换的代码携带领域规则，而我们没有能红的断言 |
| N2 | 一批「类型检查过了」就算验证的改动 | — | 「哪个检查会红」答不上来 |
| N3 | 两个动画时长 0.25 / 0.35 看着像重复 | 2 处 | 一个是透明度过渡一个是内容淡入，**变化的原因不同**。合并是制造耦合 |
| N4 | `Website.InvertColors` 收窄可见性 | 试了两次两次红 | 一致性声明在顶层不在类型作用域内，且用它的存储属性被跨文件读 |
| N5 | `WallpaperContent` / `RenderingMode` 收窄 | — | 符号计数说它们只在本文件出现，但它们是两个跨文件 internal 属性的**类型**。纯计数看不见这条引用边 |

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
