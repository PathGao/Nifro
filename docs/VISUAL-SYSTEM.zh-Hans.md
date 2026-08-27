# 这个 app 的视觉词汇

[English](VISUAL-SYSTEM.md)

> 2026-08-27 对着 `dead3a6`（v0.1.3）写。下面每个数字旁边都附了产生它的命令，可以重跑，不必相信。

面板和设置窗口看起来不像同一个 app，而且没有任何机制要求它们像。这份文档说清楚它们实际差多远、哪些差异
是决定、哪些是意外，并提出**最小**的那个东西——让「有人硬编码了一个颜色」直接让 CI 变红，而不是等一双
眼睛发现。

这里没有任何东西已经实现。第 5、6 节是方案，第 7 节列出动手前需要你拍板的事。

---

## 1. 硬编码视觉字面量有多少

```sh
# 按文件、按类别。在仓库根目录跑。
for f in $(git ls-files 'Nifro/*.swift' | grep -v generated); do
  r=$(grep -cE "(cornerRadius|xRadius|yRadius): *[0-9]" $f)
  o=$(grep -cE "\.(system|systemFont|monospacedSystemFont|monospacedDigitSystemFont)\((of)?[Ss]ize: *[1-9]" $f)
  s=$(grep -cE "spacing: *[1-9]" $f)
  p=$(grep -cE "\.padding\((\.[a-zA-Z]+, *)?[1-9]" $f)
  w=$(grep -cE "\.frame\(.*(width|height): *[1-9]" $f)
  c=$(grep -cE "Color\(red:|(NS)?Color\.(white|black)|withAlphaComponent\(|\.opacity\(0?\.[0-9]" $f)
  [ $((r+o+s+p+w+c)) -gt 0 ] && printf "%-42s %2s %2s %2s %2s %2s %2s = %s\n" $f $r $o $s $p $w $c $((r+o+s+p+w+c))
done
```

| 文件 | 圆角 | 字号 | spacing | padding | frame | 颜色 | 合计 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `Screens/DisplayPanel.swift` | 9 | 1 | 8 | 7 | 5 | 1 | **31** |
| `Screens/SiteGalleryScreen.swift` | 0 | 0 | 5 | 4 | 2 | 0 | 11 |
| `Screens/PanelControls.swift` | 2 | 3 | 1 | 0 | 1 | 1 | 8 |
| `Screens/WebsitesScreen.swift` | 1 | 0 | 2 | 1 | 3 | 1 | 8 |
| `Zoom/CropSelectionView.swift` | 1 | 2 | 0 | 0 | 0 | 5 | 8 |
| `Screens/AddWebsiteScreen.swift` | 0 | 2 | 1 | 0 | 4 | 0 | 7 |
| `Screens/AboutSettings.swift` | 0 | 0 | 2 | 1 | 1 | 0 | 4 |
| `Screens/SettingsScreen.swift` | 0 | 0 | 2 | 0 | 1 | 0 | 3 |
| `Screens/SettingHelp.swift` | 0 | 0 | 1 | 0 | 1 | 0 | 2 |
| `Screens/IntervalField.swift` | 0 | 0 | 0 | 0 | 2 | 0 | 2 |
| `Support/ScrollableTextView.swift` | 0 | 0 | 0 | 0 | 1 | 0 | 1 |
| `Visibility/MenuBarBand.swift` | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| | | | | | | | **85** |

两行承担了大部分论据。`DisplayPanel.swift` 占 85 里的 31——全 app 三分之一以上的视觉字面量，都在那个
同时也放着唯一一套具名度量的文件里。而 `MenuBarBand.swift` 是 0：它的颜色从页面上取，设计系统没有任何
东西能给它。它的豁免建立在最强的理由上，不是妥协。

**哪些值是重复的。** 让字面量变成缺陷的是重数；只用一次的数字就只是个数字。

```sh
grep -rhoE --include='*.swift' "(cornerRadius|xRadius|yRadius): *[0-9]+" Nifro/Screens Nifro/Zoom |
  grep -oE "[0-9]+$" | sort -n | uniq -c
```

- **圆角：5（×4）、7（×1）、8（×4）、12（×5）** —— 外加 `PanelMetrics.cornerRadius = 6`，第五个圆角，
  只有一个使用者。一个 popover 里五种圆角。
