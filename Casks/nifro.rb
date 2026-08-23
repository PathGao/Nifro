# Homebrew cask, for use from PathGao/homebrew-tap.
#
#   brew tap PathGao/tap https://github.com/PathGao/Nifro
#   brew install --cask PathGao/tap/nifro
#
# version and sha256 are written back automatically by .github/workflows/release.yml after every
# release. Do not edit them by hand.
#
# Each architecture ships a thin binary, and there is no universal package — a universal package
# means every user downloads the half they can never run. brew picks the right one for the machine.
cask "nifro" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.0"
  sha256 arm: "0000000000000000000000000000000000000000000000000000000000000000", intel: "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/PathGao/Nifro/releases/download/v#{version}/Nifro-#{version}-#{arch}.dmg",
      verified: "github.com/PathGao/Nifro/"
  name "Nifro"
  desc "Web page as your desktop wallpaper"
  homepage "https://github.com/PathGao/Nifro"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The project's MACOSX_DEPLOYMENT_TARGET = 15.0
  depends_on macos: ">= :sequoia"

  app "Nifro.app"

  # ⚠️ This block is only needed for builds that are not notarized.
  # Once the release pipeline has a Developer ID certificate and starts notarizing (path A in
  # docs/RELEASE.md), delete the whole postflight block.
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Nifro.app"],
                   must_succeed: false
  end

  # Sandboxed app, so user data lives in the container. The last entry is only insurance: a proper
  # sandboxed build never writes there, but a build that lost its entitlements while being signed
  # does, and a user may well have installed one of those.
  zap trash: [
    "~/Library/Containers/com.pathgao.nifro",
    "~/Library/Containers/com.pathgao.nifro.ShareExtension",
    "~/Library/Application Scripts/com.pathgao.nifro",
    "~/Library/Application Scripts/com.pathgao.nifro.ShareExtension",
    "~/Library/Preferences/com.pathgao.nifro.plist",
  ]
end
