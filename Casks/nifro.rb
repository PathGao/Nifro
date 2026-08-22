# Homebrew cask，供 PathGao/homebrew-tap 使用。
#
#   brew tap PathGao/tap https://github.com/PathGao/nifro
#   brew install --cask PathGao/tap/nifro
#
# version 和 sha256 由 .github/workflows/release.yml 在每次发布后自动回写，不要手改。
cask "nifro" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/PathGao/nifro/releases/download/v#{version}/Nifro-#{version}.zip",
      verified: "github.com/PathGao/nifro/"
  name "Nifro"
  desc "Web page as your desktop wallpaper"
  homepage "https://github.com/PathGao/nifro"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 工程的 MACOSX_DEPLOYMENT_TARGET = 15.2
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

  # 沙盒 app，用户数据都在容器里
  zap trash: [
    "~/Library/Containers/com.pathgao.nifro",
    "~/Library/Containers/com.pathgao.nifro.ShareExtension",
    "~/Library/Application Scripts/com.pathgao.nifro",
    "~/Library/Application Scripts/com.pathgao.nifro.ShareExtension",
  ]
end