- **字号：11（×4）、12、13（×2）、22** —— 而 `PanelMetrics` 已经把 11 和 13 都命名了。
- **宽度：260（×3）、44（×3）、560（×3）、500/56/70/22/16（各 ×2）。** 260 是面板列宽，没有任何地方
  给它名字。

---

## 2. 按「缺陷的三个形状」分类

对照 `WORKSPACE_GUIDE.md` 的「缺陷的三个形状」。

### ① 同一个表达式被抄了 N 份

- **`Font.system(size: 11, weight: .semibold)`** 既是 `PanelMetrics.symbolFont`
  （`PanelControls.swift:25`），又在 `DisplayPanel.swift:256` 一个字符不差地写了一遍。其中一份是抄的。
- **字号 13** 既是 `PanelMetrics.font`（`PanelControls.swift:21`），又是 `PanelControls.swift:57` 的
  `.system(size: 13, weight: .medium)` —— 同一个文件里同一个字号声明了两次，只差一个字重。
- **列宽 260**，在 `DisplayPanel.swift:122`、`:139`、`:299`。更糟的是
  `PanelMetrics.chooserWidth = 195`（`PanelControls.swift:32`）的注释写着「上面那张图的四分之三」——
  也就是 `0.75 × 260`，一条推导被记成了散文而不是代码。改了列宽，那句注释就静默变成谎话。
- **开启态前景 `AnyShapeStyle(.white)`**，在 `PanelControls.swift:82`、`:131` 和
  `DisplayPanel.swift:258`。`onTint` 有名字，压在它上面的那个颜色没有。
- **圆角 12 ×3**（`DisplayPanel.swift:142,149,152`）和 **圆角 8 ×4**（`:285,292,300,302`）——两处都是
  同一个元素的填充、裁剪和描边，它们必须一致，否则边框会错过拐角。

### ② 建了一套机制，有成员没加入

- **`PanelMetrics` 有六个成员，`PanelMetrics.` 出现 16 次**，两个面板文件各 8 次：

  ```sh
  grep -rc "PanelMetrics\." Nifro/Screens/*.swift   # DisplayPanel 8, PanelControls 8
  ```

  而这两个文件里有 39 个视觉字面量。这套机制覆盖了它存在理由的大约五分之一。
- **同步链接按钮（`DisplayPanel.swift:254-267`）把 `PanelButton` 手抄了一遍。** 它自己写字体（第 256
  行，就是上面那份抄件）、自己写 `22×20` 的 frame——而 `PanelButton` 是 `26×22`
  （`PanelControls.swift:58`）、自己写 `cornerRadius: 5`、自己写 on-tint 分支——**而且完全不读 hover
  状态**，尽管它左右两边的邻居都会在 hover 时下沉和点亮。它没做成 `PanelButton` 是因为 `PanelButton`
  包的是 `Button` 而这里需要 `Menu`；除此之外它没有任何一处是想要不一样的。
- **`PanelMetrics.cornerRadius = 6` 只有一个使用者**，`PanelWideButton`。而 `PanelButton`——就在同一行
  页脚里、隔 10 点（`DisplayPanel.swift:60`）——用的是 5。token 已经在那儿了，兄弟控件没加入。

### ③ 两处独立回答同一个问题，答案不同

- **开启态颜色自己那条规则，没有被一致地应用。** `PanelMetrics.onTint` 的注释
  （`PanelControls.swift:37-40`）给出了一条真实判据：系统 accent 说「这个被选中」，图标的橙色说
  「这个在运行」。逐个调用点核过，有一个不符。`DisplayPanel.swift:319-321` 传的是
  `isOn: !column.isShowing`，所以电源按钮是在**那块屏幕的壁纸被关掉时**亮橙色。按写下来的规则这是反的；
  按另一条规则（「这个按钮被按下了」）它是对的。两种读法都站得住，而只有一种被写下来——这才是缺陷。
  另外四个调用点和注释一致。
- **一个 hover 状态，两套颜色体系，其中一套只在深色下有效。** hover 一列会画一条
  `Color.accentColor` 的边框（`DisplayPanel.swift:150`）和一块 `Color.white.opacity(0.15)` 的填充
  （`:143`）。边框跟随主题和用户的 accent；填充是固定的白色，压在浅色外观的 popover 上几乎看不见——
  而同一列内部的按钮做同一件事用的是 `.quaternary`。「hover 长什么样」有三个答案，其中一个依赖外观。
