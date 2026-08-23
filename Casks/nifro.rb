# Homebrew cask，供 PathGao/homebrew-tap 使用。
#
#   brew tap PathGao/tap https://github.com/PathGao/nifro
#   brew install --cask PathGao/tap/nifro
#
# version 和 sha256 由 .github/workflows/release.yml 在每次发布后自动回写，不要手改。
#
# 两个架构各发一份瘦二进制，不做通用包 —— 通用包等于让每个用户下载一份
# 自己永远用不到的另一半。brew 会按机器自己选。
cask "nifro" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.0"
  sha256 arm:   "0000000000000000000000000000000000000000000000000000000000000000",
         intel: "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/PathGao/nifro/releases/download/v#{version}/Nifro-#{version}-#{arch}.zip",
      verified: "github.com/PathGao/nifro/"
  name "Nifro"
  desc "Web page as your desktop wallpaper"
  homepage "https://github.com/PathGao/nifro"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 工程的 MACOSX_DEPLOYMENT_TARGET = 15.0
  depends_on macos: ">= :sequoia"

  app "Nifro.app"

  # ⚠️ 只有在「未公证」的构建下才需要这段。
  # 一旦发布流水线拿到 Developer ID 证书并开始公证（见 docs/RELEASE.md 路径 A），
  # 把整个 postflight 块删掉。
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Nifro.app"],
                   must_succeed: false
  end

  # 沙盒 app，用户数据都在容器里。最后一条只为保险：正常的沙盒构建永远不会写到那里，
  # 但一个签名时丢掉了 entitlements 的构建会，而那种包用户也可能装过。
  zap trash: [
    "~/Library/Containers/com.pathgao.nifro",
    "~/Library/Containers/com.pathgao.nifro.ShareExtension",
    "~/Library/Application Scripts/com.pathgao.nifro",
    "~/Library/Application Scripts/com.pathgao.nifro.ShareExtension",
    "~/Library/Preferences/com.pathgao.nifro.plist",
  ]
end
