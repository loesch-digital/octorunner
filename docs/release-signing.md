# Apple signing for GitHub releases

For development acceptance before a release, use the [local Xcode / Debug workflow](10-development-and-acceptance.md). It does not require installing the app through Homebrew or using release signing secrets. The same guide covers installing the signed release ZIP directly.

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
| `MATCH_GIT_TOKEN` | Unmodified fine-grained GitHub token with Contents read access to the Match repository |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Unmodified contents of the team App Store Connect API private key (`.p8`) |
| `APP_STORE_CONNECT_API_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Team API Issuer ID |

Paste the token directly into the secret; no local encoding is needed. The release
script encodes it for Match and masks the derived value in GitHub Actions logs.
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

The workflow uses Xcode 27.2 explicitly, runs the Python signing regressions,
serializes publications, and refuses existing GitHub releases. Failed releases
must use a new patch tag; the workflow never uploads assets with `--clobber`.

CI jobs have an explicit 20-minute execution limit. Release jobs have a
60-minute limit, including the notarization command's separate 30-minute wait
limit. These limits apply after a runner starts the job; queue time is separate.
When a watch stops updating, check the run's current status and step directly
instead of treating an open local watch as evidence that GitHub is still busy.
The additional `xcode-27` label is registered in `.github/actionlint.yaml` for
local validation because actionlint's built-in label list does not include it.

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
