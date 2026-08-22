# Homebrew cask，供 PathGao/homebrew-tap 使用。
#
#   brew tap PathGao/tap https://github.com/PathGao/noren
#   brew install --cask PathGao/tap/noren
#
# version 和 sha256 由 .github/workflows/release.yml 在每次发布后自动回写，不要手改。
cask "noren" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/PathGao/noren/releases/download/v#{version}/Noren-#{version}.zip",
      verified: "github.com/PathGao/noren/"
  name "Noren"
  desc "Web page as your desktop wallpaper"
  homepage "https://github.com/PathGao/noren"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 工程的 MACOSX_DEPLOYMENT_TARGET = 15.2
  depends_on macos: ">= :sequoia"

  app "Noren.app"

  # ⚠️ 只有在「未公证」的构建下才需要这段。
  # 一旦发布流水线拿到 Developer ID 证书并开始公证（见 docs/RELEASE.md 路径 A），
  # 把整个 postflight 块删掉。
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Noren.app"],
                   must_succeed: false
  end

  # 沙盒 app，用户数据都在容器里
  zap trash: [
    "~/Library/Containers/com.pathgao.noren",
    "~/Library/Containers/com.pathgao.noren.ShareExtension",
    "~/Library/Application Scripts/com.pathgao.noren",
    "~/Library/Application Scripts/com.pathgao.noren.ShareExtension",
  ]
end
