# 发布手册

Noren 不上 Mac App Store，分发走 **GitHub Release + Homebrew cask**。

涉及文件：

| 文件 | 作用 |
| --- | --- |
| `.github/workflows/release.yml` | 打 `v*` tag 触发，构建 → 签名 →（公证）→ 打包 → 建 Release → 回写 cask |
| `Casks/noren.rb` | cask 定义，`version` / `sha256` 由流水线自动更新 |
| `Config.xcconfig` | `MARKETING_VERSION`，必须和 tag 对得上，流水线会校验 |

---

## 一、两条路径

关键变量只有一个：**有没有付费 Apple Developer Program 账号（99 美元/年）**。没有账号就拿不到
Developer ID 证书，拿不到证书就不能公证，这条链是死的，绕不过去。

流水线通过「secrets 是否存在」自动选路，不需要改 YAML：

```
                      ┌─ 有 MACOS_CERTIFICATE_P12 ─→ 路径 A：Developer ID 签名
  push tag v* ─→ CI ──┤                                + notarytool 公证 + stapler staple
                      └─ 没有 ──────────────────────→ 路径 B：ad-hoc 签名（codesign -s -）
```

### 路径 A：有付费账号（推荐）

```
xcodebuild (CODE_SIGN_IDENTITY="Developer ID Application", hardened runtime)
   ↓
ditto -c -k --keepParent  →  notarize.zip
   ↓
xcrun notarytool submit --wait      （Apple 扫一遍，通常 1~10 分钟）
   ↓
xcrun stapler staple Noren.app      （把公证票据钉进 app，用户离线也能过）
   ↓
spctl -a -vvv --type exec           （门禁自检，不过就 fail，不发坏包）
   ↓
Noren-x.y.z.zip  →  GitHub Release  →  cask 回写 version/sha256
```

### 路径 B：没有付费账号

```
xcodebuild (CODE_SIGN_IDENTITY="-")   ← ad-hoc，无身份，但沙盒 entitlements 照样生效
   ↓
Noren-x.y.z.zip  →  GitHub Release  →  cask 回写 version/sha256
                                        cask 的 postflight 去掉 com.apple.quarantine
```

路径 B 下 `spctl` 检查会被跳过，流水线只打 warning，Release 说明里会自动标注「未公证」。

**免费 Apple ID 不算数**：免费账号只能签 `Apple Development` 证书，7 天过期、只在本机有效，
不能用于分发。所以「没有付费账号」的唯一可行方案就是 ad-hoc。

---

## 二、需要的 GitHub Secrets

路径 B 一个都不需要，直接打 tag 就能发。以下全部是路径 A 用的：

| Secret | 内容 | 从哪来 |
| --- | --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application 证书 + 私钥的 `.p12`，**base64 编码** | 见下方 A1/A2 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设的密码 | 自己设，自己记 |
| `APPLE_TEAM_ID` | 10 位 Team ID，如 `ABCDE12345` | developer.apple.com → Membership |
| `NOTARY_KEY_P8` | App Store Connect API 私钥 `AuthKey_XXXXXXXX.p8`，**base64 编码** | 见下方 A3 |
| `NOTARY_KEY_ID` | 该 key 的 Key ID（8 位） | 生成 key 时页面上显示 |
| `NOTARY_ISSUER_ID` | Issuer ID（UUID 格式） | App Store Connect → Integrations → Keys 页顶部 |

> 用 App Store Connect API key 而不是「Apple ID + app-specific password」：不受 2FA 影响、
> 可单独吊销、不绑个人账号密码。

base64 编码方式（macOS）：

```bash
base64 -i DeveloperID.p12       | pbcopy   # 贴进 MACOS_CERTIFICATE_P12
base64 -i AuthKey_XXXXXXXX.p8   | pbcopy   # 贴进 NOTARY_KEY_P8
```

设置位置：仓库 → Settings → Secrets and variables → Actions → New repository secret。

---

## 三、维护者本人必须手动做的事（agent 做不了）

这些都要 Apple 账号登录或本机钥匙串操作。

**路径 A 专属：**

- **A1** 在 Xcode → Settings → Accounts → Manage Certificates → `+` → **Developer ID Application**
  创建证书（或在 developer.apple.com → Certificates 里走 CSR 流程）。
- **A2** 打开「钥匙串访问」，找到该证书，**连带私钥一起**右键导出为 `.p12`，设一个密码。
  只导出证书不带私钥的话 CI 签不了名。
- **A3** appstoreconnect.apple.com → Users and Access → Integrations → Keys → 生成一个
  **Developer Access / App Manager** 权限的 API Key，下载 `.p8`（**只能下载一次**）。
- **A4** 把上表 6 个 secret 填进仓库。
- **A5** 第一次发布成功后，把 `Casks/noren.rb` 里的整个 `postflight` 块删掉（公证之后不需要
  再去隔离属性，留着反而是负面信号）。

**两条路径都要做：**

- **B1** 创建 tap 仓库 `PathGao/homebrew-tap`，或者直接让用户 tap 本仓库
  （`brew tap PathGao/tap https://github.com/PathGao/noren`，cask 就在本仓库 `Casks/` 下，
  不用维护第二个仓库 —— 这是更省事的做法）。
