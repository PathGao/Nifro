# Homebrew cask, for use from PathGao/homebrew-tap.
#
#   brew tap PathGao/tap https://github.com/PathGao/Nifro
#   brew trust --cask PathGao/tap/nifro
#   brew install --cask nifro
#
# The `brew trust` line is needed because of the postflight block below: Homebrew will not load a
# cask from outside its own repositories until the user says they trust it, since a cask can run
# code after installing. Leave it out and `brew install` refuses.
#
# version and sha256 are written back by .github/workflows/release.yml after every release, as a
# pull request somebody still has to merge. Do not edit them by hand.
#
# Each architecture ships a thin binary, and there is no universal package — a universal package
# means every user downloads the half they can never run. brew picks the right one for the machine.
cask "nifro" do
  arch arm: "arm64", intel: "x86_64"

  version "0.9.0"
  sha256 arm: "35c69372ab268208d38eaf1ac679cd9e951d56d2e9b69be00cd05c64c1a27039", intel: "c4d391242093d452622af262210284decdb251f207acffd2dfbd3408850fc5a2"

  url "https://github.com/PathGao/Nifro/releases/download/v#{version}/Nifro-#{arch}.dmg",
      verified: "github.com/PathGao/Nifro/"
  name "Nifro"
  desc "Web page as your desktop wallpaper"
  homepage "https://github.com/PathGao/Nifro"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The project's MACOSX_DEPLOYMENT_TARGET = 15.0. The symbol form means this version or newer; the
  # string form that says so out loud is deprecated, and printed a warning on every `brew tap`.
  depends_on macos: :sequoia

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
