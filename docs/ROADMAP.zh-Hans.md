# Nifro 路线图与工作台账

[English](ROADMAP.md)

> 范围的唯一事实来源。README 是面向社区的说明，这一份是我们自己的工作文档。
> 2026-08-27 对着 `54cac6a`（v0.1.3）重写。下面每一条都拿代码核过。已经做完的条目是删掉而不是划掉——
> 只有那种「删了就会被重新问一遍」的一行残留留在第 14 节。
>
> 第 8 到 11 节于 2026-08-27 对着 `53f110b` 这棵树重新核过——它是 `54cac6a` 加上 #24 到 #30，
> 再加 `fix/docs` 上的两个提交。关掉三条、新开四条，另有若干就地更正。关掉的每一条都是照着
> 现在的代码读出来的；没有一条是照提交信息关的，而 K12 和 K28 都从「读起来像是已经修好」的
> 提交里活了下来。

**这份文档反复犯的那个错。** 在写下「没人看过」之前，先读调用方。这里每一条最后被证伪的断言都是这么错的，
而读代码的成本，比它一直在等的那台硬件低得多。

---

## 1. 这是什么

Nifro 把网页放到桌面壁纸上，一块屏幕一个页面。分发走 Homebrew cask 加 GitHub Release，不上
Mac App Store。

**v0.1.3 之后的处境。** 菜单栏菜单被按显示器分列的面板取代（#21）。这一步是对的，而且只落地了一半：
现在选网站是在面板上，而旧菜单能做的十一件事没有任何入口（第 8 节）。这份文档里还开着的东西，
大部分要么是这些接线，要么是被面板照出来的问题。

```
未完成    W1-W9 接线   K1 K6 K8 K12 K16-K18 K20-K24 K26-K31 K33-K38 缺陷   L1-L4  V1-V5  S1 S2 S4  D4 D6  E21-E23  U2 U3
搁置      K7 HDR（你的决定）、P 系列（要先有测量）
阻塞      无
```

---

## 2. 功耗（P 系列）

全部已从代码里移除——删掉 811 行，回到上游的做法：页面就是在渲染，只在被禁用、锁屏、用电池时停。
它们每一个都掌握着「此刻在渲染什么」这个答案，而这正是 Browsing Mode 也要改的答案，于是每修好一处
就冒出下一处。

在任何一块回来之前，必须先满足：

1. 对它声称要省掉的成本做一次测量，在机器空闲时、针对它真正瞄准的状态——被遮住的壁纸，而不是浏览会话。
2. 「此刻在渲染什么」有且只有一个所有者。这是之前每个版本都栽在的地方。
3. 一个不需要解释就能用的关闭开关。

上游只因三个原因停，对遮挡完全不处理。这是这件事必须先超过的基线。原设计里有两个想法是**拒绝**而不是
推迟，现在作为 X10 和 X11 放在第 12 节。

---

## 3. 块：把页面变成桌面的一部分（L 系列）

Zoom 回答的是「页面的哪一部分」。块回答的是「它放在桌面的什么位置」——因为一个放大后的片段通常该待在
角落，而不是铺满全屏。真实的场景是一个只存在于网页上的数字：用量计数、构建看板、部署状态，
不会有人为它做一个小组件。

机器大都已经在了：scene 拥有窗口，`Zoom` 挑区域，`DesktopWindow` 能设任意 frame，多个 scene 本来就能同时跑。

| | 条目 | 说明 |
|---|---|---|
| **L1** | 网站在它的显示器上有位置和尺寸，而不只有一台显示器 | 像 `Zoom` 一样按比例存，换显示器时块还在。今天 `Website` 上没有位置/尺寸字段；`DesktopWindow.reducedRegion` 还在，而且仍然没有任何地方写它 |
| **L2** | 一个四宫格用来吸附，其余情况自由摆放 | 网格是可供性，不是模型。自由摆放才是模型 |
| **L3** | 网格用整屏还是避开 Dock | 一个设置项。**没有这一行原先说的那么便宜**：`pageFrame` 是 `frameWithoutStatusBar`，而 `visibleFrame` 在整个 app 里只出现在一处，在 `menuBarStripHeight` 内部。目前没有任何地方算得出「避开 Dock 的矩形」 |
| **L4** | 点击落在哪个块上 | Browsing Mode 和按住交互现在指的是**某一台显示器**的壁纸。有了块之后，它们得指某一个块 |

**三个约束，先写下来，免得以后才发现。**

- **两个东西在决定同一个窗口的尺寸。** 块必须是窗口的**基准** frame，遮挡在它内部收缩，绝不能反过来。
  正是这个冲突让裁剪和可见性策略互相争夺，直到裁剪彻底不再移动窗口。
- **一个块一个 web 进程**，而且自从按网站分数据存储落地之后，还多一份数据存储。
- **块不是用户能抓住的窗口。** 那一层没有标题栏。摆放只能在壁纸之上进行，或者从网格位置的菜单里选。

**L1–L4 从已发布的区域选择器那里继承的两个坑。**

- **模型是「框在动，页面不动」**，不是 Photos 那种「内容在动」。网页自己会平移和缩放，所以一张会动的画面
  有两种读法，而且页面自身的放大倍数会和框的倍数相乘。推导过程在 `Zoom/CropSelectionView.swift`。
- **`Geometry.resizedFrame(byGrowing:)` 是故意围绕框自身中心放大的。** 跟随指针的缩放会在页面静止时
  把框从指针底下滑走。不要再加回去。

覆盖层的职责是吞掉 scroll 和 `magnify(with:)`，让手势移动框而不是页面——`webView.allowsMagnification`
是开着的。`hasPreciseScrollingDeltas` 用来区分触控板（滚动=平移，捏合=缩放）和滚轮鼠标（滚轮=缩放）。
拖拽在任何设备上都是移动。

---

## 4. 页面记住了什么（M 系列）

声音和取景区域属于网站。**页面**在它自己内部的位置属于页面，它有四种存法。

- **M1** `localStorage` / IndexedDB —— **能留下。** 存储按网站条目（`website.id`）分，不是按 origin 分，
  所以同一站点的两个条目之间什么都不共享，删掉条目就丢掉它的存储。孤儿存储在启动时回收。
  *还没人写下来的后果：*给一台原本没有条目的显示器做同步，会新建一个 id，因而是一个空存储，
  于是 follower 在 leader 已经登录的站点上处于未登录状态。
- **M2** URL 片段 —— **能留下。** *坑：*最后加载的地址存在网站自身地址**旁边**，绝不覆盖它，
  而且只在两者「除片段外完全相同」时才使用。覆盖曾经把一个网站变成 GitHub 404。见 K28——挂起之后它就不再记录了。
- **M3** 文档滚动 —— 能撑过一次 reload，撑不过退出。只在 `reload()` 时捕获。
- **M4** 只在内存里 —— 无解。
- **M5** 一半在地址里一半在内存里（floor796）—— *在哪儿*能回来，*多近*回不来。
- **M6** 不去记住页面，而是留住页面 —— **只是提案，没有任何实现。** 在 app 的一次运行之内是完整的，
  超出这个范围就没有了。按网站开关。`releaseWebView` 现在做的正相反：挂起时把进程丢掉。

