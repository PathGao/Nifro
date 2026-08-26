<p align="center">
  <img src="assets/icon-256.png" alt="Nifro" width="180">
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
  <a href="docs/ROADMAP.md">路线图</a>
  ·
  <a href="CONTRIBUTING.md">参与贡献</a>
  ·
  <a href="README.md">English</a>
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

Nifro 是 Sindre Sorhus 的 [Plash](https://github.com/sindresorhus/Plash) 的开源分支，取自它在
2025 年 10 月闭源之前最后一个 MIT 许可的快照。Plash 本身仍在开发、仍在 App Store 上；想要原版
请[去那里拿](https://sindresorhus.com/plash)。Nifro 不是它，也不自称是它，没有使用它的任何品牌
或美术资源。

做这个分支有两个原因。一是那个项目五年的 issue 列表里堆着很多合理的请求，而它们需要的改动是原
项目不打算接的。二是把代码读完之后会发现，它建立在两个值得重新考虑的前提上：

- 为了显示一分钟才变一次的内容，它让浏览器一直在渲染。
- 它其实不是壁纸，而是压在壁纸上方的一个透明窗口。

这个分支要做的就是拆掉这两条，而第一条比看上去难：两套渲染后端、遮挡测量、静止画面自动识别
都做过，结果每一样都在替「此刻到底在渲染什么」下判断，而浏览模式也在下同一个判断。它们又被拿了
出来，一共 811 行，之后一次放回一件，每件都要先有测量。这笔账和「什么条件成立了才放回去」写在
[docs/ROADMAP.md](docs/ROADMAP.md) 第 4 节；上游每一条未关闭 issue 的分诊见
[docs/UPSTREAM-ISSUES.md](docs/UPSTREAM-ISSUES.md)。

## 它比 Plash 多做了什么

**用移动的方式框出网页的一部分。** 拖动或双指滚动壁纸，捏合缩放，最后留在屏幕上的就是那一块。
你瞄的是结果而不是被框的东西，而且它从这个网站已有的区域开始，所以既能新建也能调整。页面仍然按
整屏排版，所以站点不会重排成你没框过的样子；那一块是重新渲染的而不是拉大的，字仍然清楚。

**换一块屏幕，框好的区域依然成立。** 它存的是位置和放大倍数而不是一个矩形，所以形状不同的屏幕会
各自算出自己的矩形，围着页面的同一处。

**一块屏一个页面。** 把网站指派给某块屏幕，每块屏各显示各的。

**带时段的轮播。** 让一块屏在几个网站之间轮换，也可以让某个网站声明自己什么时间段才允许出现。
排班永远不会把一块屏清空。

**按住某个键就能操作页面。** 按住时可以点击、滚动、缩放，松开就变回壁纸。

**声音按网站分别记住。** 时钟永远不该出声，而直播没有声音就没意义。

**一份经过挑选的站点清单。** 适合当壁纸的网页，每条都带着让它好用的那些设置。App 内的图库直接
读这个分支，所以合并进来的条目不用等发版。推荐一个站点只需要填一张表，加上 app 里的「复制设置」。

**全应用中英双语。**

## 从源码构建

```sh
git clone https://github.com/PathGao/Nifro
cd Nifro
open Nifro.xcodeproj
```

需要 Xcode 26 或更高版本。Swift 6 语言模式，部署目标 macOS 15。

`./Tools/build-local.sh` 会构建并安装一份测试包，签名方式和发布版一致。请用它，不要自己手动
签名：Xcode 已经签过之后再签一次会覆盖掉原签名，连沙盒 entitlement 一起丢掉，而一个没有沙盒的
Nifro 读的偏好文件和真实安装的不是同一份。

这些纯逻辑有测试，不需要 app 包，也不需要窗口服务器：裁剪与缩放的几何、菜单栏那一条的高度以及
色带从中取哪一块、排班时段、哪块屏幕上哪个网站是当前的、视频嵌入、URL 命令，以及菜单里的折行。

```sh
swift test
```

## 参与贡献

先看 [CONTRIBUTING.md](CONTRIBUTING.md)。最省力又最有用的贡献是加一条站点。如果你有一个当壁纸
很好看的页面，那对这个项目的价值超过大部分代码。

提交信息、PR 和 issue 请用英文——不是因为英文更好，而是因为它是所有读这个仓库的人唯一共有的
语言。commit 信息是别人 `git blame` 到某一行时读到的东西，理由都写在那里；读不懂它的人就只剩
一个 diff。

## 许可

MIT，见 [license](license)。衍生自 [sindresorhus/Plash](https://github.com/sindresorhus/Plash)
v2.16.0，版权归 Sindre Sorhus，以同一许可使用。应用图标及其他美术资源不衍生自 Plash。
