#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: update-homebrew-cask.sh <version>}"
ZIP_FILE="dist/OctoRunner-${VERSION}-arm64.zip"

if [[ ! -f "$ZIP_FILE" ]]; then
  echo "Error: Release archive $ZIP_FILE not found!"
  exit 1
fi

SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')
echo "Computed SHA256 for v${VERSION}: ${SHA256}"

TAP_DIR=$(mktemp -d)
trap 'rm -rf "$TAP_DIR"' EXIT

gh repo clone loesch-digital/homebrew-octorunner "$TAP_DIR"
mkdir -p "$TAP_DIR/Casks"

cat > "$TAP_DIR/Casks/octorunner.rb" <<EOF
cask "octorunner" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/loesch-digital/octorunner/releases/download/v#{version}/OctoRunner-#{version}-arm64.zip"
  name "OctoRunner"
  desc "Native macOS desktop manager for self-hosted GitHub Actions runners"
  homepage "https://github.com/loesch-digital/octorunner"

  depends_on macos: :sequoia
  depends_on arch: :arm64

  app "OctoRunner.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/OctoRunner.app"],
                   sudo: false
  end

  uninstall quit: "io.octorunner.macos"

  zap trash: [
    "~/Library/Application Support/OctoRunner",
    "~/Library/Caches/io.octorunner.macos",
    "~/Library/Logs/OctoRunner",
    "~/Library/Preferences/io.octorunner.macos.plist",
  ]
end
EOF

cat > "$TAP_DIR/README.md" <<EOF
# Homebrew Tap for OctoRunner

Install **OctoRunner** (\`v${VERSION}\`) on macOS (Apple Silicon, macOS 15+):

\`\`\`bash
brew tap loesch-digital/octorunner
brew install --cask octorunner
\`\`\`

Upgrade to the latest version:

\`\`\`bash
brew update && brew upgrade --cask octorunner
\`\`\`
EOF

cd "$TAP_DIR"
git add Casks/octorunner.rb README.md
if git diff --cached --quiet; then
  echo "Homebrew cask already up to date."
else
  git commit -m "chore(cask): update octorunner to v${VERSION}"
  git push origin HEAD:main
  echo "Successfully updated loesch-digital/homebrew-octorunner Cask to v${VERSION}!"
fi
