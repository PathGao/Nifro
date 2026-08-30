<p align="center">
  <img src="assets/nifro-icon-256.png" alt="Nifro" width="180">
</p>

<h1 align="center">Nifro</h1>

<p align="center">
  <b>把任意网页变成你的 Mac 桌面壁纸。</b><br>
  一个时钟、你的日历、一块仪表盘、一张实时地图、一段着色器、一个自然摄像头。<br>
  浏览器能画出来的东西，都可以画在你的窗口后面。
</p>

<p align="center">
  <a href="https://github.com/PathGao/Nifro/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/PathGao/Nifro?label=release&color=0453ab"></a>
  <a href="https://github.com/PathGao/Nifro/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/PathGao/Nifro/actions/workflows/ci.yml/badge.svg?branch=main&amp;event=push"></a>
  <a href="license"><img alt="许可" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <a href="#安装"><img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple"></a>
</p>

<p align="center">
  <a href="https://github.com/PathGao/Nifro/releases/latest/download/Nifro-arm64.dmg"><img alt="下载 Apple silicon 版" src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-Apple%20silicon-0453ab?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/PathGao/Nifro/releases/latest/download/Nifro-x86_64.dmg"><img alt="下载 Intel 版" src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-Intel-4a4a4a?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://github.com/PathGao/Nifro/releases">历史版本</a>
  ·
  <a href="sites/">投稿站点</a>
  ·
  <a href="sites/CANDIDATES.zh-Hans.md">候选站点</a>
  ·
  <a href="docs/ROADMAP.zh-Hans.md">路线图</a>
  ·
  <a href="CONTRIBUTING.md">参与贡献</a>
  ·
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="assets/wallpaper-video.jpg" alt="一部影片正作为桌面壁纸播放，显示器面板开着" width="900">
</p>

---

## 安装

```sh
brew tap PathGao/tap https://github.com/PathGao/Nifro
brew trust --cask PathGao/tap/nifro
brew install --cask nifro
```

> [!NOTE]
> Homebrew 不会加载它自己仓库之外的 cask，除非你明说信任 —— 因为 cask 可以在安装后执行代码。这
> 一个执行的是一条命令：清掉 macOS 给下载文件打的「来自互联网」标记，正是它让 app 能直接打开而
> 不被拦。信任之前可以先把 [Casks/nifro.rb](Casks/nifro.rb) 整个读一遍。
>
> 想要不加 tap、不用信任、直接 `brew install --cask nifro`，得先进 Homebrew 官方的 cask 仓库，那
> 有一道本项目还没够到的热度门槛。

### 或者下载磁盘映像