- **B2** 确认 `main` 分支保护规则允许 `github-actions[bot]` 推送，否则流水线最后一步
  「回写 cask」会失败（只是告警，Release 本身不受影响，可以手动改 cask）。
- **B3** 首次发布前，把 `.github/workflows/release.yml` 顶部的 `XCODE_SCHEME` / `BUILT_APP_NAME`
  和工程实际情况对齐。**当前工程的 scheme 和 target 还叫 `Plash`**，所以默认值就是 `Plash`
  / `Plash.app`；等 target 改名成 Noren 之后，把这两个值改掉即可，其余不用动。

---

## 四、发布一个版本

```bash
# 1. 改版本号（tag 和它必须一致，不一致流水线会直接失败）
vim Config.xcconfig            # MARKETING_VERSION = 0.2.0

# 2. 提交
git commit -am "0.2.0" && git push

# 3. 打 tag
git tag -a v0.2.0 -m "v0.2.0" && git push origin v0.2.0
```

剩下的流水线全包：构建、签名、公证、打包、建 Release、回写 `Casks/noren.rb`。

失败时先看 Actions 里的 `xcodebuild-log` artifact。

---

## 五、用户拿到的东西长什么样

### 路径 A（已公证）

| 安装方式 | 用户体验 |
| --- | --- |
| `brew install --cask PathGao/tap/noren` | 装完直接能开，无提示 |
| 下载 zip 双击 | 首次弹「Noren 是从互联网下载的，确定要打开吗？」→ 点「打开」→ 结束 |

### 路径 B（ad-hoc，未公证）

| 安装方式 | 用户体验 |
| --- | --- |
| `brew install --cask PathGao/tap/noren` | 装完直接能开，无提示（cask 的 `postflight` 已去掉隔离属性） |
| 下载 zip 双击 | **被拦**：「无法打开 Noren，因为 Apple 无法检查其是否包含恶意软件」，只有「移到废纸篓 / 取消」两个按钮 |

路径 B 下直接下载 zip 的用户需要额外一步。放进 README 安装章节的说明：

> 首次打开时 macOS 会提示「无法打开 Noren，因为 Apple 无法检查其是否包含恶意软件」。
> 这是因为 Noren 没有经过 Apple 公证（公证需要 99 美元/年的开发者账号）。
> 用 Homebrew 安装不会遇到这个提示。
>
> 手动放行，二选一：
>
> 1. 打开一次被拦的 app → 「系统设置 → 隐私与安全性」→ 拉到底 → 点「仍要打开」。
> 2. 或者在终端里执行：
>    ```bash
>    xattr -dr com.apple.quarantine /Applications/Noren.app
>    ```

**别让用户去关 SIP 或 `spctl --master-disable`**，那是降低整机安全等级，不是解决这个问题的办法。

---

## 六、这套方案和 AeroSpace 的关系

参照对象是 [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace)。它的实际做法：

- **签名**：`build-release.sh` 里 `codesign -s "aerospace-codesign-certificate"`，是维护者本机
  钥匙串里的一张**自签名证书**，不是 Developer ID。CI (`build.yml`) 上用
  `./build-release.sh --codesign-identity -`，注释直说「GH Actions 上没有那张证书」。
- **公证**：不做。README 里明确说不公证。
- **发布**：**没有 release workflow**。`.github/workflows/` 下只有 `build.yml` 和两个 issue 机器人。
  真正发版靠维护者本机跑 `script/publish-release.sh`：打 tag、`open` 浏览器、**手动把 zip 拖进
  GitHub Release 页面**、回车继续。
- **cask**：自己的 tap（`nikitabobko/homebrew-tap`），`Casks/aerospace.rb` 由
  `script/build-brew-cask.sh` 生成后 `cp` 过去。没有 livecheck，`version` 是写死的字面量。
  靠 `postflight` 里的 `xattr -d com.apple.quarantine` 让 brew 用户绕过 Gatekeeper。

Noren 的偏离：

| 项 | AeroSpace | Noren | 原因 |
| --- | --- | --- | --- |
| 发布触发 | 本机脚本 + 手动上传 | tag 触发 GitHub Actions | 本机发版要求维护者机器状态正确，且不可复现 |
| 签名 | 自签名证书（本机） | Developer ID（有账号）/ ad-hoc（没有） | 自签名证书对 Gatekeeper 和 ad-hoc 等价，白多一步；不如直接留出公证位 |
| 公证 | 不做 | 有账号就做 | Noren 是沙盒 GUI app，用户群不像 tiling WM 用户那样习惯敲 `xattr` |
| cask 版本 | 手动生成后 cp | CI `sed` 回写本仓库 `Casks/` | 少维护一个 tap 仓库，少一步人工 |
| livecheck | 无 | 有 | 4 行，让 `brew livecheck` 能自查，将来若上游到 homebrew-cask 也用得上 |
| CLI / manpage / shell completion | 有 | 无 | Noren 只有 GUI app + ShareExtension |

沿用 AeroSpace 的部分：不用 fastlane，只用 `xcodebuild` + `codesign` + `notarytool` + 少量 shell；
cask 的 `postflight` 去隔离属性；zip（而不是 dmg）分发。