- **五个窗口，五个宽度，各自独立决定的。** 400（`SettingsScreen.swift:19`）、480
  （`WebsitesScreen.swift:71`）、500（`AddWebsiteScreen.swift:60`）、520×560
  （`AddWebsiteScreen.swift:494`）、560×560（`SiteGalleryScreen.swift:47`）。没有任何东西要求其中任意
  两个一致。它们**可以**合理地不同——见第 4 节——但从来没有人决定过它们是不同的。
- **关于这条边界本身的一条过期注释。** `DisplayPanelController.swift:8` 写着「旧菜单右键还在，会一直留到
  面板承担它的全部为止」。`AppState.swift:30` 写着「菜单已经没了」。`Menus.swift` 在 #21 里删掉了，
  `sendAction(on: [.leftMouseUp, .rightMouseUp])`（`AppState.swift:24`）把左右键都送进同一个处理函数。
  前一条注释描述的是一个不再存在的 app，而它恰好是读者问「哪个界面管什么」时最先读到的那条。
  （它背后那堆死掉的 `SSMenu` 脚手架已经是 ROADMAP W9；这一条说的是注释，不是代码。）

---

## 3. 哪些**不是**问题

记下来，免得下一轮重新提。

- **`MenuBarBand`** 没有任何视觉字面量，也永远不该有。它唯一的颜色是从壁纸上采的。
- **四个 `Form(.formStyle(.grouped))` 屏幕**用系统控件是对的。它们是关于普通设置的普通窗口；系统控件是
  唯一能免费跟随用户 accent 颜色、增强对比度、降低透明度和 VoiceOver 的东西。
- **`CropSelectionView` 的黑与白**不是从系统里逃出来的品牌色。它们是针对**任意一个网页**的对比度决策，
  而这恰恰是全 app 里唯一一处「跟随主题的颜色」是错误答案的界面。
- **动画时长** —— 0.12（×2）、0.2，以及 0.2/0.82 的 spring。ROADMAP N3 已经裁定过：两个因不同原因而变的
  时长不该合并；同一条判据在这里适用，按压下沉和跑马灯回位没通过它。不做 token。
- **同一个视图内重复的 `spacing:` 和 `padding:`。** `DisplayColumn` 里两次 `VStack(spacing: 9)` 是同一个
  布局写了两遍，不是共享词汇。第 5 节刻意不管这些，第 6 节说了要管的代价。

---

## 4. 系统控件与自制控件的界线该划在哪

今天这条线三处是对的，一处根本没划。

| 界面 | 应该是 | 理由 |
|---|---|---|
| Settings、Websites、Add Website、Site Gallery | **系统** | 关于普通设置的普通窗口。只有系统控件不需要被要求就跟随 accent 颜色、增强对比度、降低透明度和 VoiceOver |
| 显示面板 | **自制** | `PanelControls.swift:6-9` 已经论证过：控件作用在用户看不见的页面上，所以按钮必须是反馈的全部 |
| `CropSelectionView` | **自制** | 它压在一个任意网页上。没有任何系统绘制的东西能在未知内容上保持可读 |
| `MenuBarBand` | **两者都不是** | 它不是控件。颜色来自页面 |

**哪里是碰巧长成这样而不是被划出来的：面板内部。** 面板的三个控件是**系统 `Menu` 套着手绘标签**——
网站选择器（`DisplayPanel.swift:344-380`）、同步链接（`:239-267`）——所以弹出列表是系统绘制的、装在一个
手绘面板里，而 token 层永远只够到标签。这是个合理的停止位置，但没有任何地方这么说，也就意味着下一个加进来
的控件没有规则可循。

**已经存在的那条判据值得保留。** `onTint` 的注释——accent 表示被选中、橙色表示在运行——是一条真实的语义
区分，不是装饰，而且它正是下面那套 token 做成**语义的**（`onTint`、`hoverFill`）而不是一堆颜色名的原因。
它只是需要被「记得它的那个人」以外的东西来强制执行。第 7 节 Q1 请你裁决那个唯一不符的调用点。

---

## 5. 方案

刻意做小。`PanelMetrics` 本身**已经**是那层设计 token；问题不是它不存在，而是它以一个屏幕命名、和它服务的
视图放在一起、只覆盖了其中五分之一。所以这是一次重命名、几个新增（每个都有至少两个既有使用者），加一个共享
modifier——不是一套新框架。

### 5.1 一个文件：`Nifro/Screens/Appearance.swift`

