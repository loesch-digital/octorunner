# Pipeline, Privacy, and Test Audit (November 11, 2026)

## Verified release status

- [v0.4.2](https://github.com/loesch-digital/octorunner/actions/runs/43046560949) failed during signing. Match imported the certificate, and the signing step then reported `The specified item could not be found in the keychain`.
- The [v0.4.3 release](https://github.com/loesch-digital/octorunner/actions/runs/43049252599) and [main CI](https://github.com/loesch-digital/octorunner/actions/runs/43049252861) passed. v0.4.3 shipped the Keychain search path fix. The published tag and archive are final.

## Patch v0.4.4

v0.4.4 added an Xcode 27.2 build alongside the existing `macos-15` image. Beginning with the Step 5 branch, CI and releases use only the official `xcode-27` image, with Xcode 27.2 explicitly selected, as requested by the user. The build SDK and the app’s deployment target are independent. The macOS 15 deployment target still requires runtime testing on macOS 15. Swift 6 language mode and `complete` strict concurrency remain required. The minimum SPM tools version of 6.0 can be used with a newer compiler.

On November 11, 2026, local verification used Xcode 27.2 (27B52) and Swift 6.4.2. The latest stable versions verified that day were Xcode 27.2, checkout v7.0.1, and release-it 21.1.2. [Apple](https://developer.apple.com/xcode/system-requirements/), [runner images](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), [checkout releases](https://github.com/actions/checkout/releases).

Homebrew availability checks run quietly and installation errors stay visible. Python signing tests also run before releases. CI receives only `contents: read`. Releases are published serially, and `gh release create --verify-tag` rejects duplicate releases to prevent replacing archives with `--clobber`. PR CI runs on `pull_request`. Push CI runs only on `main`.

CI collects coverage for the selected toolchain and retains JSON reports as artifacts for 14 days using `actions/upload-artifact@v7`. v7.0.2 was the verified version at the time. The team prioritizes tests for failure paths and has left the overall coverage threshold unset because UI rendering can inflate the aggregate number.

## Why macOS requested Documents access

At startup, discovery looked for `.runner` under `~/Documents/apps/actions-runner` and `~/Documents/actions-runner`, along with paths found in the process table. The embedded log view also read previously imported external runners. The installed app’s startup reads triggered the prompt, independently of where the OctoRunner source repository was stored. [Apple’s file and folder access guide](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac).

After reviewing the behavior with the user, the patch made these changes.

- Automatic discovery checks `~/actions-runner`, `~/.octorunner/runners/*`, and `~/Library/Application Support/io.octorunner.macos/runners/*`.
- For external runners, first select the directory through **Import Folder…**. Process metadata alone grants no folder access.
- For embedded logs from external runners, first select **Refresh** or **Full Console**. The automatic access policy rejects external paths before any file system resolution.
- Automatic discovery stays within the allowed paths when following symlinks. Diagnostics skip symlinked `_diag` directories and log files.

Only the specific user action can trigger a macOS permission prompt when access is required. macOS continues to enforce the permissions it has already granted.

## Minimum GitHub permissions

The `workflow` OAuth scope allows changes to workflow files. The app stopped requesting it because runner management and job history only require the permissions listed below. Reauthorize to lower the permissions on an existing grant.

| Task | OAuth or classic PAT | Fine-grained PAT |
| --- | --- | --- |
| Register private repository runners or update their labels | `repo` and administrator access to the target repository | Administration write access for selected repositories only |
| Register organization runners or update their labels | `admin:org`, plus `repo` for private repositories where needed | Self-hosted runners write access for the target organization |
| Read workflow and job history in a future release | `repo` for private repositories | Actions read access for the target repositories |

The OAuth flow requests `repo` and `admin:org` to support repository and organization runners. A fine-grained PAT issued for selected repositories can grant narrower access. A separate OAuth step for optional organization permissions could be added in the Settings milestone. When a fine-grained PAT response omits `X-OAuth-Scopes`, the app treats its permissions as unknown. The target API checks the actual permissions when the app makes a request.

[Runner endpoints](https://docs.github.com/en/rest/actions/self-hosted-runners), [OAuth scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps), [fine-grained token permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).

## Test coverage and limits

The baseline included 29 Swift tests and 6 Python tests. The patch adds runnable workflow regression tests, HTTP request and authentication fixtures, folder and symlink boundary tests, and a test for the Quit dialog. It retains NSHostingView rendering and contrast tests. Interaction and VoiceOver conformance require separate verification.

The following measurements used `swift test --package-path Packages/OctoRunnerKit --no-parallel --enable-code-coverage` before the final log symlink tests.

| Module | Lines executed |
| --- | ---: |
| AppShellFeature | 68.0% |
| CoreModels | 72.3% |
| DesignSystem | 100.0% |
| GitHubAPI | 27.0% |
| RunnerEngine | 25.1% |
| SecurityKit | 89.2% |
| SyncKit | 61.7% |
| TelemetryKit | 97.1% |

SwiftUI generics increase the number of instrumented lines. OAuth polling and cancellation, API error responses and pagination, provisioning rollback, crash supervision, and actual update rollback need more behavioral tests in v0.5–v0.7. Full hardware telemetry still needs verification. The implementation at this point estimates memory usage.

During manual acceptance, the user confirmed that selecting **Dashboard** five times in the menu bar popover opened exactly one window, closing and reopening worked, the Quit dialog and quitting worked, a normal restart showed no Documents prompt, and the three preview toggles were disabled. A new external folder import and the continued operation of specific LaunchAgent runners still needed separate live checks. The computer control tool returned `cgWindowNotFound`, so the UI results came directly from the user. Testing proceeded without resetting TCC or changing privacy permissions.

## Upcoming milestones

The patch left these milestones open.

- **v0.5.0** delivers six functional Settings tabs, jobs and queue views, real host telemetry, and an audit interface.
- **v0.6.0** delivers full supervision, safe import migration, periodic synchronization, and visible conflicts.
- **v0.7.0** delivers German and English localization, accessibility, end-to-end update and rollback testing, documentation, and screenshots.

A v1.0.0 release after v0.7.0 requires explicit approval.
