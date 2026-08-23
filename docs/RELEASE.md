# 发布手册

Nifro 不上 Mac App Store，分发走 **GitHub Release + Homebrew cask**。

涉及文件：

| 文件 | 作用 |
| --- | --- |
| `.github/workflows/release.yml` | 打 `v*` tag 触发，构建 → 签名 →（公证）→ 打包 → 建 Release → 回写 cask |
| `Tools/setup-signing.sh` | 生成自签名证书：装到本机钥匙串，或导出 `.p12` 给 CI |
| `Tools/build-local.sh` | 本机出一份和发布版同样签名方式的测试包 |
| `Casks/nifro.rb` | cask 定义，`version` / `sha256` 由流水线自动更新 |
| `Config.xcconfig` | `MARKETING_VERSION`，必须和 tag 对得上，流水线会校验 |

---

## 一、当前选定：自签名

**Nifro 走自签名证书**，参照 AeroSpace。不买 Apple Developer Program，因此不公证。

流水线只看 `MACOS_CERTIFICATE_P12` 里装的是哪种证书，自己判断走哪条，YAML 不用改：

```
                                    ┌─ 证书是 Developer ID ─→ 硬化运行时 + 公证 + staple
  push tag v* ─→ 导入证书 ─→ 看身份 ─┤
                     │              └─ 证书是自签名 ───────→ 只签名，不公证   ← 现在走这条
                     └─ 没有 secret ────────────────────────→ ad-hoc
```

### 自签名和 ad-hoc 差在哪

对 Gatekeeper 完全一样：两者都没通过公证，下载来的包首次打开都会被拦。差别在**签名身份稳不稳定**。

Nifro 是沙盒 app，用户把本地 HTML 文件设成壁纸时，存的是**安全作用域书签**
（`Nifro/Support/Extensions.swift` 里的 `BookmarksUserDefaults`）。书签绑在 app 的代码签名上：

```
ad-hoc    v0.1 签名 A ──┐
          v0.2 签名 B ──┴─→ 每次都是新签名 → 升级后书签失效 → 用户被重新弹文件选择器
自签名    v0.1 ┐
          v0.2 ┴─→ 指定要求恒为 certificate root = <同一张证书> → 授权跨版本保留
```

所以这里多做的一步不是为了「看起来更正规」，是为了升级不掉用户设置。

**证书丢了等于换身份。** 导出的 `.p12` 是唯一一份，丢了之后所有后续版本的指定要求都会变，
等同于对每个用户做了一次 ad-hoc 升级。备份它。

### 若将来买了账号：Developer ID + 公证

```
xcodebuild (CODE_SIGN_IDENTITY="Developer ID Application", hardened runtime)
   ↓
ditto -c -k --keepParent  →  notarize.zip
   ↓
xcrun notarytool submit --wait      （Apple 扫一遍，通常 1~10 分钟）
   ↓
xcrun stapler staple Nifro.app      （把公证票据钉进 app，用户离线也能过）
   ↓
spctl -a -vvv --type exec           （门禁自检，不过就 fail，不发坏包）
   ↓
Nifro-x.y.z.zip  →  GitHub Release  →  cask 回写 version/sha256
```

### 现在走的：自签名

```
Tools/setup-signing.sh --export nifro-release.p12   ← 一次性，本机 openssl 生成，不需要任何账号
   ↓  base64 后存进仓库 secret
xcodebuild (CODE_SIGN_IDENTITY="Nifro Signing")     ← 沙盒 entitlements 正常写进签名
   ↓
Nifro-x.y.z.zip  →  GitHub Release  →  cask 回写 version/sha256
                                        cask 的 postflight 去掉 com.apple.quarantine
```

`spctl` 检查会被跳过，流水线只打 warning，Release 说明里自动标注「未公证」。

**免费 Apple ID 不算数**：免费账号只能签 `Apple Development` 证书，7 天过期、只在本机有效，
不能用于分发。自签名证书反而没有这些限制，因为它压根不经过 Apple。