| 芯片 | 下载 | |
|---|---|---|
| **Apple silicon** | [`Nifro-arm64.dmg`](https://github.com/PathGao/Nifro/releases/latest/download/Nifro-arm64.dmg) | M1 及以后 |
| **Intel** | [`Nifro-x86_64.dmg`](https://github.com/PathGao/Nifro/releases/latest/download/Nifro-x86_64.dmg) | |

不做通用二进制，免得每个人都下载一份自己永远用不到的另一半。两个链接永远指向最新版。

> [!IMPORTANT]
> **第一次打开一定会被拒绝。** 构建包用的是本项目自己的证书而不是 Apple Developer ID，所以没有
> 经过公证，macOS 对下载来的副本只会回一句*「Apple 无法验证「Nifro」是否包含可能危害 Mac 安全或
> 泄漏隐私的恶意软件」*，而那个弹窗只给**移到废纸篓**和**取消**两个按钮。**两个都不是出路**，出
> 路是：
>
> 1. 按**取消**。不是移到废纸篓。
> 2. 打开**系统设置 → 隐私与安全性**，滚到最下面。
> 3. 在写着 Nifro 的那一行按**仍要打开**，用密码或触控 ID 确认。
> 4. 在最后一个弹窗按**打开**。
>
> 一次就够，macOS 会记住。过去那个「按住 Control 点一下 → 打开」的捷径已经没用了：macOS 15 里
> Apple 把这条路去掉了。用 brew 装则完全遇不到这一步 —— 这正是推荐 brew 的原因。详见
> [docs/RELEASE.md](docs/RELEASE.md)。

要求 macOS 15 或更新版本。

### 卸载

```sh
brew uninstall --zap --cask nifro
```

把 app 拖进废纸篓会留下它的容器目录。这是 macOS 的行为，不是 Nifro 的：容器比拥有它的 app 活得
久，而 app 在卸载时根本没有机会执行任何代码。`--zap` 就是负责删掉它的那个参数。没加这个参数、或
者当初是从磁盘映像装的，就手动删这几个目录：

```
~/Library/Containers/com.pathgao.nifro
~/Library/Containers/com.pathgao.nifro.ShareExtension
~/Library/Application Scripts/com.pathgao.nifro
~/Library/Application Scripts/com.pathgao.nifro.ShareExtension
```

里面装的大多是 WebKit 的东西而不是你的东西，Nifro 运行期间会把它压在 100 MB 以内，见
[`DiskBudget`](Nifro/Support/DiskBudget.swift)。**设置 → 高级 → 清除所有网站数据**可以随时清空。

## 这个项目从哪来

灵感来自 Sindre Sorhus 的 [Plash](https://github.com/sindresorhus/Plash)。

Nifro 保留了「把网页当作桌面壁纸」这个想法，但围绕这个想法的 App 基本被重新做了一遍。

它把界面设计成一眼能看懂网站、播放列表和显示器之间关系的样子。每块屏幕都有自己的壁纸、控制和
状态；网页可以裁切到你真正想放在桌面上的那一块；网站不再只是平铺列表，而是按播放列表来管理。

性能和日常使用体验也在这次重构范围内。保留下来的是这个 Idea，重构的是实现它的整个 App。

## 它做了什么

**把网页放到桌面上。** 实时摄像头、艺术网站、地图、仪表盘，或任何放在背景里比占着浏览器标签更合适
的网页。

**每块屏幕各放各的。** 多显示器时，每块屏都能显示不同内容。菜单栏面板会把各块屏并排展示，只显示
这块屏当前的网页和它自己的控制项。

**只显示网页中有用的部分。** 拖动、滚动或缩放，框出想留在桌面上的区域。Nifro 会记住它，换到尺寸
不同的显示器时也尽量保持在网页的同一个位置。

**用播放列表整理网站。** 可以按工作、风景或任意用途建播放列表，让一块屏固定显示一个网站、按顺序或
随机轮换，也可以遵守每个网站自己的时间安排。

<p align="center">
  <img src="assets/panel-two-displays.jpg" alt="显示器面板，每块屏一列" width="900">
</p>

**需要时再操作网页。** 按住快捷键即可点击、滚动和缩放，松开就回到壁纸。声音和链接打开方式都按网站
分别记住。

**从图库开始，或自己添加。** 内置图库收录了适合放到桌面的网页，也可以加入任意网站。Nifro 提供中英文
界面。

## 适合拿来做什么

Nifro 最适合那些可以一直留在屏幕上、偶尔瞥一眼又确实有内容的网页。

- **生成艺术和环境动画。** [Floor796](https://floor796.com/) 这类艺术网站，让原本静止的桌面持续有
  变化，又不会抢走注意力。
- **音乐和长视频。** YouTube 的 lofi 直播、环境音乐或 HDR 风景视频，可以放在工作窗口后面；声音是否
  播放仍按网站单独控制。
- **实时风景。** 窗景、自然摄像头，以及 [WindowSwap](https://www.window-swap.com/) 这类网站，很适合
  作为安静、持续变化的桌面背景。
- **工作和世界动态仪表盘。** OpenAI、Claude 的用量页面，以及 [World Monitor](https://www.worldmonitor.app/)
  这类实时仪表盘，把需要反复查看的信息放在一眼能看到的地方。
- **实时地图。** [Windy](https://www.windy.com/) 和 [Flightradar24](https://www.flightradar24.com/) 适合在
  需要持续关注天气或航班动态时常驻桌面。

## 从源码构建

### 环境要求

- macOS 15 或更新版本
- Xcode 26 或更高版本

### 在 Xcode 中运行

```sh
git clone https://github.com/PathGao/Nifro.git
cd Nifro
open Nifro.xcodeproj
```

在 Xcode 中选择 `Nifro` scheme 和**我的 Mac**，然后按 **Run**（⌘R）。

### 构建本地测试包

```sh
./Tools/build-local.sh
```

脚本会在需要时创建本地签名身份，带着 App 的沙盒 entitlement 构建，并把 `Nifro-test.app` 安装到桌面。
请用它，不要手动对 Xcode 构建产物重新签名：重新签名可能会删掉 entitlement，让它使用与正式版不同的
偏好设置容器。

### 运行测试

```sh
swift test
```

测试既覆盖 App 行为，也覆盖项目护栏：每显示器的状态、播放列表迁移、裁切和缩放、URL 处理、设置兼容性，
以及类型系统本身守不住的源码级规则。

## 参与贡献

先看 [CONTRIBUTING.md](CONTRIBUTING.md)。最省力又最有用的贡献是加一条站点。如果你有一个当壁纸
很好看的页面，那对这个项目的价值超过大部分代码。

提交信息、PR 和 issue 请用英文——不是因为英文更好，而是因为它是所有读这个仓库的人唯一共有的
语言。commit 信息是别人 `git blame` 到某一行时读到的东西，理由都写在那里；读不懂它的人就只剩
一个 diff。

## 许可

MIT，见 [license](license)。应用图标及其他美术资源均为本项目原创。