**绕过 M5 的两条路，都不急，而且互不冲突。** **B** 是把 M6 做成按网站的开关：它对每个站点都有用，
不依赖任何站点的内部实现，还顺手让「切回来」不再是一次页面加载。**C** 是给某个目录条目加
`pageWorld: true`：站点自己的放大倍数能撑过重启，代价是那个条目失去隔离，并且依赖 floor796 的私有字段。
C 必须始终是按条目的选择加入、默认隔离，绝不能改成全局换 world。app 自己的脚本（音频控制和媒体时钟）
无论如何都待在 `.defaultClient`。

**值得在 app 里明说的一句：**网站的设置是按网站走的，而页面在它自己内部的位置由页面决定。现在没有任何地方告诉用户这件事。

---

## 5. 多显示器（D 系列）

写在一台单显示器机器上。凡是读代码能回答的都已经读过了，而且大部分要么是错的、要么早就坏了——
那些修复在第 14 节。只剩两条必须靠硬件才能定。

| | 断言 | 什么能证明它是错的 |
|---|---|---|
| **D4** | 在没有菜单栏的显示器上的菜单栏色带 | 判据是 `screen.statusBarThickness > 0`，副屏这种情况已经有测试。未知的是「显示器有各自的空间」对 `visibleFrame` 做了什么，那是操作系统行为，从这里读不出来 |
| **D6** | 不同缩放比例、不同尺寸并排 | app 里没有任何地方按 backing scale 分支；每屏布局是 `pageFrame` → `DesktopWindow.setFrame`。没有可读的代码会出错，只有像素会 |

D7 原本在这一节，但它不属于这里：它是有明确修法的缺陷，不是没核过的断言。它现在是 K31。

---

## 6. 站点目录（S 系列）

`CANDIDATES.md`（候选池）→ `sites/*.yml`（过 schema 校验的目录）→ `featured: true`（首次启动即安装）。
每一个条目都是 agent 从一个链接加一次猜测写出来的，而 featured 的那些会在陌生人第一次启动时自己装上。

| | 条目 | 说明 |
|---|---|---|
| **S1** | 维护者审一遍 featured 条目 | **先做这个。** 它们是新用户在判断这个 app 好不好之前看到的东西。一个晚上的活，也是这份文档里性价比最高的一小时 |
| **S2** | 维护者审一遍目录里其余的 | 风险低一些，但承载着同一个断言：它们的设置是对的 |
| **S4** | 读者落到 `sites/` 上，先看到的是贡献指南 | 完成一半——两个 README 现在都直接链到 `CANDIDATES.md`。不要再加第四份同样数据的呈现：app 里的 Site Gallery 就是那份可读清单。让那两个 markdown 文件在开头就说清自己是干什么的 |

**这是一条规则，不是一个条目：**候选池会一直比目录大。这是常态，不是待清的欠账。永远不要把它的数量写进正文——
顺带一提，这一节原先在写下这条规则三段之后，自己违反了两次。

---

## 7. 面板的媒体控制（V 系列）

**先读这段再看表。** 这里的每一行原先都在把 `MediaSync`（多显示器同步）当成正在运行的东西来描述。它们
一个都不在代码树里：没有时钟、没有 epoch、没有读数、没有页面内脚本。`mediaClock()` 和 `mediaClockCode`
这两个名字被这些行当成「可以去读的代码」写着，而它们在 `Nifro/` 里根本不存在。这个功能留下来的只有
`docs/shelved/MULTI-DISPLAY-SYNC.md`，那份文件第一行就写明它已从 app 移除、不参与任何构建。所以这里
没有哪一行是「已建一半」——每一行都排在「把那套东西重建起来」之后，下面各行说明各自需要其中的哪一部分。

| | 条目 | 已知情况 |
|---|---|---|
| **V1** | 在某一列上暂停、播放、前后步进 | 什么都没有，检测也没有：`Nifro/` 里没有任何地方读 `<video>`，所以「这一列有没有视频」今天答不了。两半都得从头做。检测是被搁置的那段脚本里的一行——取时长有限的最大那个视频。传输那半连在那份设计里也没做过：它只写一个 epoch，由页面自己算出并执行跳转，所以暂停、播放、步进是要新加的消息类型，不是复用现成调用 |
| **V2** | 画面下方的进度条 | 前提有一半已经有了，而且是便宜的那一半：`DisplayPanelModel.startLiveRefresh` 本来就是面板打开时跑、关闭即取消，读数有现成的循环可搭。读数本身不存在 |
| **V3** | 在同步组里一个控制意味着什么 | 根本没有同步组。最后一条提到同步组的规则是在 `WallpaperScene.shouldPlaySound` 那里删掉的，那条注释也写明了设计去了哪里。先读 `docs/shelved/MULTI-DISPLAY-SYNC.md` 的第 4 节——那是这个功能被撤掉的缺陷清单；在决定拿什么替代它们之前，这一条无法定义 |
| **V4** | 直播流没有传输条 | 没有任何东西在报告它，因为没有任何东西读 `<video>` 的 `duration`。这个有限性判据只有一行，会跟着 V1 的检测一起回来；这里没有单独的工作量 |
| **V5** | 保存某一列正在显示的画面 | 完全没做。按一下把当前帧写到桌面，按住超过一秒则写一小段 GIF。**按显示器自身分辨率**——面板的快照是 260 点，所以这需要第二条全尺寸路径，只在被请求时才走，4K 上大约每帧 600 毫秒 |

**V1 和 V2 共同的前提**是一个页面内的上报器，而它并不存在，也就无从调。面板自己的循环是 80 毫秒，
不是瓶颈；新鲜度的上限取决于一个页面能被问多勤，而那是一段还得有人去写的脚本。被搁置的那份设计是
每 1000 毫秒向上报一次、每 250 毫秒纠正一次——那是起点数字，不是对任何正在运行的东西的测量。
**V5 的 GIF** 需要按全分辨率把帧留住——4K 显示器一秒钟就是几十兆，所以它要的是帧预算和硬性上限，
不是「直到用户松手」。

---

## 8. 面板重构还没接上的东西（W 系列）

菜单有、面板没有的能力。这些都不是坏掉的代码，是没有入口的东西。每一行的基线都是
`git show 54cac6a~1:Nifro/App/Menus.swift`。