---

## 二、需要的 GitHub Secrets

自签名只要前两个，后四个是将来公证才用的。

| Secret | 内容 | 从哪来 | 自签名要吗 |
| --- | --- | --- | --- |
| `MACOS_CERTIFICATE_P12` | 证书 + 私钥的 `.p12`，**base64 编码** | `Tools/setup-signing.sh --export` 直接打印 | 要 |
| `MACOS_CERTIFICATE_PASSWORD` | 该 `.p12` 的密码 | 同上，脚本随机生成后打印 | 要 |
| `APPLE_TEAM_ID` | 10 位 Team ID，如 `ABCDE12345` | developer.apple.com → Membership | 不要 |
| `NOTARY_KEY_P8` | App Store Connect API 私钥 `AuthKey_XXXXXXXX.p8`，**base64 编码** | 见下方 A3 | 不要 |
| `NOTARY_KEY_ID` | 该 key 的 Key ID（8 位） | 生成 key 时页面上显示 | 不要 |
| `NOTARY_ISSUER_ID` | Issuer ID（UUID 格式） | App Store Connect → Integrations → Keys 页顶部 | 不要 |

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

**现在要做的（自签名，不需要 Apple 账号）：**

- **B0** 本机跑一次，把打印出来的两个值填进仓库 secret：

  ```bash
  ./Tools/setup-signing.sh --export ~/nifro-release.p12
  ```

  然后把 `~/nifro-release.p12` 备份到一个一年后还找得到的地方（见第一节「证书丢了等于换身份」），
  仓库里**不要**放这个文件。

**以下是将来买了付费账号才做的，现在跳过：**

- **A1** 在 Xcode → Settings → Accounts → Manage Certificates → `+` → **Developer ID Application**
  创建证书（或在 developer.apple.com → Certificates 里走 CSR 流程）。
- **A2** 打开「钥匙串访问」，找到该证书，**连带私钥一起**右键导出为 `.p12`，设一个密码。
  只导出证书不带私钥的话 CI 签不了名。
- **A3** appstoreconnect.apple.com → Users and Access → Integrations → Keys → 生成一个
  **Developer Access / App Manager** 权限的 API Key，下载 `.p8`（**只能下载一次**）。
- **A4** 把上表 6 个 secret 填进仓库。
- **A5** 第一次发布成功后，把 `Casks/nifro.rb` 里的整个 `postflight` 块删掉（公证之后不需要
  再去隔离属性，留着反而是负面信号）。换成 Developer ID 后签名身份会变一次，用户已授权的
  本地文件壁纸会失效一次——这是从自签名迁到公证的一次性代价，写进那一版的 Release 说明。

**无论哪条路都要做：**

- **B1** 创建 tap 仓库 `PathGao/homebrew-tap`，或者直接让用户 tap 本仓库
  （`brew tap PathGao/tap https://github.com/PathGao/nifro`，cask 就在本仓库 `Casks/` 下，
  不用维护第二个仓库 —— 这是更省事的做法）。
- **B2** 确认 `main` 分支保护规则允许 `github-actions[bot]` 推送，否则流水线最后一步
  「回写 cask」会失败（只是告警，Release 本身不受影响，可以手动改 cask）。
- **B3** ~~对齐 workflow 顶部的 `XCODE_SCHEME` / `BUILT_APP_NAME`~~ 已完成，两个值都是 `Nifro`。

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

剩下的流水线全包：构建、签名、公证、打包、建 Release、回写 `Casks/nifro.rb`。

失败时先看 Actions 里的 `xcodebuild-log` artifact。

---

## 五、用户拿到的东西长什么样

### 若将来公证了

| 安装方式 | 用户体验 |
| --- | --- |
| `brew install --cask PathGao/tap/nifro` | 装完直接能开，无提示 |
| 下载 zip 双击 | 首次弹「Nifro 是从互联网下载的，确定要打开吗？」→ 点「打开」→ 结束 |

