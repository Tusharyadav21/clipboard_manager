cask "clipboard-manager" do
  version "1.0.0"
  sha256 "d3521179e91b215b0c314b8e73b389562c982e5a80f70d5c286ca078031bc4c2"

  url "https://github.com/Tusharyadav21/clipboard_manager/releases/download/v#{version}/Clipboard.Manager.dmg"
  name "Clipboard Manager"
  desc "Local-first secure clipboard history manager for macOS"
  homepage "https://github.com/Tusharyadav21/clipboard_manager"

  app "clipboard manager.app"

  zap trash: [
    "~/Library/Application Support/com.tusharyadav.clipboard-manager",
    "~/Library/Preferences/com.tusharyadav.clipboard-manager.plist",
  ]
end