| | 消失的 | 今天怎么够得着 |
|---|---|---|
| **W1** | 全局启用 / 禁用 | 只剩全局快捷键和 Shortcuts intent。UI 里没有任何控件，这正是 K22 严重的原因 |
| **W2** | 明说「已因电池而停用」 | `Screens/` 里没有任何地方读 `isEnabled` 或 `isManuallyDisabled`。壁纸消失，面板一声不吭。**#53 之后更糟**：原本解释它的那句状态串是被删菜单留下的孤儿，随其余一起删掉了，所以现在没有任何文字提到这个行为——而它是设置里那一节唯一没有 ⓘ 的一行 |
| **W3** | Reload | 只有快捷键和 `nifro://reload` |
| **W4** | Random——立刻随机跳一个 | 面板的 `.random` 轮换模式只影响定时器的 tick |
| **W5** | "Update Website to Current" | **整个仓库里都不存在了。** `AppState.swift:32-33` 声称它「搬进了网站自己的设置」；并没有。那条注释是假的，而这是 M2 的手动那一半 |
| **W6** | 从名字进入「编辑这个网站」 | 面板上的名字那一行不是按钮。**那条半死的路径是删掉了，不是继续摆着：**`.showEditWebsiteDialog` 和它的观察者都已删除——观察者打开的是 `AppState.currentWebsite`，也就是无论请求从哪块屏幕来都取主显示器的网站，于是把它重新接到面板上，只会在用户盯着外接显示器时打开笔记本上的那个网站。要接上这条线，需要的是一条按显示器的路径，而不是把这个通知重新声明一遍 |
| ~~**W7**~~ | ~~把网站挪到另一台显示器~~ **已完成**，方式是取消这个问题：网站是 playlist 的成员，显示器选 playlist。 | 只在网站编辑弹窗里。加上 K17，从面板出发没有任何路径能把网站放到某台显示器上 |
| **W8** | 快捷键的可发现性 | `setShortcut(for:)` 没了；面板按钮只有 `.help()` 文案。`Shortcuts.swift:8,15-16` 还在论证「之所以配了默认快捷键，是为了让菜单能显示它们」 |
| **W9** | 菜单留下的脚手架 | `SSMenu`、以及 `WebsitesScreen` 里那个空的 `.onChange` 和空的 `.onAppear` 都已删除。剩下的是 `CallbackMenuItem.validateCallback`：从未被赋值，所以 `validateMenuItem` 恒为 `true` |

W1 和 W3 是让 app 从面板上看起来最不完整的两个；W5 丢的是功能本身，不只是入口。

---

## 9. 已知未修（K 系列）

