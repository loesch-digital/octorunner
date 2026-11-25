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

Add the following repository secrets under **Settings → Secrets and variables → Actions**.

| Secret | Value |
| --- | --- |
| `MATCH_GIT_URL` | Existing Match repository URL. An Actions variable also works. |
| `MATCH_PASSWORD` | Existing Match repository encryption password |
| `MATCH_GIT_TOKEN` | Unmodified fine-grained GitHub token with Contents read access to the Match repository |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Unmodified contents of the team App Store Connect API private key (`.p8`) |
| `APP_STORE_CONNECT_API_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Team API Issuer ID |

Paste the token directly into the secret. The release
script encodes it for Match and masks the derived value in GitHub Actions logs.
The repository access token needs Contents read permission on the Match repository.
The OctoRunner workflow's default `GITHUB_TOKEN` cannot read another private
repository. Use a team API key authorized for notarization on the same Apple team
as the Developer ID certificate.

Never commit private keys or paste passwords or tokens into chat. The signing
script deletes its temporary keychain and decoded notarization key on exit.
GitHub release signing uses `scripts/sign-and-notarize.sh`. The older local
Fastlane lane remains available for development and ad hoc builds.

## Sign the background helper and app

For v0.8 and later, the release build embeds the executable at
`OctoRunner.app/Contents/MacOS/OctoRunnerBackgroundMonitor`. The release script
requires it to be present and executable. It signs the helper first, then the app
bundle, with the same existing Developer ID Application identity. Both signatures
use the hardened runtime and a secure timestamp. Only the outer app receives
`App/OctoRunner.entitlements`. The helper uses no Apple account capabilities or
provisioning profile. The release runner then submits the signed app for
notarization, staples the ticket, and checks Gatekeeper before creating the ZIP.

To reproduce the signing steps locally, build the Release configuration and work
on a copy of the app bundle. Set `SIGNING_IDENTITY` to the local Developer ID
Application identity and `APP_PATH` to the copy's path. Run these commands from
the repository root with the identity available in your local Keychain search list.

```bash
HELPER_PATH="$APP_PATH/Contents/MacOS/OctoRunnerBackgroundMonitor"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$HELPER_PATH"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
  --entitlements App/OctoRunner.entitlements "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$HELPER_PATH"
```

The helper's signature shows the `runtime` flag and a `Timestamp`. Signature
inspection can reveal the identity's account name and team ID. Share redacted
output only. For notarization, stapling, and public distribution, use the release
workflow with its configured GitHub secrets.

## Publish a verified release

After configuring secrets, publish a new patch version from verified `main`.
Do not replace an already published archive: Homebrew caches archives and checks
their SHA-256 digests.

The workflow uses Xcode 27.2, runs the Python signing regression tests,
serializes publications, and refuses existing GitHub releases. After a failed
release, use a new patch tag. The workflow preserves existing assets by omitting
`--clobber`.

CI jobs have an explicit 20-minute execution limit. Release jobs have a
60-minute limit, including the notarization command's separate 30-minute wait
limit. These limits apply to execution time after a runner starts the job.
When a watch stops updating, check the run's current status and step directly
instead of treating an open local watch as evidence that GitHub is still busy.
Swift test commands in CI and releases run through `scripts/run-swift-tests.py`.
It preserves the original exit status and streams output into
`DerivedData/SwiftTestDiagnostics/swift-tests.log`. Once tests have started,
120 seconds without output triggers stack sampling of up to eight processes in
the wrapper's private POSIX session, including SwiftPM's separate child groups.
The wrapper then exits with status 124. A separate 10-minute deadline bounds the
entire command, including compilation. The shorter idle deadline applies only
after tests start. Sampling is bounded and best effort. The wrapper rechecks
session and group membership before signaling only processes in its private
session. Diagnostics exclude process arguments and environment dumps. The
workflow uploads the artifact on success and failure and runs the full test
command once.

On 2026-11-14, main run `43579538373` hit the job limit after the existing
`Acknowledgement persists across restarts ...` test began. The same test passed
in PR run `43578763517` and locally with coverage. The underlying intermittent
hang recurred in PR run `44462124714` on 2026-11-19 and was bounded by the
watchdog. The first artifact contained only the waiting SwiftPM parent because its test
helper starts a separate process group. The launcher therefore follows its
new private session and rechecks membership before sampling or signaling.
Processes that leave that session are excluded. A subsequent local three-repetition run reproduced the stall. Sampling the actual
test helper showed synchronous `Process.waitUntilExit()` in HTTP test-server
cleanup. PR #28 replaced that fixture with asynchronously observed termination
and added lifecycle regressions. Its main run then exposed an independent native
UI launch failure: the app adopted accessory activation policy before its first
window. PR #29 adds a startup-policy regression and preserves regular activation
until a window has appeared. PR CI and main run `44470817545` passed, including
native UI tests. The fixes address the two observed defects. The original CI
helper stack remains unknown. A further EOF regression
removes watchdog busy-polling when output closes before the child exits.

The additional `xcode-27` label is registered in `.github/actionlint.yaml` for
local validation because actionlint's built-in label list does not include it.

## Verification

```bash
python3 -m unittest discover -s scripts/tests -v
codesign --verify --deep --strict --verbose=2 /path/to/OctoRunner.app
xcrun stapler validate /path/to/OctoRunner.app
spctl --assess --type execute --verbose=2 /path/to/OctoRunner.app
```

The unit tests exercise success and rejection paths with command stubs. Verify
the certificate and notarization with a real release using Apple credentials. [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Prereleases

Validated tags may also use `vX.Y.Z-beta.N` or `vX.Y.Z-rc.N` (positive N).
`scripts/release_tools.py` separates the complete release version from Apple's
numeric `CFBundleShortVersionString` / `CFBundleVersion`. Before signing, it
checks the built bundle identity and numeric versions, then writes the complete
version into `OctoRunnerReleaseVersion`. The app uses this value for display and
SemVer update checks. A generic `INFOPLIST_KEY_` build setting did not preserve the custom
key in the verified local Xcode build, so stamping is explicit.

Prereleases are published with `--prerelease --latest=false`, use reviewed notes
from `docs/releases/<tag>.md` when available, and skip the stable Homebrew tap.
They retain the same Developer ID/notarization/Gatekeeper requirements. Direct
ZIP installation is their acceptance path. Stable releases keep the Homebrew
upgrade check. No archive or existing release is replaced.
