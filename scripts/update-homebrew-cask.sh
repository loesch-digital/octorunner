#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: update-homebrew-cask.sh <version>}"
ZIP_FILE="dist/OctoRunner-${VERSION}-arm64.zip"

if [[ ! -f "$ZIP_FILE" ]]; then
  echo "Error: Release archive $ZIP_FILE not found!"
  exit 1
fi

SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')
CASK=$(python3 scripts/release_tools.py cask "v${VERSION}" "${SHA256}")
echo "Computed SHA256 for v${VERSION}: ${SHA256}"

TAP_DIR=$(mktemp -d)
trap 'rm -rf "$TAP_DIR"' EXIT

gh repo clone loesch-digital/homebrew-tap "$TAP_DIR"
mkdir -p "$TAP_DIR/Casks"

printf '%s\n' "$CASK" > "$TAP_DIR/Casks/octorunner.rb"

cd "$TAP_DIR"
git add Casks/octorunner.rb
if git diff --cached --quiet; then
  echo "Homebrew cask already up to date."
else
  git commit -m "chore(cask): update octorunner to v${VERSION}"
  git push origin HEAD:main
  echo "Successfully updated loesch-digital/tap/octorunner to v${VERSION}!"
fi