| | 现象 | 已知情况 |
|---|---|---|
| **K1** | YouTube 视频没法缩回 YouTube 页面 | 地址被改写成纯播放器页（它的播放器在自己是文档而不是 frame 时会报 error 153），所以没有页面可导航，Browsing Mode 也无处可点。**但登录是做得到的**：把地址改成 `youtube.com/watch`，登录，再改回来——cookie 存储按 `website.id` 走，不跟着地址变。没人告诉用户这件事。修法是一句帮助文案，不是新 UI。这里做任何改动都必须继续避开 153 |
| **K6** | 帮助文案有的地方到位，有的地方单薄 | 这次数清楚了：**30 处**——23 处 `.explained(…)` 加 7 处 `.help(…)`，分布在三个界面共 2838 行里。之前那个「七处」错了四倍。值得整体过一遍，但这是 30 条文案的活，不是小活 |
| **K7** | 全 app 没有任何地方处理 HDR | **搁置，你的决定。** 已扫描确认：没有 API、entitlement 或 plist 键涉及它；唯一的匹配是菜单栏取色器里的一个色彩空间选项，以及某个站点名字里的 "HDR" 三个字母。要先有真实 HDR 源和一次「究竟什么送到了显示器」的测量，才谈得上设计 |
| **K8** | Bilibili 条目只有通用图标，YouTube 条目有视频封面 | YouTube 的封面能从视频 id 推出来；Bilibili 的在 `api.bilibili.com` 后面（`data.pic`）。只影响 Websites 列表的行图标——`previewImageURL` 只有一个调用方。这会是 app 第一次调用站点 API 而不只是加载页面 |
| **K12** | 裁剪进行中重建 scene 的 content view，会把那个窗口永久钉在最上层 | **已重新定位：不需要第二台显示器，而且从来就不需要。** 覆盖层是 `window.contentView` 的子视图，而没有任何地方保护 `applyContent` 不在裁剪进行中执行——于是任何一次重建都会把覆盖层摘下来，而它是唯一能调用 `onFinish` 的东西。窗口保持 `.floating` 和完全不透明，`beginCropSelection` 从此永远拒绝。**在 `a332dae` 和 `53f110b` 的取景改动之后重新核过，它们没够到这里：**`installContentView` 现在在 `isFramingRegion` 时传 `nil`，`applyOpacity` 现在也不动正在取景的那个窗口，但 `content` 的 `didSet` 是按赋值触发而不是按变化触发——于是那次重新赋值照样走到 `applyContent`，照样写 `window.contentView`，照样把覆盖层一起带走。「可交互」这一项已经从症状里去掉：`rebuildScenes` 路过时会按 Browsing Mode 重新赋 `isInteractive`。`DisplayPanelModel.chooseRegion` 在 `beginCropSelection` **之前**紧挨着调用 `makeCurrent`，而那次写入是在**下一个** runloop 回合才到达——也就是覆盖层装好之后。对于已经有区域的网站，也就是这个功能存在的理由，摘下来是必然的 |
| **K16** | 同步一台显示器会吃掉它原来的网站，并留下一份副本 | `mirrorAcrossSyncGroup` 就地覆盖 follower 的条目，所以那台显示器原本显示的页面是被删掉而不是被搁置，没有任何办法找回。在维护者自己的列表上量过：八个条目里六个是副本，两个原始条目不可恢复。追加的副本上限是「每台起初为空的 follower 显示器一个」，而且永远不会被删除。两半是同一个决定：镜像条目是 leader 的一个**视图**，不是独立的网站，它根本不该出现在列表里 |
| ~~**K17**~~ | ~~某台显示器上的网站选择器只列出那台显示器自己的网站，通常只有一个~~ **已完成。** 显示器选 playlist，选择器列的是那个 playlist 的成员，`effectiveDisplay == scene.display` 连同它读的那个字段一起删掉了。这条说「这个控件是用来选任意网站**并把它搬过来**」——答案换了个形状：没有东西需要搬，因为没有东西再属于某块屏。 | 过滤条件是 `effectiveDisplay == scene.display`，而网站获得显示器的方式就是在那儿被选中——于是菜单只有一项，看起来像坏了。被删掉的菜单遍历的是整个列表，它的注释说这是**刻意的**，所以这是回归而不是设计变更。这个控件的用途是选中任意网站**并把它挪过来** 设计写在代码之前，见 `docs/PLAYLIST-REFACTOR.md`。 |
| **K18** | 同步纠正会让画面卡顿 | 在 WebKit 上每次改 `playbackRate` 都有一次可见的顿挫（bug 208142）。任何调参之前，先在真实流上数出每分钟发生多少次速率变化；如果次数高，答案是放宽 `engage`，不是缩小 `nudge` |
| **K20** | 面板每秒截图十二次，而且没人看得见时还在继续 | **你提的这条。** 关掉面板确实会停——所有关闭路径都会到达 `popoverDidClose`。但仍有两处不对。循环 sleep **80 毫秒**，也就是每秒 12.5 轮、每轮每台显示器一张快照，而旁边的注释写的是 "a few a second"，快照那边自己的注释写的是 "roughly once a second"。而且停止条件是**已关闭**，不是**可见**：transient popover 只在外部交互时自关，所以它能挺过锁屏、显示器休眠、切换 Space 和 Mission Control，全程以 12.5 Hz 转 SwiftUI 树。`startLiveRefresh` 上的注释仍然声称没人看的时候这里什么都不跑。修法是降低频率加一个遮挡或锁屏判断，顺手在各 scene 之间加一个 `Task.isCancelled`，免得中途关闭还多推一帧 |
| **K21** | 面板预览显示的是整个放大后的页面，不是取景区域 | `snapshot()` 没有传 `rect`，于是抓的是 web view 的完整 bounds——而在区域模式下 `PageView` 把那个 frame 设成放大后的整页再裁切。结果是列上显示整页缩到 260 点，显示器上显示的却是其中一片。`refreshMenuBarBandColor` 已经演示了正确写法：把 `configuration.rect` 设成区域与 `webView.bounds` 的交集 |
| ~~**K22**~~ | ~~app 被禁用时，面板的电源按钮显示「开着」，按下去反而关掉显示器~~ **已完成。** 那一列和它的电源键问的是 `isSwitchedOff`，所以 app 被禁用时一列不会读成「开」，按下去也不会把「关」写到一台用户正想打开的显示器上。app 关着时把某台打开，只是记下这个设置、屏幕仍然是黑的——这本来就是 `setDisplayEnabled` 承诺的事。 | 那一列读的是 `!scene.isDisabledForDisplay`，从不参考 `AppState.isEnabled`。开着「用电池时停用」拔掉电源：所有壁纸消失，每一列仍画成 Showing，按下电源按钮传入 `false`，把那台显示器**关掉**。而 W1 缺失，于是从面板里没有任何办法把 app 重新打开 |
| **K23** | 网站选择器不会唤醒已关闭的显示器，上面两行的箭头却会 | `step()` 会先重新启用，还带着解释为什么的注释。`show()` 只是裸的 `makeCurrent`，没有这个保护，于是在已关闭的显示器上选网站只会改标题、屏幕依然空白。同一列里的两个相邻控件对「选一个网站」是什么意思给出了不同答案 |
| ~~**K24**~~ | ~~轮换箭头可能亮着却按不动~~ **已完成。** `canRotate` 就是 `eligible(in:).count > 1`——和箭头走的是同一个表达式、同一个解析出来的 playlist，不再是另一处忽略排班的计数。 | `canRotate` 按显示器数网站；轮换走的是 `eligible(for:)`，也就是那个集合与排期的交集。一台显示器上有两个网站、其中一个排 08:00–18:00，到 22:00 两个箭头都是亮的，按下去什么也不发生。`RotationMode` 自己的文档承诺固定期间箭头依然可用 |
| ~~**K25**~~ | ~~每日更新检查写进了一个没人读的键~~ **已由 #53 完成。** 面板页脚只在有新版本时长出一个下载按钮，设置里那句话指向它。 | U1 随 #18 落地，它的被动提示面做在 `Menus.swift` 里；#21 删掉了那个文件，没给这个条目重新安家。`latestKnownVersion` 现在只写不读——每 24 小时一次网络请求，结果从不展示——而 `SettingsScreen.swift:78` 还在承诺「Nifro 会在菜单里提到新版本，别处不提」。要么在面板底栏加一个提示，要么删掉每日任务；两样都不做是三个选项里最差的 |
| **K26** | 页面加载失败，报告在没人会看的地方 | 错误设置了状态栏图标的 tooltip，除非 Browsing Mode 开着，否则到此为止。面板从不读它，所以一个开始返回 500 的壁纸 URL 只会显示成 "No Website"，不给任何原因。被删掉的菜单是把错误放在最顶上的。**已重新定位：** 它要读的那份记录现在按显示器存、并跟着 scene 一起清理，所以剩下的是「一列能把它说出来」，不再是「这件事根本没人记」 |
| ~~**K27**~~ | ~~Browsing Mode 会把已关闭显示器的窗口重新调到前台~~ **已完成，而且原因不是那个循环。** `applyBrowsingMode` 早就是按 scene 读 `isBrowsingMode(on:)` 的；把窗口放回来的是 `orderBack`——它对在屏上的窗口是「放到别人后面」，对不在屏上的窗口是「显示出来」，而它在未抬起分支里被跑到了一个 `suspend()` 已经移出屏幕的窗口上。守卫加在那里的 `isVisible` 上，而不是加在「赋值是否改变」上——`rebuildScenes` 对每个窗口都写同一个属性，`bringBrowsingModeToFront` 的订阅者还故意把它赋值给自己好让这个分支再跑一遍，所以守在值上会静默地让那个设置失效。**已在两台显示器上实测**：外接关闭时，修之前在切换那一刻从「不在屏上」变成「在屏上」，修之后全程不在屏上；同时 Browsing Mode 仍然抬起它自己那台，`bringBrowsingModeToFront` 仍然到 `.floating`，关掉仍然回到桌面层。 | `applyBrowsingMode` 遍历**所有** scene，包括已挂起的，而 `isInteractive.didSet` 每次赋值都会调 `makeKeyAndOrderFront`，哪怕值没变。窗口是透明的所以症状不重——除了对 `allowsInteraction` 的网站，它会不再让点击穿透；而通过全局快捷键触发时，它会以 `.floating` 出现在用户已经关掉的那台显示器上 |
| **K28** | 任何一次挂起之后 M2 就不再记录 | `releaseWebView` 会新建一个 web view，而两边都没有重新订阅 `addressObserver`，于是它仍绑在已经消失的那个 web view 上。禁用/启用、锁屏、电池切换、按显示器开关之后，那个 scene 再也不会记录它的页面把自己挪到了哪里。`reload()` 是直接捕获的，这掩盖了带 reload 定时器的页面的问题。改一行 |
| ~~**K29**~~ | ~~四条 `WKUIDelegate` 路径仍在用全局 Browsing Mode~~ **本来就已经修好了**，是这个条目活过了它：四条路径全都取 `isBrowsingMode(on: scene?.display)`。 | `createWebViewWith` 以及 confirm、prompt、open 面板读的是 `isBrowsingMode`，含义是「任意一台显示器」；同一文件里的两条导航路径已经改成按显示器的形式，这四条被落下了。笔记本上开着 Browsing Mode 时，显示器壁纸上的 `window.open()` 会被接受，替掉一个没人在交互的页面 |
| **K30** | 缩略图缓存不清扫、不受预算约束 | `DiskBudget` 每六小时按 100 MB 预算清扫两个 WebKit 根目录。`websiteThumbnailCache` 不在其中任何一个：在 `~/Library/Caches/Nifro/` 下每个 key 一个文件，没有数量上限、没有大小上限、没有按时间清扫，唯一的删除路径是「清除所有网站数据」按钮。key 是 URL，所以改地址或删网站会永久留下孤儿文件——`removeOrphanedStores` 是按网站 *ID* 保留、而且只够得着 WebKit 的数据存储，缩略图永远没有东西来收。上限是「列表里出现过的不同 URL 数」，所以不会失控——但它对现有的那个预算是不可见的。两行：把这个目录加进 `sweptRoots`，或者拿孤儿清扫那套对着缩略图 key 再用一次。**落盘格式是另一个问题，它一条都关不掉。**换更省的编码只是让每个文件更小，而没有上限的目录仍然没有上限；它也不会让已经在盘上的东西变小，因为 `IconView.fetchIcons` 命中缓存就直接返回、而命中是从磁盘读的，所以写过一次的文件永远不会被重写，换格式只会让旧文件和新文件长期并存 |
| ~~**K31**~~ | ~~同一个 URL 的两个条目在两台显示器上会互相覆盖页面位置~~ **已完成。** 现在按 `Website.ID` 键，而且从 URL 生成键的那条路径是删掉而不是留着没人用，所以不可能再产生地址形状的键。已存的滚动位置丢了一次，正如这条自己接受的。**它还付出了这条当初没预见的代价：** 旧的键要问每一类「`?panel=2` 算不算另一个页面」，而 `id` 问不出这个问题——于是在 Browsing Mode 里点链接到达的页面，现在和条目共用同一份记录而不是各有一份，恢复的是最后被滚动过的那个页面。影响有界且会自我修正，但这是行为改变，不只是换个键。另外被删掉的网站的记录现在也会被清扫了，和数据存储一起、依据同一份列表；在此之前只有「清除一切」那个按钮会动它们。 | 原 D7。按页面的记录（`scrollPosition_`、`lastAddress_`、`zoomLevel_`）按 URL 存，而数据存储按 `website.id` 存。**同步组让这成为常态而不是边角情况**：每个组都会为每台 follower 显示器新建一个带着 leader URL 的条目，于是 ≥2 个 id 不同、URL 相同的条目共用同一套记录。修法是改按 `website.id` 存，代价是已保存的位置丢一次 |
| ~~**K32**~~ | ~~UI 还在让人去用一个不存在的菜单~~ **已完成**，由 #40 和 #53 解决。在 `112e9a2` 上重新数过：目录里剩的四条含「menu」的字符串全指菜单栏*图标*，那是真实存在的。 | **六处，是数出来的不是估的：**欢迎页的「点它的图标并选择 Add Website…」和「在同一个菜单里」、区域设置的「Nifro 菜单里的 Choose Region…」（面板上它叫 Crop）、声音设置的「和 Nifro 菜单里的 Sound 是同一个设置」、更新设置的「在菜单里」，以及隐藏图标设置的「如果你需要访问 Nifro 菜单…」。这一行原先说的第七处、目录里的那一处，并不存在。**矩形也已经没了：**区域帮助文案描述的是移动和缩放壁纸，那就是 L0 的模型，也是对的那个 |
| **K33** | 菜单栏色带采样的位置，和页面实际布局的位置差最多一个缩放因子 | 窗口被刻意设成 `pageFrame.height + 1`，而 `pageLayoutSize` 就是 `pageFrame.height`。`PageView` 从实时 `bounds` 推导，`topStripOfWallpaper` 从 `pageLayoutSize` 推导。和 K2 是同一类差一个点的不一致，而且发生在唯一没有测试的那个界面上 |
| ~~**K34**~~ | ~~按住交互键时移动指针，会把起手那台显示器晾在那儿~~ **本来就已经修好了**，是这个条目活过了它——包括下面那句「在这棵树上仍然能复现」。`HoldToInteract` 在 `begin` 存下 scene，`end` 用的就是那一个。 | `HoldToInteract.begin` 给 `actingScene.display` 打开 Browsing Mode，`end` 给 `actingScene.display` 关掉，两次都是运行的那一刻现问的。松手时人在另一块屏幕上，于是被关掉的是第二台——它本来就没开过——而第一台继续可交互，没有任何东西按着它，只能靠切换快捷键收回来。显示器必须在 `begin` 时记下来，不能到 `end` 再问一遍。**有一条自己的分支在处理它；在这棵树上它仍然能复现，所以照实写在这里，而不是假定它已经没了** |
| **K35** | 显示器正在重新配置的那一小段时间里，两张全屏壁纸可能叠在同一块屏幕上 | `Display.main` 是套在 `CGDisplayCreateUUIDFromDisplayID` 上的可失败初始化，它会在几十毫秒里返回 `nil`——正是 `Display.underMouse` 已经写下来的那个窗口。在那段时间里，没指定显示器的网站 `effectiveDisplay == nil`，而 `isShowable` 仍然说「该显示」——整条链都是 `nil` 时 `(display ?? .main)?.isConnected != false` 为真——于是 `displaysInUse` 里可以同时装着 `nil` 和一台真实显示器。`rebuildScenes` 给两者各建一个 scene，而两者解析屏幕都走 `Display.mainScreen`，于是同一块屏幕上有两个壁纸窗口、两条菜单栏色带、两套定时器。下一次 `NSScreen.publisher` 事件会让它自愈。**是推出来的，从未复现过：**那个窗口短到手工撞不上，这也是它出错代价低的原因 |
| ~~**K36**~~ | ~~一台显示器的加载失败，会被另一台显示器的例行重载抹掉~~ **已完成。** 记录按显示器为键、跟着 scene 一起清理，状态栏 tooltip 从三个写入方收敛成一个，所以一台显示器上跑完的加载既抹不掉也盖不住另一台的失败。图标说的仍然是「有没有」而不是「哪一台」——那是 K26。 | `AppState.webViewError` 是一个全 app 唯一的槽位，却是按显示器写的。`load()` 会为正在加载的那个 scene 把它置 `nil`，于是外接显示器上的一次重载定时器，就把「笔记本上的页面开始返回 500」这条记录扔了。状态栏图标的 tooltip 是同一个槽位的另一头：`report` 把错误写上去，而下一个加载完成的 scene 会把它自己网站的 tooltip 盖上去。两者都不说这是哪台显示器。K26 说的是根本没人看得见这个错误；这一条说的是这个错误只有一份 |
| **K37** | 已经彻底不会再回来的显示器，它的按显示器设置永远不会被忘掉 | `rotationModes`、`rotationIntervals`、`disabledDisplays` 和 `currentWebsites` 都按 `Display.settingsKey`（一台显示器一个 UUID）存，而没有任何地方删条目。对于「拔掉又插回来」的显示器这是对的，那正是当初选字典的理由；但对于一台已经卖掉的显示器，没有任何办法忘掉它。每台接过的显示器一个小条目，任何地方都看不见，所以这是整洁性问题而不是缺陷——值得留一行，免得以后被当成泄漏重新发现一遍。`browsingDisplays` 是例外：`Events.swift` 会把它整个清空 |
| **K38** | 每次定时重载都起一个新的 WebContent 进程 | 定时重载走 `reload()` → `loadBySwapping` → `createWebView()`，后者新建一整套 `WKWebViewConfiguration`、全部 user script，**以及一个新的 `WKWebsiteDataStore(forIdentifier:)`**——等于每次起一个新渲染进程和新网络会话，再把上一个扔掉。请求还带 `.reloadIgnoringLocalCacheData`，所以子资源全部冷取。15 分钟的条目 × 2 块屏 ≈ **192 次进程启动/天**。修法是替换 URL 与已加载 URL 相同时原地调 `reloadFromOrigin()`——那正是定时重载这条路，区别于切换网站。**仅在这条路上放弃的东西：** swap loading 的失败隔离——Mac 唤醒后网络还没起来时的失败重载会显示错误页，而不是静默保留最后一个好页面。动手前先测：`powermetrics --samplers tasks` 过滤 `com.apple.WebKit.WebContent`，两屏 15 分钟间隔跑一小时，对比改用 `reloadFromOrigin()` 的构建，重载前后各跑一次 `pgrep -c WebContent` |
| **K39** | 设置里的全局重新加载间隔对几乎所有网站都不生效 | `Website.effectiveReloadInterval` 是 `reloadInterval ?? Defaults[.reloadInterval]`，编译器说右边永远用不到。两边都是 `Double?`，本该走可选重载——但 `Defaults[.reloadInterval]` 经过包里的泛型下标，把重载解析推到了 `T ?? T`（`T == Double?`），这个重载里左边是非可选的，默认值是死代码。**量过而不是读出来的：** 把右边换成普通的 `Double?` 字面量，警告消失；换回下标，警告回来。于是没有自己设间隔的网站得到 `nil`，`resetTimer()` 在 `let reloadInterval =` 那个守卫处返回，定时器根本没装。这个设置画得出来、存得下去、谁也到不了。修法是用 `if let` 而不是 `??`——这也顺便挡住下一个 `Defaults` 默认值被同样吞掉 |