### 现在（自签名，未公证）

| 安装方式 | 用户体验 |
| --- | --- |
| `brew install --cask PathGao/tap/nifro` | 装完直接能开，无提示（cask 的 `postflight` 已去掉隔离属性） |
| 下载 zip 双击 | **被拦**：「无法打开 Nifro，因为 Apple 无法检查其是否包含恶意软件」，只有「移到废纸篓 / 取消」两个按钮 |

直接下载 zip 的用户需要额外一步。放进 README 安装章节的说明：

> 首次打开时 macOS 会提示「无法打开 Nifro，因为 Apple 无法检查其是否包含恶意软件」。
> 这是因为 Nifro 没有经过 Apple 公证（公证需要 99 美元/年的开发者账号）。
> 用 Homebrew 安装不会遇到这个提示。
>
> 手动放行，二选一：
>
> 1. 打开一次被拦的 app → 「系统设置 → 隐私与安全性」→ 拉到底 → 点「仍要打开」。
> 2. 或者在终端里执行：
>    ```bash
>    xattr -dr com.apple.quarantine /Applications/Nifro.app
>    ```

**别让用户去关 SIP 或 `spctl --master-disable`**，那是降低整机安全等级，不是解决这个问题的办法。

---

## 六、这套方案和 AeroSpace 的关系

参照对象是 [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace)。它的实际做法：

- **签名**：`build-release.sh` 里 `codesign -s "aerospace-codesign-certificate"`，是维护者本机
  钥匙串里的一张**自签名证书**，不是 Developer ID。CI (`build.yml`) 上用
  `./build-release.sh --codesign-identity -`，注释直说「GH Actions 上没有那张证书」。
  Nifro 这里做得更进一步：证书导出成 `.p12` 存进仓库 secret，CI 也拿得到同一张，
  所以正式发布不会因为「在谁的机器上打的包」而换签名身份。
- **公证**：不做。README 里明确说不公证。
- **发布**：**没有 release workflow**。`.github/workflows/` 下只有 `build.yml` 和两个 issue 机器人。
  真正发版靠维护者本机跑 `script/publish-release.sh`：打 tag、`open` 浏览器、**手动把 zip 拖进
  GitHub Release 页面**、回车继续。
- **cask**：自己的 tap（`nikitabobko/homebrew-tap`），`Casks/aerospace.rb` 由
  `script/build-brew-cask.sh` 生成后 `cp` 过去。没有 livecheck，`version` 是写死的字面量。
  靠 `postflight` 里的 `xattr -d com.apple.quarantine` 让 brew 用户绕过 Gatekeeper。

Nifro 的偏离：

| 项 | AeroSpace | Nifro | 原因 |
| --- | --- | --- | --- |
| 发布触发 | 本机脚本 + 手动上传 | tag 触发 GitHub Actions | 本机发版要求维护者机器状态正确，且不可复现 |
| 签名 | 自签名证书（只在本机） | 自签名证书（本机 + CI 共用一张） | 对 Gatekeeper 两者等价，但固定身份能让沙盒书签跨版本存活；CI 也拿得到才谈得上「固定」 |
| 公证 | 不做 | 现在不做，留好开关 | 现阶段一样不公证；流水线按证书类型自动切，将来买账号只换一个 secret |
| cask 版本 | 手动生成后 cp | CI `sed` 回写本仓库 `Casks/` | 少维护一个 tap 仓库，少一步人工 |
| livecheck | 无 | 有 | 4 行，让 `brew livecheck` 能自查，将来若上游到 homebrew-cask 也用得上 |
| CLI / manpage / shell completion | 有 | 无 | Nifro 只有 GUI app + ShareExtension |

沿用 AeroSpace 的部分：不用 fastlane，只用 `xcodebuild` + `codesign` + `notarytool` + 少量 shell；
cask 的 `postflight` 去隔离属性；zip（而不是 dmg）分发。
