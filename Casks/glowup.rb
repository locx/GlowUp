cask "glowup" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/lokeshchauhan/GlowUp/releases/download/v#{version}/GlowUp.dmg"
  name "GlowUp"
  desc "Safe, open-source macOS cleanup utility"
  homepage "https://github.com/lokeshchauhan/GlowUp"

  depends_on macos: ">= :ventura"

  app "GlowUp.app"

  zap trash: [
    "~/Library/Application Support/GlowUp",
  ]
end