**这里面有六条是同一个形状。** K22、K26、K27、K29、K34、K36 是按六份互不相干的报告写下来的，其实是
一件事：一个只对**某一台显示器**成立的事实，被放进了只装得下一个答案的槽里；或者在按显示器的问法
已经存在的地方，去问了整个 app。这也是为什么一条一条修总能修好、又总会漏下兄弟——Browsing Mode 的
按显示器读法落到了 `WebViewController` 和 `HoldToInteract`，而面板的电源按钮和加载错误还是全局的，
上面还有两条的条目活过了自己的修复而没人发现。现在关掉了五条，剩下 K26——它要的是一个展示面，不是
一份记录。下一条这个形状的出现时，去找那个槽，不要去找症状；护栏在 `ScopeTests` 和 `SwitchedOffTests`。

---

## 10. 工程（E 系列）

| | 条目 | 状态 |
|---|---|---|
| **E21** | `nifro://` 被注册到了 app 的陈旧副本上 | **测试 URL 命令一律用 `open -a <path> "nifro:reload"`，绝不用裸的 `open "nifro:reload"`。** LaunchServices 把这个 scheme 记在这台机器上构建过的每一份副本上，包括 `~/.Trash` 和 derived data。仓库里没有任何东西导致它，也没有任何东西能修它。裸写法曾经让我们对着一个三周前的构建折腾了一下午 |
| **E22** | 把本地化迁到 Vorssaint 那套机制 | **新增，而且是重做而非缺陷。** Nifro 现状：`Localizable.xcstrings`，244 个键，2 种语言（英文是未翻译的源），写 `AppleLanguages` 并**强制重启**，外加一个 CI 脚本守完整性。Vorssaint：字符串就是 Swift——一个 892 个字段的 `struct Strings`，13 种语言各一个 `static let`，少一个字段就编译不过，因此不需要 CI 门禁；`L10n: ObservableObject` 发布选择，视图**无需重启**即刻重绘。迁过去是五步，第三步就是全部成本：(1) 用 `struct Strings` 加每语言一个值替掉 catalogue；(2) 加 `L10n`，带 `systemDefault` 映射和字面量 `displayName`；(3) **把约 30 个文件里的 244 处字面量改写成 `l10n.s.field`**，并让 AppKit 那几个界面——`DisplayPanel`、`PanelControls`、`Actions`——在切换时重建，而不是依赖 `AppleLanguages`；(4) 删掉重启对话框；(5) 删掉 CI 门禁，编译器接管。**会失去什么：**`AppleLanguages` 免费顺带本地化了第三方包的字符串（`LaunchAtLogin.Toggle`），Swift struct 方案够不着它们。为这些保留一个小门禁 |
| **E23** | 升级时用户配置的迁移 | **新增。** 没有这套机制。现有的是三样各管一个 case 的东西：`rotationInterval(stored:legacySeconds:)` 在新键缺失时读旧键，`@DecodableDefault` 给 `Website` 新增的字段补默认值，`SS_hasLaunched` 是欢迎界面的一次性标志。没有任何地方记录上次运行的是哪一版，也没有一个可以挂一次性升级步骤的位置。至今没出事，是因为还没有人从任何版本升上来——这同时也意味着它的形态还可以自由选。改动已发布的默认值是最能暴露这个缺口的 case。它不属于第 12 节：该做，而且该在首个正式版把每个选择变成永久之前做。|
| **E24** | 网站改为 playlist | **新增，也是计划中最大的一次改动。** 网站不再归属于某台显示器，改成显示器去选 playlist。设计写在代码之前，见 `docs/PLAYLIST-REFACTOR.md`：里面按 K 系列逐条数了它消解掉什么（K17、K24、W7）和它动不到什么（十四条，全是 web view、窗口和缓存的问题）。它还会把 K31 从边角重新变回常态——复制 playlist 是深拷贝，两份副本 URL 相同——所以 `PerPageDefaults` 改键是前置条件而不是顺手整理 |
| **E24** | 五条从未执行过的 lint 规则 | **和 #58 修掉的 periphery 配置是同一个形状。** `.swiftlint.yml` 声明了五条 `analyzer_rules`——`capture_variable`、`typesafe_array_init`、`unneeded_synthesized_initializer`、`unused_declaration`、`unused_import`。analyzer 规则只在 `swiftlint analyze` 下执行，那需要编译日志；而 Xcode 构建阶段和 `ci.yml` 跑的都是 `swiftlint lint`。**所以这五条从写下来那天起就是惰性的。** `unused_import` 本来能点名 #58 里手工删掉的那两个 import。接上它要付出 `xcodebuild ... | tee`、一次 `--compiler-log-path` 运行，以及多一个 lint job 的 CI 分钟数，换五条价值未经测量的规则——但一条不可能触发的规则读起来像是已经查过了。要么让它们跑，要么删掉这一块；声明了却不跑是三者里最糟的 |

