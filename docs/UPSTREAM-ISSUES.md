# 上游 Plash open issue 分诊

> 这份文件不是路线图。事实来源仍然是 [ROADMAP.md](ROADMAP.md)。
> 这里是把上游五年攒下的 35 条 open issue 逐条读完之后的取舍清单，最后一节是建议合并进 ROADMAP 的新条目。合并由本人做，本文件不改 ROADMAP。

**数据来源**：`sindresorhus/Plash` issue 追踪器（源码已删，issue 还在）。
**抓取方式**：GitHub REST API 匿名读取 `/issues?state=open`（35 条正文、标签、reaction）+ 每条的 `/comments`（21 条有评论的全部 90 条评论）。评论数为 0 的也读了正文。
**抓取时间**：2026-08-23。
**实现成本判据**：基线 `mattdanielbrown/Plash @ 364f3e1`（v2.16.0）在 `Nifro/` 下的当前代码。

成本口径：**S** = 一个设置项 / 几十行；**M** = 一个新文件或改一处结构；**L** = 需要 R1 场景化或 S1 验证这类前置改造。

---

## 一、总表

| # | 用户到底要什么 | 成本 | 分类 | 路线图编号 |
|---|---|---|---|---|
| [196](https://github.com/sindresorhus/Plash/issues/196) | 视频壁纸开机自动播，不用手动按一次 | S | OBSOLETE | — |
| [195](https://github.com/sindresorhus/Plash/issues/195) | 换显示器别让我翻三层设置 | S | DO | **F8**(新) |
| [193](https://github.com/sindresorhus/Plash/issues/193) | 页面不更新时 `backdrop-filter` 的模糊就冻住了 | M | LATER | P 系列相关 |
| [183](https://github.com/sindresorhus/Plash/issues/183) | 壁纸上点一下能唤起 `vscode://` 这类 app | S | LATER | — |
| [182](https://github.com/sindresorhus/Plash/issues/182) | 触发台手势一划，底下露出真桌面图片，穿帮 | L | LATER | P6 / A2 |
| [177](https://github.com/sindresorhus/Plash/issues/177) | 我在干别的活时，壁纸自己变暗变灰别抢注意力 | S | LATER | **F9**(新)，挂 P1 |
| [173](https://github.com/sindresorhus/Plash/issues/173) | 我写的自定义 CSS 在浏览器生效，在 app 里不生效 | S–M | DO | **F10**(新) |
| [169](https://github.com/sindresorhus/Plash/issues/169) | Google 日历顶上常年挂着"浏览器版本过旧" | S | DO | **F11**(新) |
| [164](https://github.com/sindresorhus/Plash/issues/164) | 点链接就地跳转，别弹新窗口 | S | LATER | 需要更多信息 |
| [162](https://github.com/sindresorhus/Plash/issues/162) | 把网页缩到屏幕一角，剩下的地方还给桌面 | M | DO | F1 / F2 |
| [158](https://github.com/sindresorhus/Plash/issues/158) | 壁纸里的天气页能拿到我的位置 | M | LATER | — |
| [154](https://github.com/sindresorhus/Plash/issues/154) | 临时关掉再打开，别把我播到一半的页面丢了 | S | DO | F7(扩) |
| [140](https://github.com/sindresorhus/Plash/issues/140) | 按住修饰键点链接，用真浏览器打开 | S | DO | **F13**(新) |
| [132](https://github.com/sindresorhus/Plash/issues/132) | 页面里的告警声要能响 | ? | LATER | 需要更多信息 |
| [127](https://github.com/sindresorhus/Plash/issues/127) | 合盖再开，别把页面状态刷没了 | S | DO | F7(扩) |
| [125](https://github.com/sindresorhus/Plash/issues/125) | 把摄像头/采集卡画面当壁纸 | M | **REJECT** | **X7**(新) |
| [114](https://github.com/sindresorhus/Plash/issues/114) | 快捷键切到浏览模式后能直接打字，不用再点一下 | S | DO | **F14**(新) |
| [93](https://github.com/sindresorhus/Plash/issues/93) | 网页当侧边栏，而且要触发移动端布局 | M | DO | F1 / F2 |
| [88](https://github.com/sindresorhus/Plash/issues/88) | 从 Alfred 里列出已配置网站并切过去 | — | OBSOLETE | — |
| [79](https://github.com/sindresorhus/Plash/issues/79) | 301 跳转到站外的链接也该丢给浏览器 | M | LATER | — |
| [76](https://github.com/sindresorhus/Plash/issues/76) | 多来点现成的图片壁纸源 | — | OBSOLETE | C3 / F6 |
| [50](https://github.com/sindresorhus/Plash/issues/50) | 不进浏览模式也能点壁纸上的链接/按钮 | L | LATER | **F15**(新) |
| [47](https://github.com/sindresorhus/Plash/issues/47) | 切换网站时别硬切，淡入淡出 | M | DO | **F12**(新) |
| [41](https://github.com/sindresorhus/Plash/issues/41) | 唤醒时没网就白屏，红图标，内容全没了 | M | DO | **F12**(新) |
| [39](https://github.com/sindresorhus/Plash/issues/39) | 重载后保住缩放和滚动位置 | M | DO | F7 |
| [37](https://github.com/sindresorhus/Plash/issues/37) | Cookie 横幅和广告把壁纸毁了 | M | LATER | **F16**(新) |
| [21](https://github.com/sindresorhus/Plash/issues/21) | 别让我看见重载过程，加载完再露出来 | S | DO | **F12**(新) |
| [16](https://github.com/sindresorhus/Plash/issues/16) | 不进浏览模式，壁纸也能跟着鼠标动 | M–L | LATER | **F15**(新) |
| [15](https://github.com/sindresorhus/Plash/issues/15) | 静态站点别一直挂着浏览器进程 | L | DO | P5 / F4 |
| [11](https://github.com/sindresorhus/Plash/issues/11) | 源站挂了别弹错误框，保住上一屏内容 | M | DO | **F12**(新) |
| [9](https://github.com/sindresorhus/Plash/issues/9) | 首次加载别先给我一块灰底 | S | DO | **F12**(新) |
| [7](https://github.com/sindresorhus/Plash/issues/7) | 首启引导做得像样点 | S | DO | **E15**(新) |
| [5](https://github.com/sindresorhus/Plash/issues/5) | 帮忙润色 App Store 文案 | — | OBSOLETE | — |
| [4](https://github.com/sindresorhus/Plash/issues/4) | 多个网站轮播，最好还能按时间排班 | L | LATER | F5（需 R1） |
| [2](https://github.com/sindresorhus/Plash/issues/2) | 每块屏幕一个网页 | L | LATER | F3（需 R1） |

**分类计数**：DO 17 / LATER 13 / REJECT 1 / OBSOLETE 4。

**这 35 条其实只压成了 8 个机制**：

```
F12 双 webview 交换加载 ──┬─ #9  首次淡入
                          ├─ #11 加载失败保住旧内容
                          ├─ #21 加载完成再露出
                          ├─ #41 唤醒无网不白屏
                          └─ #47 切站淡入淡出

F7  会话状态保留 ─────────┬─ #39  滚动 + 缩放
（WKWebView.interactionState）├─ #127 唤醒不重载
                          └─ #154 关闭再开保住当前 URL

F1/F2 裁切（网页侧+窗口侧）┬─ #162 缩小后仍挡住右边
                          └─ #93  侧边栏 + @media 要生效

F15 桌面层有限交互 ───────┬─ #50 点击
                          └─ #16 鼠标移动

P5/F4 快照后端 ───────────── #15
P6/A2 真壁纸 ─────────────── #182
F10 / F11 各自独立的真 bug ── #173 / #169
```

---

## 二、DO（17 条）

### F12 双 webview 交换加载 —— #9 #11 #21 #41 #47

一句话：**新页面在一块隐藏的 webview 里加载，成功了才淡入换掉旧的，失败就整块丢掉。**

上游作者本人在 #47、#41、#11 三处分别写下了同一段方案，五年没做。这五条 issue 是同一个机制的五个症状：

| issue | 症状 | 交换加载之后 |
|---|---|---|
| #9 | 首启一块灰底 | 加载完才淡入 |
| #11 | 源站返回死链就弹模态错误框 | 失败丢弃新 webview，屏上还是上一屏 |
| #21 | 用户能看见重载过程 | 天然消失，不需要"等 5 秒"这个设置 |
| #41 | 唤醒时没网 → 红图标 + 空白 | 旧内容留着，联网后自动补一次 |
| #47 | 切网站硬切 | 交叉淡入 |

当前代码的证据：`AppState.loadURL` 里是 `delay(.seconds(1)) { desktopWindow.contentView?.isHidden = false }` —— 一个写死的 1 秒，还带着 `// TODO: Fade in the web view`。`Events.swift` 的 `SSEvents.deviceDidWake` 无条件 `reloadWebsite()`，而全仓没有任何 `NWPathMonitor`，所以 #41 在我们基线上是活的。

成本 M（一个新文件管两块 webview 的生命周期 + 一个 `NWPathMonitor`）。收益：一次关掉 5 条，其中 #11、#41 是真 bug。这是全表性价比第一。

### F10 自定义 CSS 注入健壮性 —— #173

用户在 zoom.earth 和 Google 日历上写的 CSS 在 DevTools 里贴生效，写进 app 的 CSS 框不生效。四条评论里有三个不同的人复述同一现象（2024-12、2026-02、2026-03）。

机制：`Utilities.swift:1626` 的 `createCSSInjectScript` 在 `.atDocumentStart` 把 `<style>` 挂到 `document.documentElement` 上。SPA 在挂载时整片改写 `documentElement` 的子树，注入的 style 节点被连带清掉 —— 所以"手贴生效、页面一 reload 就没了"。最小修法：documentEnd 再补一次注入，或用 `MutationObserver` 在 style 掉出文档时重挂。

需要注意的是 #173 里 jiexiangfan 报的 `SyntaxError: Can't create duplicate variable: 'style'` **不适用于我们** —— 那是上游 2.17.0 的回归，我们基线的注入脚本是包在 IIFE 里的（`Utilities.swift:1631`）。这一条对我们已 OBSOLETE，别照着改。

成本 S–M。收益高：自定义 CSS 是这个 app 的核心用法，ROADMAP 第四节专门为了社区五年的 Plash CSS 片段保留了双类名，注入本身坏掉的话那个兼容性决定就白做了。

### F11 用户代理策略 —— #169

`Utilities.swift:1406` 把 UA 钉死成 `Version/18.3 Safari/605.1.15`。Google 日历按版本号判活，于是壁纸顶上常年挂一条"This browser version is no longer supported"。报告人 2024 年提，2025-03、2025-04、2025-10 三个人接着复述"我也是"，最后一条评论是教人用 CSS 把那个 div 藏掉（`.V8Lvo { display: none }`）—— 五年下来社区只能靠遮丑。

作者的回复"Plash 用的是内置 Safari 不是 Chrome"没答到点上：问题不是引擎旧，是我们自己报了个会过期的版本号。

修法（成本 S）：不要写死版本号。要么别覆盖 `customUserAgent`（WKWebView 默认 UA 本身不带 `Version/x`，需要实测哪些站点会挑剔），要么在运行时从系统 Safari 取版本号拼。注意现有代码已经对 `*.google.com` 走空 UA 分支（`WebViewController.swift` 两处），但只在 `website.url.hasDomain("google.com")` 时建 webview 就置空，`calendar.google.com` 走的是导航时那条 —— 顺手统一。

### F7 扩展成会话状态保留 —— #39 #154 #127

三条 issue 是同一件事的三个入口：

- #39 重载后保住滚动位置和缩放（作者 2020 年就把缩放做了，我们代码里的 `zoomLevelWrapper` 就是；滚动一直没做）
- #154 快捷键禁用再启用，播放列表位置丢了（作者本人回复"应该这么做"）
- #127 合盖唤醒被强制重载，页面状态没了

作者自己在 #39 里留了答案：`WKWebView.interactionState`。这个属性一口气覆盖 URL、历史、滚动位置，可以序列化存盘。不用像 2020 年那样写 JS 滚动监听 + Swift 桥。

配套要改的还有 `AppState.isEnabled` 的 else 分支（现在是 `loadURL("about:blank")` + `orderOut`）和 `Events.swift` 里唤醒无条件 reload —— 后者应该出一个"唤醒时重新加载"的开关，默认可以保持现状。

成本 S–M。收益：三条 issue，且 #127 的抱怨对"用 Nifro 显示带状态的页面"这类用户是致命的。

### F1 / F2 裁切 —— #162 #93

两条 issue 是 ROADMAP 第六节那个论断的直接证据，不需要再论证，只需要记一笔：

- #162：用户按作者在 discussion #139 给的 CSS 缩小了 Google 日历，结果"右边的空白照样挡住桌面" —— 只做网页侧不做窗口侧等于没做。
- #93：用户想把网页当侧边栏，指出 CSS 改 `:root { width }` 只改容器不改窗口，所以 `@media` 查询不动，拿到的还是桌面版布局。**这是 CSS 侧永远解不了的那部分**，只有真的把 `window.setFrame` 缩小才行。两条附议评论。

#93 给 F1 补了一条 CSS 派做不到的硬需求，值得写进 ROADMAP 的 F1 说明里。

### P5 / F4 静态模式 —— #15

作者 2020 年自己开的 issue，方案和 ROADMAP 的 Backend A 一字不差：加载 → 截图 → 把截图当桌面显示 → 按 reload 间隔更新。评论里 firrae 问"截图本身会不会更费 CPU"，作者回答"只在间隔 tick 时截，最快 1 秒一次，通常 1 分钟一次，所以更省"。命名讨论里有人提议叫 **Snapshot**。

对我们：直接对应 P5 / F4，方向不用再讨论，实现路径见 ROADMAP 第二节。成本 L。

### F8 显示器选择进主菜单 —— #195

用户在家和公司之间换工位，每天都要改"Show on"，但要点进设置的 General 页。他几乎不换网页，只换屏幕。

成本 S：`Menus.swift` 加一个 Display 子菜单，读写的还是 `Defaults[.display]`。
注意顺序：如果 F3（多显示器）先落地，这个菜单形态要跟着变（从"选一块屏"变成"每块屏配什么"），所以要么现在做十几行、F3 时重做，要么等 F3 一起做。两种都行，别做一半。

### F14 进入浏览模式时真正取得焦点 —— #114

用户用 Nifro 写东西，快捷键切到浏览模式后还得手动点一下窗口才能打字，因为 JS 的 `onfocus`/`onblur` 也不触发。他的替代方案是拿 Alfred + AppleScript 合成一次鼠标点击。

代码里 `DesktopWindow.isInteractive = true` 时已经 `makeKeyAndOrderFront(self)`，但 app 是 accessory 型，没有 `SSApp.forceActivate()` 就拿不到真正的键盘焦点。成本 S。

### F13 修饰键在默认浏览器打开链接 —— #140

用户用 Nifro 显示监控面板，站内链接总在 Nifro 里打开，他想按住 shift+cmd 点一下丢给真浏览器排查。

`WebViewController.decidePolicyFor` 里现成的判断是 `Defaults[.openExternalLinksInBrowser] && 跨 host`；加一个"或者当前按着某修饰键"即可。代码里已经有读修饰键的先例（`NSEvent.modifiers != .option`）。成本 S，约十行。只在浏览模式下有意义。

### E15 首启引导 —— #7

上游这条是"把临时的 NSAlert 换成像样的 SwiftUI 欢迎窗"。对我们它先是个**事实错误**：`WelcomeScreen.swift` 现在的文案还在说"droplet icon"（E13 已经换成飘窗轮廓图标），还在替上游解释多显示器支持有限。这段话现在是错的，必须改。

成本 S（改文案）。顺手换 SwiftUI 是可选项，别为了它拖住改文案。

### #196 相关的一行加固（分类归 OBSOLETE，但记在这）

#196 报告人自己在两天后回帖说：手动播一次之后自动播放就一直正常了 —— 那是 WebKit 的按站点自动播放配额，作者复现不了。issue 本身作废。但如果后面做 P2（遮挡时 `setAllMediaPlaybackSuspended`），要确认恢复可见时视频会自己接着播，别把这条 issue 变成我们自己的 bug。

---

## 三、LATER（13 条）

| # | 为什么不是现在 |
|---|---|
| **#2 多显示器** | 全表第一需求：47 个 👍、36 条评论、六年不断有人 bump（最近一条 2026-08-13）。作者五年给的都是"多开几个 bundle id 不同的 Plash"这种绕路，社区最后自己写了 `plash-cloner` 脚本克隆 app。**但它依赖 R1 场景化**，在 `AppState` 还是"一个窗口一个 webview 的单例"之前做不了。按 ROADMAP 第十一节的顺序，它是 R1 之后的第一件事，也是我们相对上游最大的差异化点。评论里额外的信息：多数人要的是**每块屏不同 URL**（ianiv 那条 +25），不是同一个页面铺满。 |
| **#4 播放列表** | 同样需 R1。评论补了一条上游没写的诉求：按时间排班（早上看 GitHub 活动、晚上看别的）。作者 2021 年的回答是"Plash 可脚本化，自己写 bash 轮换"——我们有 App Intents，短期内也可以这么答。 |
| **#182 触发台手势穿帮** | ROADMAP 第二节已经点名了它。这是"它不是真壁纸"的直接后果，只有 P6/A2 能真解，而 P6 卡在 S1。在 A2 之前任何 `collectionBehavior` 的补丁都是猜。 |
| **#177 失焦变暗/去色** | 想法对，而且 macOS 自己对桌面小组件就是这么做的。实现是挂在 P1 之上的一个二十行 rider：`OcclusionMonitor` 已经在监听应用激活/切换空间的通知，拿到"桌面不是活跃焦点"之后调 `alphaValue` + 注一条 `filter: grayscale(1)` 的 CSS 就行。**先做 P1，别单独为它再造一套判定。** |
| **#193 backdrop-filter 冻住** | 见第五节。本质是 WebKit 的渲染节流，不是我们的代码。需要先在我们基线上复现（报告人给了完整的 about:blank 复现脚本），确认它跟 P4 的快照层替换是不是同一个东西的两面。在没复现之前给不出成本。 |
| **#183 URL scheme 唤起 app** | 全表离"无理要求"最近但没过线的一条。壁纸页面能唤起本机 app 是明确的攻击面，但报告人自己就提了正确的设计：默认关 + 白名单 + 首次确认，而且他在本地改过一行验证不破沙盒。只影响开这个开关的人。收益很小（1 个 👍），排在所有 S 项后面。**如果要做，默认关是硬要求。** |
| **#158 geolocation** | 作者本人开的 issue，他自己判断"要手动实现，不打算做，希望 Apple 原生支持"（WWDC24 之后并没有）。可行路径是在 `.page` world 注入一个 `navigator.geolocation` 的 shim，后面接 CoreLocation。**但这要给一个 24 小时渲染任意用户 URL 的进程加定位权限**，和 #125 是同一套论证，区别只在于粗定位一次性 vs 实时视频流。要做的话必须默认关 + 按站点授权。1 人附议。 |
| **#164 点链接就地跳转** | 需要更多信息。诉求写于 2024 年（2.x），而当前代码里：`target=_blank` 只在浏览模式下才开新窗口（`createWebViewWith` 里 `targetFrame == nil` 就地加载），前进后退手势也已经开着（`allowsBackForwardNavigationGestures = true`）。**缺的信息**：他遇到的到底是弹窗口还是别的。要么等复现，要么按"总是在同一视图内导航"做成一个开关（S）。 |
| **#132 页面声音响不了** | 需要更多信息。标题写"Force mute"，正文要的其实相反：他关掉了 Mute audio，页面里的 Web Audio (`AudioContext` + `Audio().play()`) 还是不响。我们的 `muteAudio()` 只处理 `<audio>/<video>` 元素，管不到 AudioContext，所以静音开关不是原因；更可能是 WebKit 的自动播放策略要 user gesture，而桌面层根本没有 gesture。**缺的信息**：在我们基线上设 `mediaTypesRequiringUserActionForPlayback = []` 之后能不能解封 AudioContext。如果只能靠私有的 `_WKWebsiteAutoplayPolicy`，这条直接转 X 系列。 |
| **#79 301 跳转的外链** | 真 bug。`openExternalLinksInBrowser` 的判断只在 `navigationType == .linkActivated` 那一刻比对 host，服务端 301 到站外时导航类型已经是 `.other`，于是跳转结果留在了 Nifro 里。修法是记住"这次导航是用户点出来的"，在 `didReceiveServerRedirect` 或响应阶段再比一次 host。成本 M（要在导航生命周期里带状态），收益中等偏小，排在 F12 后面 —— 两者都在动导航链路，一起改更省。 |
| **#50 + #16 桌面层有限交互** | 合并成一条（F15）。#50 十条评论，用户想要"桌面上的可交互小组件"（计算器、按钮、计时器）；#16 想要跟随鼠标的粒子/流体背景（+1×2、hooray×3）。<br>**上游已经解掉了一半**：2020 年那次提交让浏览模式不再盖住所有窗口，我们基线里就是 `bringBrowsingModeToFront` 默认关；而 `isBrowsingMode` 本身是持久化的 Default，所以"启动即浏览模式"这个诉求（评论里 imaverage 提的）今天就成立。剩下真正没解的是"只吃点击、不吃选择和滚动"。<br>#16 的实现比看起来便宜：`NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` 不需要辅助功能权限，拿到坐标合成 JS 事件即可。**但这跟整个 P 系列的立场冲突** —— 一个 60Hz 的全局监听 + 每次 `evaluateJavaScript`。要做就必须按站点开、带节流，并且在文档里写清它的功耗代价。 |
| **#37 cookie 横幅 / 广告拦截** | 作者自己开的，自己标注"工作量巨大，不会很快做"。全量自维护过滤规则确实不该碰。但中间路线便宜：`WKContentRuleListStore.compileContentRuleList` 是现成 API，我们只提供**加载入口**（内置一小份 cookie 横幅规则 + 允许用户指向自己的规则 JSON），不承诺跟进任何上游规则源。成本 M。收益真实：cookie 横幅确实会毁掉一整块壁纸。 |

---

## 四、REJECT（1 条）

### #125 摄像头 / 采集卡输入 —— 判据：违背定位 + 进程级权限面 + 有更合适的现成工具

诉求：把摄像头或 HDMI 采集卡的画面当壁纸；退一步，让调用 `getUserMedia` 的网页能工作。3 个 👍，四条评论，其中一位自己改了 Xcode 工程验证可行（加 `NSCameraUsageDescription` + 相机 entitlement + 授权请求），另一位是拿 Mac mini 当监控墙。

**技术上做得到**（`navigator.mediaDevices` 之所以 undefined 就是缺 entitlement），所以拒的理由不是难度：

1. **entitlement 是进程级的，不是按站点的。** 一旦签上相机权限，这个 24 小时渲染**用户任意输入的 URL** 的进程就永久具备了取摄像头的能力。macOS 的授权弹窗只是第二道闸，第一道闸——"这个 app 压根不该有这个能力"——是我们自己放弃的。壁纸 app 的 entitlement 列表越短越好，这是用户能核查的少数几件事之一。
2. **违背定位。** 它是壁纸，不是视频采集软件。一个 3 人规模的诉求换来所有用户在"隐私与安全"里看到 Nifro 申请摄像头。
3. **有更合适的现成工具。** 采集卡/多路视频合成走 OBS（虚拟摄像头 / 全屏投影 + 置底窗口），监控墙走专门的 NVR 客户端。这些工具本来就在做这件事，做得比我们好。

**建议进 X 系列（X7）**，连同"屏幕采集 / `getDisplayMedia`"一起写死，省得以后再讨论。

同类论证适用于 #158（定位），但那条留在 LATER：一次性粗定位和实时视频流的风险量级不同，且天气类页面是主流用法。真要做也必须默认关 + 按站点授权。

---

## 五、OBSOLETE（4 条）

| # | 为什么作废 |
|---|---|
| **#196 视频自动播放** | 报告人自己两天后结论：只需手动播一次，之后自动播放一直正常（WebKit 的按站点自动播放配额），作者复现不了。issue 是个误会。唯一要留意的是 P2 别把它变成真 bug，见第二节末尾。 |
| **#88 Alfred 列出已配置网站** | 作者 2021 年的计划是"等 Shortcuts for Mac 出来，用 App Intents 返回网站列表"。**我们基线里已经有了**：`Intents.swift` 的 `WebsiteAppEntity` 带 `EnumerableEntityQuery`，配 `SetCurrentWebsiteIntent`，Alfred/Shortcuts 现在就能列出并切换。不需要再造 deeplink。 |
| **#76 更多图片壁纸源** | 上游的做法是号召别人各自 fork 他的 `plash-bing-photo-of-the-day` 仓库。我们的等价物是已完成的 **C3（sites/ 清单 + schema + 投稿入口）** 和待做的 **F6（app 内图库）**，方向更好：一个集中清单 + 一键添加，而不是散落的 N 个仓库。作为 issue 作废，作为需求已被 C3/F6 吸收。 |
| **#5 App Store 文案** | 我们不上 MAS（ROADMAP 第一节），E12 已经把商店链接和评分弹窗全清了。 |

---

## 六、其实是性能问题的 issue

这一节回答"哪些 issue 表面在说功能，实际在说功耗/渲染调度"。

```
用户看到的                        真正的机制                     我们的编号
─────────────────────────────────────────────────────────────────────────
#193 backdrop-filter 冻住   ← WebKit 在 DOM 不更新时停止重算    P 系列的反面
                              backdrop 快照，页面一"活"就恢复    （见下）

#15  静态站点太浪费          ← 作者本人的功耗论证，方案就是      P5 / F4
                              截图替代常驻渲染

#154 想要 pause 而不是 disable ← 他要的"挂起渲染器但别丢状态"    P2 / P3 / P4
                              正是遮挡链路那套动作               + F7

#127 唤醒别重载              ← 无谓的整页重建（我们还写死了      P9 + F7
                              reloadIgnoringLocalCacheData）

#21  加载完再显示            ← reload 期间的白屏与重排是         P9 + F12
                              "每次整页重建"的可见症状

#196 视频不自动播            ← 自动播放配额；同时是 P2 挂起      P2 的验收项
                              媒体后必须验证的恢复路径

#182 手势穿帮 / #177 想变暗   ← "它不是真壁纸"这条假设的两个      P6 / A2、F9
                              下游症状

#16  鼠标跟随                ← 想做的话代价是 60Hz 全局监听 +    与 P 系列冲突
                              每次 evaluateJavaScript
```

**#193 值得单独说一句**：它是我们整个 P 系列思路的一次现实检验。WebKit 已经在自己做节流了 —— 页面不更新时它连 backdrop 都懒得重算。这既说明"挂起不活跃内容"是引擎认可的方向（支持 P1–P4），也说明**做 P4（把 webView 摘出视图树换成快照层）时，靠 CSS 动效/滤镜吃饭的页面会明显退化**，快照层必须是按站点可关的。复现脚本在 issue 正文里，是现成的 P4 回归用例。

---

## 七、建议加进 ROADMAP 的新条目（可直接粘）

### 加进第六节「功能（F 系列）」的表

| | 功能 | 上游 issue | 状态 |
|---|---|---|---|
| **F8** | 显示器选择进主菜单 | [#195](https://github.com/sindresorhus/Plash/issues/195) | 待做，S。F3 落地后菜单形态要改，二选一别做一半 |
| **F9** | 桌面失焦时变暗 / 去色 | [#177](https://github.com/sindresorhus/Plash/issues/177) | 待做，S。挂在 P1 的判定之上，别另造一套 |
| **F10** | 自定义 CSS 注入健壮性：SPA 改写 documentElement 后重新注入 | [#173](https://github.com/sindresorhus/Plash/issues/173) | 待做，S–M。真 bug，命中 Google 日历、zoom.earth |
| **F11** | 用户代理策略：别再钉死 `Version/18.3` | [#169](https://github.com/sindresorhus/Plash/issues/169) | 待做，S。写死的版本号让 Google 日历常年报警 |
| **F12** | 双 webview 交换加载：成功才淡入，失败保留旧内容 | [#9](https://github.com/sindresorhus/Plash/issues/9) [#11](https://github.com/sindresorhus/Plash/issues/11) [#21](https://github.com/sindresorhus/Plash/issues/21) [#41](https://github.com/sindresorhus/Plash/issues/41) [#47](https://github.com/sindresorhus/Plash/issues/47) | 待做，M。一个机制关掉 5 条，作者五年前就写好了方案 |
| **F13** | 修饰键点击时在默认浏览器打开链接 | [#140](https://github.com/sindresorhus/Plash/issues/140) | 待做，S。约十行 |
| **F14** | 进入浏览模式时真正取得键盘焦点 | [#114](https://github.com/sindresorhus/Plash/issues/114) | 待做，S。缺的是 `SSApp.forceActivate()` |
| **F15** | 桌面层有限交互（点击 / 鼠标移动），按站点开 | [#50](https://github.com/sindresorhus/Plash/issues/50) [#16](https://github.com/sindresorhus/Plash/issues/16) | 待做，L。功耗代价必须写进文档 |
| **F16** | 内容规则加载入口（cookie 横幅 / 广告），不自维护规则源 | [#37](https://github.com/sindresorhus/Plash/issues/37) | 待做，M |

### 修改已有条目

| | 改成 | 依据 |
|---|---|---|
| **F7** | 保留**会话状态**：URL + 滚动位置 + 缩放，用 `WKWebView.interactionState` 一次拿下；配一个"唤醒时重新加载"开关 | [#39](https://github.com/sindresorhus/Plash/issues/39) [#127](https://github.com/sindresorhus/Plash/issues/127) [#154](https://github.com/sindresorhus/Plash/issues/154)。作者在 #39 评论里自己指出了 `interactionState` |
| **F1** | 在"必须两侧同时改"那段补一句：**CSS 侧永远改不了 `@media` 查询**，只有窗口侧 `setFrame` 缩小才会触发移动端布局 | [#93](https://github.com/sindresorhus/Plash/issues/93)，两条附议 |
| **F3** | 补一句：评论里的主流诉求是**每块屏不同 URL**，不是同屏铺满；社区已自建 `plash-cloner` 克隆 app 绕路 | [#2](https://github.com/sindresorhus/Plash/issues/2)，47 👍 / 36 评论 / 2026-08 仍在 bump |
| **F5** | 补一句：评论里还要求**按时间排班**（早晚不同页面） | [#4](https://github.com/sindresorhus/Plash/issues/4) |
| **P4** | 补一句：快照层替换会让靠 CSS 动效/滤镜吃饭的页面退化，必须按站点可关；[#193](https://github.com/sindresorhus/Plash/issues/193) 正文是现成回归用例 | #193 |
| **P2** | 补一条验收项：恢复可见后视频要自己接着播 | [#196](https://github.com/sindresorhus/Plash/issues/196) |

### 加进第七节「工程（E 系列）」

| | 事项 | 状态 |
|---|---|---|
| **E15** | 首启引导：现文案还在说"droplet icon"、还在替上游解释多显示器限制，两处都是错的 | 待做，S。[#7](https://github.com/sindresorhus/Plash/issues/7) |

### 加进第十节「明确不做」

| | 方案 | 否掉的理由 |
|---|---|---|
| **X7** | 摄像头 / 屏幕采集输入（`getUserMedia`、`getDisplayMedia`） | entitlement 是进程级的，等于给一个 24 小时渲染任意用户 URL 的进程永久配上取摄像头的能力；壁纸 app 的权限列表越短越可核查。采集卡合成走 OBS，监控走 NVR 客户端。上游 [#125](https://github.com/sindresorhus/Plash/issues/125)，3 👍 |