`PanelMetrics` 搬过来，改名 `Appearance`，保留它的文档。它要有自己的文件，是为了让 5.3 的 lint 规则能豁免
一条稳定路径；留在 `PanelControls.swift` 里会连带豁免 `PanelButton` 和 `PanelWideButton`——而那正是这件事
要堵的洞。

```swift
enum Appearance {
	// 控件外观。和 PanelMetrics 一样，没有改动。
	static let controlFont = Font.system(size: 13)
	static let symbolFont = Font.system(size: 11, weight: .semibold)
	static let controlHeight = 28.0
	static let controlPadding = 15.0
	static let controlRadius = 6.0            // ← 第 7 节 Q2：图标按钮的 5 是有意不同吗？
	static let iconButtonSize = CGSize(width: 26, height: 22)

	// 列。
	static let columnWidth = 260.0
	static let cardRadius = 12.0
	static let pictureRadius = 8.0
	static let chooserWidth = columnWidth * 0.75   // 把既有那条注释变成由构造保证的事实。

	// 状态。按它的含义命名，而不是按它是什么颜色。
	static let onTint = Color(red: 234 / 255, green: 115 / 255, blue: 63 / 255)
	static let onForeground = AnyShapeStyle(.white)
	static let hoverFill = AnyShapeStyle(.quaternary)
	static let restFill = AnyShapeStyle(.quinary)
}
```

十四个名字。除了 `controlRadius`（只有一个使用者，就是 Q2 的议题），其余每一个今天都至少有两个调用点。
没有任何东西是为了对称加进去的：**没有 `windowWidth`**，因为第 3 节的 N3 判据说，五个为五种内容定尺寸的
窗口是五个决定，不是一个。

### 5.2 一个 modifier，三个调用点

```swift
extension View {
	/// 按面板画控件的方式画这个控件。
	func panelChrome(isOn: Bool, isHovering: Bool, rest: AnyShapeStyle = Appearance.restFill) -> some View
}
```

它负责前景（`onForeground` / `.primary`）、背景（`onTint` / `hoverFill` / `rest`）和圆角形状。
`PanelButton` 传 `rest: AnyShapeStyle(.clear)`；`PanelWideButton` 用默认值；**同步链接的 `Menu` 标签也用
它**——这就是把第二个图标按钮折回机制里的那一步。之后，图标按钮和药丸按钮之间唯一的差别就是 frame 和
padding，它们留在调用点，因为那才是真正的差别。

不做 protocol，不做样式注册表，不做 `ButtonStyle` 层级。只有一个面板。

### 5.3 护栏：三条 SwiftLint 自定义规则

SwiftLint 已经 pin 在 0.65.1，CI 里已经跑 `--strict`（`ci.yml:99`），所以不引入新工具、不新增 job。
加进 `.swiftlint.yml`：

```yaml
custom_rules:
  hardcoded_corner_radius:
    included: 'Nifro/(Screens|Zoom|Visibility)/.*\.swift'
    excluded: 'Nifro/(Screens/Appearance|Zoom/CropSelectionView)\.swift'
    regex: '(cornerRadius|xRadius|yRadius): *[0-9]'
    message: '圆角属于 Appearance。在那里给它一个名字，或者用 disable 注明这一次为什么不是共享的。'

  hardcoded_font_size:
    included: 'Nifro/(Screens|Zoom|Visibility)/.*\.swift'
    excluded: 'Nifro/(Screens/Appearance|Zoom/CropSelectionView)\.swift'
    regex: '\.(system|systemFont|monospacedSystemFont|monospacedDigitSystemFont)\((of)?[Ss]ize: *[1-9]'
    message: '字号属于 Appearance。'

  hardcoded_ui_colour:
    included: 'Nifro/(Screens|Zoom|Visibility)/.*\.swift'
    excluded: 'Nifro/(Screens/Appearance|Zoom/CropSelectionView)\.swift'
    regex: 'Color\(red:|(NS)?Color\.(white|black)\b|AnyShapeStyle\(\.white\)'
    message: '字面颜色既不跟随主题也不跟随用户 accent。用 Appearance，或者用语义样式。'
```