**这是一个陷阱，不是一个待办条目：** 给 `Website` 加字段是一次会丢数据的改动，除非这个字段能从早于它的
载荷里解出来。整张列表是一个 `Defaults` 值，所以一条解不开的记录会把所有网站一起带走，而 `Defaults`
对解码失败的回答是「用这个键的默认值」——一个空数组。用户看到的是一个全新安装，而磁盘上的文件仍然
装着全部内容。

`@DecodableDefault` 读起来像是覆盖了这件事，它自己做不到。真正做这件事的是 `Extensions.swift` 里
`KeyedDecodingContainer.decode(_:forKey:)` 的一个重载，它把包装器转给 `decodeIfPresent`；没有它，
合成的 `init(from:)` 在包装器跑起来之前就抛 `keyNotFound`。那个 extension 曾经在「碰巧没有成员」时被
删掉，而这个缺口一直没人发现，直到下一个字段被加进来——因为一个字段只有在**它存在之前**写的记录里
才会缺席，所以已经在用这个包装器的那四个字段从来没有证明过任何事。`WebsiteMigrationTests` 现在同时
断言那个重载和那个包装器：「属性被包着」和「缺席能活下来」是两件必须一致、而没有别的东西要求它们
一致的事。


**这是一个坑，不是一个条目：**第四种按页面的记录必须是 `PerPageDefaults` 的一个 case——key 由它构造，
而清扫走的是 `allCases`。

---

## 11. 签名与分发

- **签名**用一张稳定的自签证书 `Nifro Signing`。稳定才是重点：它让 designated requirement 保持不变，
  而持有本地文件壁纸的 security-scoped bookmark 是绑在它上面的。ad-hoc 每次构建都换身份，会把它们弄坏。
- **公证**等有了付费账号再做。Nifro 是沙盒 GUI app，它的用户没有敲 `xattr` 的习惯。
- **发布**是打 tag 触发 Actions，每个架构一个精简 dmg。cask 就放在 `Casks/`，由 CI 写回。livecheck 开着。
- **一个 workflow 两条路径**，按 `secrets.MACOS_CERTIFICATE_P12` 是否存在来选。以后买账号的成本是六个
  secret 加删掉 cask 的 `postflight` 块，YAML 一行都不用改。完整手册在 `docs/RELEASE.md`。

