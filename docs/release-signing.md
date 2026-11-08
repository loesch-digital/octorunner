# Apple signing for GitHub releases

GitHub releases require a Developer ID Application signature, Apple's accepted
notarization, a stapled ticket, and a successful Gatekeeper assessment. The final
ZIP is created after these checks. Missing credentials or any failed check stops
publication. The Homebrew cask no longer removes quarantine attributes.

## One-time setup

The existing Developer ID certificate and private key live encrypted in the
Fastlane Match repository. The release runner imports them into a temporary
keychain with `fastlane mac sync_certificates` in readonly mode.

Add these repository Actions secrets under Settings → Secrets and variables
→ Actions:

| Secret | Value |
| --- | --- |
| `MATCH_GIT_URL` | Existing Match repository URL; an Actions variable is also supported |
| `MATCH_PASSWORD` | Existing Match repository encryption password |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Base64-encoded `username:token` for HTTPS read access to the private Match repository |
| `NOTARY_KEY_BASE64` | Base64-encoded team App Store Connect API private key (`.p8`) |
| `NOTARY_KEY_ID` | API Key ID |
| `NOTARY_ISSUER_ID` | Team API Issuer ID |

The repository access token needs Contents read permission on the Match repository.
The OctoRunner workflow's default `GITHUB_TOKEN` cannot read another private
repository. Use a team API key authorized for notarization on the same Apple team
as the Developer ID certificate.

Never commit private keys or paste passwords or tokens into chat. The signing
script deletes its temporary keychain and decoded notarization key on exit.
GitHub release signing uses `scripts/sign-and-notarize.sh`; the older local
Fastlane lane can still produce development/ad-hoc builds and is not evidence of
notarization.

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