**为什么是这几条正则而不是别的。** 每一条匹配的都是**框架**符号——SwiftUI 和 AppKit 自己的公开参数标签和
初始化器。没有一条匹配这个仓库里任何人取的名字。把 `PanelButton`、`isHovering` 或者 `PanelMetrics` 本身
改名，都不可能让它们中的任何一条变红——这正是 `WORKSPACE_GUIDE.md` 划的「白红」与「真红」的界线。字号规则
里的 `[1-9]` 不是修饰：`NSFont.controlContentFont(ofSize: 0)`（`ScrollableTextView.swift:47`）是 AppKit
表示「系统默认字号」的惯用写法，是硬编码字号的反面，用 `[0-9]` 会把它误红。

**这些是量出来的，不是预测的。** 两半都在本机用与 CI pin 相同的 0.65.1 跑过：

```sh
swiftlint lint --quiet --config /path/to/probe.yml | grep -c 'warning:'
```

- 三条规则在 `dead3a6` 上触发 **32 次**。第 6 节逐条列出。
- 按规则的 `excluded:` 生效：把它指向 `PanelControls.swift`，计数 32 → 24，正好是那个文件的 8 条。
- `// swiftlint:disable:next hardcoded_corner_radius - <理由>` 能消掉一行；而
  `superfluous_disable_command`——`.swiftlint.yml` 里**已经**开着——会在下面那行不再违规时把这条 disable
  本身报成违规。也就是说，**理由过期的允许清单条目会失败**，这正是 `WORKSPACE_GUIDE.md` 要求允许清单具备
  的性质，也是这件事做成 lint 规则而不是源码形状测试的原因。

**为什么不写成 `Tests/` 里的源码形状测试。** `WORKSPACE_GUIDE.md` 的判据是命题**不可运行**还是代码只是
**不可达**。「`Appearance.swift` 之外不存在颜色字面量」是一条关于源码文本的缺席命题，所以形状测试本来是
对的工具——但 SwiftLint 已经读每一个文件、已经跑 `--strict`、已经有带过期检查的逐行豁免，而且能在 PR
diff 里指到出问题的那一列。测试要把这些全部重写一遍，而 `NifroLogic` 这个 package target 只编译七个文件，
得伸到自己外面去读其余的。用已经在那儿的工具。

### 5.4 哪些暂时不管，什么时候再管

`spacing:`、`.padding(…)` 和 `.frame(width:height:)` 不在覆盖范围内。把规则扩到它们上面会**多触发 45
次**（用同样的方法量的），而其中大部分是只写了一次的局部布局。一份 45 条、每条写着「这是个布局数字」的
允许清单，正是 `WORKSPACE_GUIDE.md` 禁止的形状。等到出现第二个面板、某个 spacing 必须跨两者一致时再加——
那时候这个数字才有名字可取，今天没有。

---

## 6. 迁移顺序，以及那 32 条

**没有「先只告警」这个阶段。** CI 已经跑 `swiftlint lint --strict`，所以一条默认严重度的自定义规则落地
当天就是红的。下面这个顺序的作用是在规则加进去之前把计数降到零，不是让它慢慢过渡。

| 步骤 | 做什么 | 验证判据 |
|---|---|---|
| 1 | `Appearance.swift`：搬 `PanelMetrics`、改名、加 5.1 里那八个名字 | `git grep -c PanelMetrics` → 0；app 能构建；`swift test` 不变（package target 不编译这些文件，所以这一步不可能弄坏它） |
| 2 | `panelChrome`，同步链接按钮采用它 | `DisplayPanel.swift` 的字面量数从 31 降到约 20。可见变化：同步按钮变成 26×22 并获得 hover 状态 |
| 3 | 第 7 节的 Q1 和 Q2 —— 是决定，不是改名 | 没有可量的东西。需要你 |
| 4 | 加那三条规则。剩三条违规，每条一行 `disable:next` 附理由 | `swiftlint lint --strict` 退出码 0。从此之后，写下一个硬编码字面量的那个 PR 当场变红 |

### 那 32 条，逐条给出处置

这就是 `WORKSPACE_GUIDE.md` 要求的清单：首次运行的每一条，都要有说法，没有一条不经审视被塞进允许清单。