没有账号时，双击 dmg 会被**直接拦下**——只有「移到废纸篓 / 取消」——而 brew 是干净的，
所以 README 的安装段落必须把 brew 放在前面。

**关于 tap 的两件事，都是刻意的。** 安装意味着要写出 tap 的 URL，而简写形式需要一个真的叫
`homebrew-tap` 的仓库。值得做的理由是带宽而不是简写：tap 会把这个仓库整整 6 MB 克隆到每个用户机器上，
并在每次 `brew update` 时重新拉取。等这变成别人的带宽问题时再做。裸的 `brew install --cask nifro`
意味着进 Homebrew 自己的 cask 仓库，那有知名度门槛——是一个值得留意的里程碑，不是一件要排期的任务。
**本节和 README 已经脱节两处：**安装现在还需要 `brew trust`，而 `Casks/nifro.rb:1` 写的是这个 cask
「供 PathGao/homebrew-tap 使用」，与本节说的「cask 就放在这个仓库」相矛盾。下次动 tap 这个议题时一起修。

**发布不可变性是关的**，而当初关它的理由已经过期：发布资产现在在发布时就不带版本号，正是为了让
`/releases/latest/download/…` 稳定，也就不再需要发布后改名。可以打开了。

| | 条目 | 说明 |
|---|---|---|
| **U2** | Sparkle | 现在不做。它需要一个 appcast feed 和一对 EdDSA 密钥——app 生命周期内要一直保管的第二套签名身份——而沙盒 app 没有 installer XPC service 就无法替换自己。**feed URL 从第一个带它的版本起就是永久的。** 今天改这个仓库的名字是免费的，那一天起就不再免费 |
| **U3** | cask 里的 `auto_updates true` | U2 一落地就是必须的，在那之前毫无意义：没有它，`brew upgrade` 和 app 会争夺同一个 bundle |

U1 已发布，然后在面板重构里丢了它的展示面——那是 K25，不是 U 系列的条目。

---

## 12. 明确不做（不要再提）

| | 提案 | 为什么被否掉 |
|---|---|---|
| **X1** | 换 web 引擎（Electron / Tauri / CEF） | WKWebView 是与 Safari 共享的系统进程，别的都更贵。问题在调度，不在引擎 |
| **X2** | 全部重写成纯 SwiftUI | `NSWindow` 加上在关键处用 AppKit，又快又正确 |
| **X3** | Tuist / XcodeGen | `project.pbxproj` 远没到冲突会痛的规模，手动加一个文件是四行 |
| **X4** | 依赖注入框架、插件系统 | 没有第二个实现，抽象没有依据 |
| **X5** | 只用 CLT 做类型检查门禁 | **试过，失败**：KeyboardShortcuts 用了 `#Preview`，那个宏插件只随 Xcode 分发 |
| **X7** | 摄像头 / 屏幕采集输入 | entitlement 是按进程给的，等于永久地让一个全天候渲染任意 URL 的进程能碰摄像头。这个 app 的权限列表越短越容易核查。它**技术上做得到**，难度不是理由 |
| **X8** | 渲染成图片交给 `NSWorkspace.setDesktopImageURL`（原 P6，以及旧第 2 节的 A2） | 是拒绝而不是阻塞：它会终结这个 app。这样设的壁纸是一张图片——不能点、没有 Browsing Mode、无法登录——而刷新它会让整个桌面交叉淡入。**而且它需要那个不可能存在的离屏渲染器：**离屏窗口会让 WebKit 报告 `visibilityState: hidden`，于是 `requestAnimationFrame` 永远不跑，canvas 页面拍出来是空白。在 JS 里覆盖 `document.hidden` 也没用。每一个「用快照当壁纸」的想法都死在这句话上 |
| **X9** | 把用户自己的 Chrome 窗口放到桌面层 | 拒绝。**没有公开 API 能设置另一个进程的窗口层级**——对着不属于我们的 connection 调 SkyLight 是 yabai 的路子，需要关掉部分 SIP。能做出来的那个变体放弃了图标层，并把壁纸的生命周期交给一个我们控制不了的 app：Cmd-Q 结束它、自动更新重启它，而且 entitlement 要扩到完整辅助功能并关掉沙盒。改用投屏更糟——DRM 视频送过来是黑的、帧是 JPEG，而且需要开着 `--remote-debugging-port`，等于把整个浏览器身份交给 localhost 上的任意进程。它的动机（继承登录态）本来就已有答案：WKWebView 的存储是持久的，通过 Browsing Mode 登录一次就一直有效 |
| **X10** | 内容铺满屏幕时转为不透明 | 省下的量测不出来，而且需要一个会在透明背景页面上把屏幕变黑的开关 |
| **X11** | 可配置的 reload 策略 | 没人提过。一个在找抱怨的设置项 |

---

## 13. 审查过并刻意保留

被否掉的结论比造出来的东西更容易丢失，所以这些留下来，免得下一轮又被提一遍。

| | 候选 | 为什么保留 |
|---|---|---|
| **R1–R3** | `SecurityScopedBookmarkManager`、`Cache` + `SimpleImageCache`、`WebsiteIconFetcher` | 各自调用点都很少。替换其中任何一个都是在信任边界上做等价重写，而且写错了没有任何检查会红。K30 说的是缺一次清扫，不是这几个类 |
| **R4** | 打开 gallery 时从 `main` 拉取的 `sites/index.json` | 条目带 `css` 和 `javaScript`，而新增一个条目是一次合并而不是一次发布——所以坏条目不经构建就能到达已安装的副本。**影响面比读起来窄，只有一次刻意点击那么宽**：`featured` 取自编译进去的快照，拉取到的条目里的代码只有在有人按下 Add 时才会进入 web view。保留，因为「版本之间到来的条目」正是它的意义所在。**把站点清单当作发布级别的界面来审** |
| **R6** | `DesktopWindow.reducedRegion` | 被读一次，从不被写。`periphery` 看不出来，因为这个属性被读了。保留是因为「把窗口缩到桌面的一部分」就是 L1，而这正是它需要的形状 |
| **N1–N2** | 循环改正则的批量重写，以及唯一验证是「类型检查通过」的改动 | 没有任何断言会变红 |
| **N3** | 两个动画时长 0.25 和 0.35 | 一个是不透明度过渡，一个是内容淡入。它们因不同原因而变，合并等于制造耦合 |
| **N4** | 收窄 `Website.InvertColors` 的可见性 | 试了两次，红了两次 |
| **N6** | 切换网站时做交叉淡入 | 两个页面得同时在窗口里，也就是「`contentView` 里装的是什么」有了第二个答案——正是之前造成空白壁纸的那种歧义。只有在直接切换读起来太生硬时才重新考虑 |


### 私有 API：核实过没有公开替代，保留

