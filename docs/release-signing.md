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
Swift test commands in CI and releases run through `scripts/run-swift-tests.py`.
It preserves the original exit status and streams output into
`DerivedData/SwiftTestDiagnostics/swift-tests.log`. Once tests have started,
120 seconds without output triggers stack sampling of up to eight processes in
the wrapper's private POSIX session (including SwiftPM's separate child groups), followed by a failed exit (124). A separate
10-minute total deadline also bounds compilation. Compilation does not use the
short test-idle deadline. Sampling is best-effort and bounded; only this command's
private session is terminated after freshly checking session/group membership. No existing runner or app is signalled,
and no process arguments or environment dumps are collected. The diagnostics
artifact is uploaded on failure as well as success. These are diagnostic limits,
not retries or skipped tests.

On 2026-11-14, main run `43579538373` hit the job limit after the existing
`Acknowledgement persists across restarts ...` test began. The same test passed
in PR run `43578763517` and locally with coverage. The underlying intermittent
hang recurred in PR run `44462124714` on 2026-11-19 and was bounded by the
watchdog. The first artifact contained only the waiting SwiftPM parent: its
test helper starts a separate process group. The launcher therefore follows its
new private session and rechecks membership before sampling or signalling.
Processes that leave that session are excluded. A subsequent local three-repetition run reproduced the stall. Sampling the actual
test helper showed synchronous `Process.waitUntilExit()` in HTTP test-server
cleanup. PR #28 replaced that fixture with asynchronously observed termination
and added lifecycle regressions. Its main run then exposed an independent native
UI launch failure: the app adopted accessory activation policy before its first
window. PR #29 adds a startup-policy regression and preserves regular activation
until a window has appeared. PR and main run `44470817545` passed, including
native UI tests. This evidence fixes two demonstrated defects; it does not infer
the original CI stack from its last buffered test line. A further EOF regression
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

The unit tests exercise success and rejection paths with command stubs; only a
real release using Apple credentials verifies the certificate and notarization.

Reference: [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Prereleases

Validated tags may also use `vX.Y.Z-beta.N` or `vX.Y.Z-rc.N` (positive N).
`scripts/release_tools.py` separates the complete release version from Apple's
numeric `CFBundleShortVersionString` / `CFBundleVersion`. Before signing, it
checks the built bundle identity and numeric versions, then writes the complete
version into `OctoRunnerReleaseVersion`; the app uses this for display and SemVer
update checks. A generic `INFOPLIST_KEY_` build setting did not preserve the custom
key in the verified local Xcode build, so stamping is explicit.

Prereleases are published with `--prerelease --latest=false`, use reviewed notes
from `docs/releases/<tag>.md` when available, and skip the stable Homebrew tap.
They retain the same Developer ID/notarization/Gatekeeper requirements. Direct
ZIP installation is their acceptance path. Stable releases keep the Homebrew
upgrade check. No archive or existing release is replaced.