**第 1 步解决 —— token 已存在或正在加（19 条）。**
`PanelControls.swift:21,25,41` 本身就变成 token 定义。`PanelControls.swift:57`（字号 13）和
`DisplayPanel.swift:256`（11 semibold）是已存在 token 的逐字抄件。`PanelControls.swift:60,61` 和
`DisplayPanel.swift:261` 是圆角 5 那一组，按 Q2 变成 `controlRadius`。`DisplayPanel.swift:142,149,152`
变成 `cardRadius`；`:285,292,300,302` 变成 `pictureRadius`。`DisplayPanel.swift:327`（圆角 7）变成
`pictureRadius - 1` —— 它是嵌在圆角 8 的图片里的一颗药丸，7 就是这个关系，被写成了一个数字。
`PanelControls.swift:82,131` 和 `DisplayPanel.swift:258` 变成 `onForeground`。

**第 3 步解决 —— 是决定，不是改名（1 条）。**
`DisplayPanel.swift:143`，`Color.white.opacity(0.15)`。这是 Q3：只在深色外观下有效的 hover 填充。它几乎
肯定应该变成 `hoverFill`，和同一列内部的按钮一致——但这会改变面板的样子，你来定。

**作为一个界面整体豁免，只写一条理由（9 条）。**
`CropSelectionView.swift` 全部 —— `:152,157,170,171,174,175,190,191(×2)`。它的黑色遮罩、白色描边和 22 点
读数都是针对任意网页的对比度决策，是全 app 里唯一一处「跟随主题的颜色」是**错误**答案的界面。九条一模一样
的逐行理由说明的东西还不如一条文件级的多，所以豁免写成 `excluded:` 里的一条路径，理由写在 YAML 里它上面。
如果你更想看到九行 `disable:next`，说一声——这是一个真实的选择，不是疏忽。

**永久允许，各一行（3 条）。**
- `AddWebsiteScreen.swift:460` 和 `:481`，`monospacedSystemFont(ofSize: 11)`。这两处是 CSS 和 JavaScript
  编辑器。代码编辑器的字体就是代码编辑器的字体，和外观没有关系；放进 `Appearance` 等于把一个编辑器耦合到
  一个面板上。
- `WebsitesScreen.swift:246`，网站图标上的 `cornerRadius: 5`。它是系统 `Form` 里一张 44×44 的遮罩图片，
  不是面板控件。它更应该用 macOS 自己的图标圆角而不是 `Appearance` 的——这也是它被「允许」而不是被「迁移」
  的原因。

---

## 7. 需要你拍板

- **Q1 —— 电源按钮的橙色。** `DisplayPanel.swift:319-321` 在那块屏幕被**关掉**时点亮 `onTint`，这和
  `onTint` 自己的注释（「图标的橙色说*这个在运行*」）矛盾。要么调用点取反，要么把注释改写成「这个按钮被
  按下了」。无论选哪个，另外四个调用点都要照着重读一遍。注意这件事**挨着**但不等于 ROADMAP K22 ——
  K22 说的是这个按钮**不对**，这里说的是它**颜色不对**。
- **Q2 —— 五种圆角，还是更少。** `PanelButton` 用 5，`PanelWideButton` 用 6，两者在页脚里隔 10 点。
  第 5 节假定它们合并成一个 `controlRadius`；选 5 还是选 6 是审美决定，我不该替你做。卡片的 12 和图片的
  8 无论如何都保持独立。
- **Q3 —— 列的 hover 填充。** 把 `Color.white.opacity(0.15)` 换成 `.quaternary` 会修好浅色外观，同时改变
  面板在深色下的样子。第 3 步之前确认。
- **Q4 —— `CropSelectionView` 是整个文件豁免还是逐行豁免。** 第 6 节论证的是整个文件。判断错的代价是：
  以后真正共享的值在那里被硬编码，不会被发现。
- **Q5 —— 窗口宽度。** 五个窗口五个宽度，从来没决定过。第 5 节按 ROADMAP N3 的理由**刻意不**把它们做成
  token。如果你认为 Settings 的 400 和 Websites 的 480 应该一致，那是一个独立的、更小的改动，不该搭这趟车。

## 8. 明确不做

- 一套 `ButtonStyle` 或 `ViewModifier` 库。只有一个面板；能证明这个抽象成立的是第二个实现，而它不存在
  （ROADMAP X4 的理由）。
- 把 `Form` 屏幕改成面板的样子。那等于交换掉第 4 节所说的、使用系统控件的全部理由：辅助功能和外观行为。
- 一个颜色资源目录。只有一个颜色是 app 特有的，其余都是语义系统样式，目录只会把它们盖住。
- 动 `MenuBarBand`、`DimWhenUnfocused` 或 `Wallpaper/` 下的任何东西。它们都不画外观。
