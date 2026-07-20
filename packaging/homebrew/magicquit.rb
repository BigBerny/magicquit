# Draft cask for homebrew/homebrew-cask (or a personal tap).
# Update version + sha256 after each release (scripts/release.sh prints the sha).
cask "magicquit" do
  version "2.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_SCRIPT"

  url "https://github.com/BigBerny/magicquit/releases/download/v#{version}/MagicQuit-#{version}.zip"
  name "MagicQuit"
  desc "Automatically quits apps that are idle or whose last window was closed"
  homepage "https://github.com/BigBerny/magicquit"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "MagicQuit.app"

  zap trash: [
    "~/Library/Preferences/com.MagicQuit.plist",
  ]
end
