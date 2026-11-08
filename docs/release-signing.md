# Apple signing for GitHub releases

GitHub releases require a Developer ID Application signature, Apple's accepted
notarization, a stapled ticket, and a successful Gatekeeper assessment. The final
ZIP is created after these checks. Missing credentials or any failed check stops
publication. The Homebrew cask no longer removes quarantine attributes.

## One-time setup

1. In the Apple Developer account, create a **Developer ID Application**
   certificate for the intended team. Export the certificate **with its private
   key** from Keychain Access as a password-protected `.p12` file. Apple Development
   and Apple Distribution certificates are not substitutes.
2. Create a **team App Store Connect API key** with permission to submit
   notarizations. Keep its `.p8` private key, Key ID, and Issuer ID. Use the same
   developer team as the certificate.
3. Add these repository Actions secrets under Settings → Secrets and variables
   → Actions:

| Secret | Value |
| --- | --- |
| `SIGNING_CERTIFICATE_BASE64` | Base64-encoded `.p12`, including the private key |
| `SIGNING_CERTIFICATE_PASSWORD` | Export password for that `.p12` |
| `NOTARY_KEY_BASE64` | Base64-encoded API private key (`.p8`) |
| `NOTARY_KEY_ID` | API Key ID |
| `NOTARY_ISSUER_ID` | Team API Issuer ID |

Upload file contents directly without printing private keys:

```bash
base64 -i /path/to/DeveloperID.p12 | gh secret set SIGNING_CERTIFICATE_BASE64
gh secret set SIGNING_CERTIFICATE_PASSWORD
base64 -i /path/to/AuthKey.p8 | gh secret set NOTARY_KEY_BASE64
gh secret set NOTARY_KEY_ID
gh secret set NOTARY_ISSUER_ID
```

Never commit these files or paste private keys or passwords into chat. The signing
script imports the certificate into a temporary keychain and deletes that
keychain and the decoded credentials on exit. GitHub release signing uses
`scripts/sign-and-notarize.sh`; the older local Fastlane lane can still produce
development/ad-hoc builds and is not evidence of notarization.

After configuring secrets, publish a new patch version from verified `main`.
Do not replace an already published archive: Homebrew caches archives and checks
their SHA-256 digests.

## Verification

```bash
python3 -m unittest discover -s scripts/tests -v
codesign --verify --deep --strict --verbose=2 /path/to/OctoRunner.app
xcrun stapler validate /path/to/OctoRunner.app
spctl --assess --type execute --verbose=2 /path/to/OctoRunner.app
```

The unit tests exercise success and rejection paths with command stubs; only a
real release using Apple credentials verifies the certificate and notarization.

Reference: [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
