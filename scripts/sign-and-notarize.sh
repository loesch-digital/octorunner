#!/usr/bin/env bash
# Release archives are created only after Apple's acceptance and Gatekeeper validation.
set -euo pipefail

APP_PATH="${1:?Usage: sign-and-notarize.sh <app-path> <output.zip>}"
ZIP_PATH="${2:?Usage: sign-and-notarize.sh <app-path> <output.zip>}"

for name in MATCH_GIT_URL MATCH_PASSWORD NOTARY_KEY_BASE64 NOTARY_KEY_ID NOTARY_ISSUER_ID; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required release secret: ${name}" >&2
    exit 1
  fi
done
[[ -d "$APP_PATH" ]] || { echo "App not found: $APP_PATH" >&2; exit 1; }
# Prevent a stale archive from being mistaken for a successfully notarized release.
rm -f "$ZIP_PATH"
umask 077
SIGNING_DIR=$(mktemp -d)
KEYCHAIN_PATH="$SIGNING_DIR/release.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT

printf '%s' "$NOTARY_KEY_BASE64" | base64 --decode > "$SIGNING_DIR/AuthKey.p8"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
# Match imports the existing certificate/private key and configures signing access.
# CI forces the lane into readonly mode; releases must never create certificates.
CI=true MATCH_KEYCHAIN_NAME="$KEYCHAIN_PATH" MATCH_KEYCHAIN_PASSWORD="$KEYCHAIN_PASSWORD" \
  fastlane mac sync_certificates
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | sed -nE '/"Developer ID Application:/s/.*\) ([A-Fa-f0-9]{40}) .*/\1/p' | head -1)
[[ -n "$IDENTITY" ]] || { echo "No valid Developer ID Application identity in certificate." >&2; exit 1; }

codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN_PATH" \
  --options runtime --timestamp --entitlements App/OctoRunner.entitlements "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SIGNING_DIR/submission.zip"
xcrun notarytool submit "$SIGNING_DIR/submission.zip" \
  --key "$SIGNING_DIR/AuthKey.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
  --wait --timeout 30m --output-format json > "$SIGNING_DIR/notarization.json"
python3 - "$SIGNING_DIR/notarization.json" <<'PY'
import json, sys
with open(sys.argv[1]) as result:
    response = json.load(result)
if response.get("status") != "Accepted":
    raise SystemExit(f"Apple notarization failed: {response}")
print("Apple notarization accepted.")
PY
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"
mkdir -p "$(dirname "$ZIP_PATH")"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