| 位置 | 为什么保留 |
|---|---|
| `WKWebView.drawsBackground` KVC | 让壁纸透明的就是它。**`underPageBackgroundColor` 不是替代品**——它画的是 over-scroll 区域，不是视图的背板，别凭名字就换过去。#45 的护栏按名字单独允许了这一个键，删除这条允许的条件写在旁边 |
| 24 个 `WKMenuItemIdentifier*` 字符串 | 符号在 `WebKit.tbd` 里，但没有公开头文件声明它们，而 `WKUIDelegate` 在 macOS 上没有受支持的方式识别右键菜单项。没有链接任何私有符号，所以没有审查风险；改名只会让过滤变成 no-op |
| `com.apple.screenIsLocked` / `Unlocked` | 沙盒 app 拿不到公开的锁屏通知。`NSWorkspace.screensDidSleepNotification` 是**另一个事件**，不是它的安静版本。改名会让挂起失效，但不会崩溃 |
| `com.apple.DownloadFileFinished` | Dock 弹跳。装饰 |
| `EnvironmentValues().openWindow` / `openSettings` | macOS 15 上没有受支持的办法从 AppKit 打开 SwiftUI 的 `Window` scene。**但这是无声失败**：SwiftUI 一更新，面板上的「设置」和「网站」按钮就什么都不做，且不报错。从一个长期存活的视图里捕获 `@Environment(\.openWindow)` 会比它活得久 |

### 看着像手搓，其实是对的答案

- **`NSWindow.Level.desktop` / `.desktopIcon`** —— 由 `CGWindowLevelForKey` 构造，那是**公开的** CoreGraphics。不是私有窗口层。
- **`UpdateCheck.isNewer`** —— `String.compare(options: .numeric)` 会认为 `0.2` 比 `0.2.0` 旧。手写的那版判它们相等，那是对的。
- **`ScrollRestoration` 不用 `WKWebView.interactionState`** —— 那个 API 会**驱动一次导航**，所以一个陈旧的 blob 会留下一块空白壁纸且无路可退。滚动位置恢复失败是安全的。
- **`ScrollableTextView`** —— SwiftUI 在 macOS 上**不暴露智能引号和短横线替换的开关**，而用户 CSS 或 JavaScript 里出现一个智能引号会直接把他们的代码弄坏。这个包装存在的全部理由就是这个。
- **用 `NSStatusItem` + `NSPopover` 而不是 `MenuBarExtra`** —— `MenuBarExtra` 一个都不暴露 `isVisible`、`appearsDisabled`、`behavior`、`contentTintColor`，也没有可以跑加载脉冲的 layer。丢五个能力换零个。
- **`DisplayPanelModel.startLiveRefresh` 的 80ms 轮询** —— 它是一个正在动的页面的实时预览，没有可以订阅的通知，popover 关闭时会取消。那里真正错的是每帧解码两遍列表，已由 #57 修掉。

### 看着像死的，其实不是

`NSItemProvider: @unchecked Sendable`（**删掉编译失败**，data-race 错误；只有 conformance 的扩展没有成员供索引器看见引用）· `Intents.swift` 里全部 `AppIntent` 和 `WebsiteAppEntity` 的 `@Property`（从 bundle 元数据发现——periphery 15 条原始发现里的 14 条）· `Shortcut.allNames`（三个活调用点加一条测试；它的文档注释过时了，代码没有）· `NSStatusBarButton.setShowingActivity`（一条测试断言它）· 下载 entitlement · `SecurityScopedBookmarks.swift` · `Display.serialize`/`deserialize`（`Defaults.Bridge` 的协议要求，由包调用）· `Constants.playlistInterval`（有意的、有日期的迁移垫片）· `ActionTrampoline`、`CallbackMenuItem`、`addCallbackItem`（`SSWebView` 用它们建右键菜单）。

### 两个否定结果

- **站点目录能表达的比「添加网站」界面更少，不是更多。** `SiteCatalog.Entry` 解码七个字段，`Entry.add()` 只应用五个，而这五个全都有对应控件；目录条目碰不到 `allowsInteraction`、`display` 或 `startHour`/`endHour`。这条路上没藏东西。
- **九个快捷键全部带默认键位**，并且在设置里都有录制行。专门找过有没有不带绑定就发布的，答案是零。


---

## 14. 已决定、已完成

每条一行，只保留那种「删了就会被重新问一遍」的。

- **L0** 区域选择已是直接操作。见第 3 节那两个坑。
- **K2** 区域漂移——随 L0 消失；已经没有转换，也就没有差一个点的地方。
- **K3** 正在路上的页面在两个界面上都会说话：面板的选择器会脉冲、那一列变灰，菜单栏图标则对任意显示器脉冲。它是从 `WallpaperScene.isLoading` 读出来的而不是数出来的，所以本次会话的首次加载、挂起之后那次、以及某台显示器被重新打开之后那次，报告方式和其它每一次一样——而旧条目说只有 swap 路径才报告。
- **K5** 语言选择器已发布：写 `AppleLanguages` 加重启提示。被 E22 取代，E22 改的是机制而不是功能。
- **K9** 带 `zoom` 的目录条目不再拖垮整个 gallery：两种拼写都能解码，拉取时跳过坏条目而不是丢掉整个列表。跳过那一半没有测试——它是 `private` 的。
- **K10** Browsing Mode 由 `isEnabled.didSet` 重放。**K11** 页面缩放在两条到达路径上都恢复到真正接手页面的那个 web view 上。
- **K13 / K14 / D5** 显示器消失时它的壁纸也消失；插上的显示器能拿到页面，因为 `NSScreen.publisher` 现在调的是 `applyWebsiteChanges()` 而不是 `rebuildScenes()`。
- **K15** `.canJoinAllSpaces` 在 `DesktopWindow.init` 里设置。**尚未在真机核过：**开着 app 切换 Mission Control 桌面。
- **K19** 首次运行的策展写在条目自己的 YAML 里：`featured` 从标志变成了名次，floor796 是 1、Svalbard 是 2，第 N 台显示器拿第 N 个站点。它仍然会装上全部八个 featured 条目；那一半从来不是抱怨所在，而且那份列表正是新用户要去编辑的东西。
- **D3** `croppingSceneDisplay` 和它的 `?? primaryScene` 兜底都没了；裁剪持有的是 weak scene。
- **D9 / D10** 轮换按显示器走，scene 在 `init` 时就拿到自己的网站。两者都由 `swift test` 覆盖，这正是它们不再需要两台显示器的原因。
- **D11** `layOutContent` 从 `bounds` 推导。当初那个断言是只读一个文件推出来的，读了调用方就站不住。
- **E16** Universal binary：不做。每个架构一个精简构建，workflow 里写着理由。
- **E17** 按页面的 defaults 不会无界增长；是量出来的，不是推出来的。
- **E18** 清扫已经不可能被遗忘——见第 10 节那个坑。
- **E19** 本次会话的第一个页面由 `setUpEvents` 里一句显式的 `reloadEverything()` 加载，排在内容规则订阅**前面**而不是后面。原先站在这里的那条断言说旧顺序是刻意的、订阅上那条注释是唯一的护栏——两句都是假的：设了规则列表时，启动加载要等一次 `URLSession` 拉取加一次规则编译，而 `isEnabled.didSet` 里的一次重复加载正好把这件事遮住了。
- **E20** `nifro://reload`、`nifro:reload` 和 `nifro:///reload` 三种写法都接受；解析是纯函数，三种拼写都钉住了。
- **U1** 检查本身已发布，每日一次且可关闭。它的展示面没有——K25。
- **R5** `Extensions.swift` 已拆分，四个不是 extension 的类型搬了出去。里面没有任何死代码，`periphery` 推翻了那个只靠读代码得出的相反结论。
- **N5** `RenderingMode` 没了：两个 case 是由一个 `Bool` 算出来的。
