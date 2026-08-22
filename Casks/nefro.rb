# Homebrew cask，供 PathGao/homebrew-tap 使用。
#
#   brew tap PathGao/tap https://github.com/PathGao/nefro
#   brew install --cask PathGao/tap/nefro
#
# version 和 sha256 由 .github/workflows/release.yml 在每次发布后自动回写，不要手改。
cask "nefro" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/PathGao/nefro/releases/download/v#{version}/Nefro-#{version}.zip",
      verified: "github.com/PathGao/nefro/"
  name "Nefro"
  desc "Web page as your desktop wallpaper"
  homepage "https://github.com/PathGao/nefro"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 工程的 MACOSX_DEPLOYMENT_TARGET = 15.2
  depends_on macos: ">= :sequoia"

  app "Nefro.app"

  # ⚠️ 只有在「未公证」的构建下才需要这段。
  # 一旦发布流水线拿到 Developer ID 证书并开始公证（见 docs/RELEASE.md 路径 A），
  # 把整个 postflight 块删掉。
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Nefro.app"],
                   must_succeed: false
  end

  # 沙盒 app，用户数据都在容器里
  zap trash: [
    "~/Library/Containers/com.pathgao.nefro",
    "~/Library/Containers/com.pathgao.nefro.ShareExtension",
    "~/Library/Application Scripts/com.pathgao.nefro",
    "~/Library/Application Scripts/com.pathgao.nefro.ShareExtension",
  ]
end
