# Remaining Work Through v0.7

Status as of November 20, 2026. v0.6.0 has shipped. Earlier detail plans record the state at their respective milestones.

## Agreed Scope

On November 19, 2026, the user moved the global runner concurrency limit to v0.6, removing it from the v0.5 release gate. The saved setting is informational until the runner engine enforces it.

| Order | Deliverable | Plan and Dependencies |
|---|---|---|
| 0 | Fix reproduced hangs and capture diagnostics | PRs #27–29 merged, with CI passing on main. [CI test diagnostics](./superpowers/plans/2026-11-14-ci-test-diagnostics.md) |
| 1 | Complete v0.5 acceptance, add GitHub details, and publish a signed release | [v0.5 completion](./superpowers/plans/2026-11-19-v05-acceptance-and-release.md) |
| 2 | Process ownership, start, stop, restart, policies, concurrency, and live logs | Requires step 1. [v0.6 engine](./superpowers/plans/2026-11-19-v06-supervision-and-concurrency.md) |
| 3 | Safe migration and recovery after failure | Requires step 2. [v0.6 migration](./superpowers/plans/2026-11-19-v06-runner-migration.md) |
| 4 | Periodic reconciliation, conflicts, groups, multiple repositories, and v0.6 release | Requires steps 2 and 3. [v0.6 sync](./superpowers/plans/2026-11-19-v06-runner-reconciliation.md) |
| 5 | Full German and English and accessibility acceptance, update rollback, documentation, and v0.7 release | Requires step 4. [v0.7 completion](./superpowers/plans/2026-11-19-v07-polish-and-release.md) |

## Verified Progress

- **v0.6.0** has shipped. The release workflow completed signing, notarization, GitHub Release publication, and the Homebrew tap update. On the test Mac, the upgrade from v0.5.2 to v0.6.0, stapled ticket, Gatekeeper approval, and app launch were verified. Interactive migration acceptance with a test runner remained open. [Release](https://github.com/loesch-digital/octorunner/releases/tag/v0.6.0) · [Release CI](https://github.com/loesch-digital/octorunner/actions/runs/44723287728)
- v0.6 includes process supervision, a concurrency limit for directly managed runners, local live logs, migration, and periodic GitHub reconciliation. The UI supports runner groups, multiple repositories, and per-target read access checks. [v0.6.0 release notes](./releases/v0.6.0.md)
- v0.5 delivered six Settings pages, configurable native macOS notifications, a menu bar logo with runner health, blue Running status, a separate last job result, job history with filters and metrics, cache and storage analysis with safe cleanup, an audit dialog with a runner dropdown, and host telemetry with a process inspector, memory pressure, and thermal state.
- v0.6 passed **493 Swift tests in 87 suites**, **35 Python tests**, and a native Xcode build. PR CI reported **76.3%** line coverage for the Swift package. Coverage for the provisioner was **109 of 578** lines. Registration and migration with real GitHub responses remain part of hands-on acceptance. [Coverage artifact](https://github.com/loesch-digital/octorunner/actions/runs/44716639590) · [Final main CI](https://github.com/loesch-digital/octorunner/actions/runs/44721755971)
- PR #25 delivered the process inspector and PR #26 delivered memory pressure and thermal state. The subsequent CI run on main stalled during tests. Buffered output left the identity of the stalled test unconfirmed. PR CI run 44462124714 reproduced the stall on November 19. A full local run with three repetitions also stalled. The first stack sample captured the waiting SwiftPM parent, so diagnostics expanded to its private test session. The test helper sample from the local stall showed a synchronous `Process.waitUntilExit()` during HTTP test server cleanup at `GitHubActionsTransportTests.swift:19`. Confirmation that this caused the original CI stall still requires a stack sample from that CI helper. [PR #25](https://github.com/loesch-digital/octorunner/pull/25) · [PR #26](https://github.com/loesch-digital/octorunner/pull/26)
- PR #27 added test time limits and stack artifacts. PR CI 44463655972 and main CI 44464836288 passed. The process lifecycle fix merged in PR #28 after 286 tests each passed three repetitions and PR CI passed. Main CI 44467709824 passed the Swift suite and exposed a separate failure during the first native UI launch. The app switched to accessory activation policy before opening its first window. PR #29 added a failing state regression test and fixed the startup policy. PR CI 44469664743 and main CI 44470817545 passed, including native UI tests. The local suite at that point included 287 tests. The user confirmed that the intermittent hangs occurred in GitHub test runs. [PR #27](https://github.com/loesch-digital/octorunner/pull/27) · [PR CI 44463655972](https://github.com/loesch-digital/octorunner/actions/runs/44463655972) · [Main CI 44464836288](https://github.com/loesch-digital/octorunner/actions/runs/44464836288) · [PR #29](https://github.com/loesch-digital/octorunner/pull/29) · [Main CI 44470817545](https://github.com/loesch-digital/octorunner/actions/runs/44470817545)
- The v0.7 runner error notification setting merged in PR #45, and CI passed on main. Update recovery is in progress. v0.7.0 has yet to be released. [PR #45](https://github.com/loesch-digital/octorunner/pull/45) · [Main CI](https://github.com/loesch-digital/octorunner/actions/runs/44728201484)

## Jobs Scope Added November 19, 2026

Since v0.5, workflow details show associated pull requests, expandable jobs and steps, and on-demand job logs. The app shows live step status, available GitHub job log snapshots, and local live logs in separate views. [Implementation plan](./superpowers/plans/2026-11-19-workflow-github-details.md) · [v0.5 release notes](./releases/v0.5.0.md)

## Scope Boundaries

- Crash and quarantine notifications require process supervision. Runtime controls should appear when they can take effect.
- Jobs metrics reflect the loaded history.
- Telemetry reports available measurements and verified process associations. Separate performance and efficiency core utilization requires a verified mapping.
- Personal multi-repository setup creates separate registrations. Prefixes name runners, labels route jobs, and organization runner groups control access.
- Installed LaunchAgents can continue after the GUI quits. Central monitoring runs in the GUI. A separate background agent remains optional and would require an architecture decision if it changed the existing design contract.
- Migration leaves private runner keys at the source, as specified in docs/08. It must account for registration and any server-side compensating actions.

## v0.5 Acceptance Matrix Before PR Approval

The matrix records local checks for the specified scenarios. PR CI, main CI, and release verification remain separate gates.

| Area | Evidence Under `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests` | Remaining Verification or Scope |
|---|---|---|
| Settings persistence and safe defaults | `AppPreferencesTests.swift` | Confirm the effect of each setting. Global concurrency is part of v0.6. |
| Login, Dock, and language without startup prompts | `AppIntegrationTests.swift`, `SettingsTests.swift` | Verify actual SMAppService states and macOS approval interactively. |
| Versions and updates in Settings | `SettingsUpdateTests.swift` covers manual checks, errors, cancellation, duplicate calls, German and English search, and rendering with 100 runners. | The reused release checker runs on demand without scanning folders. Debug version display remains unchanged. Native navigation is tested separately in CI. |
| Shell, PATH, and restart for new LaunchAgents | `RunnerLaunchConfigurationTests.swift` | Applies to newly configured services. |
| Native notifications and event filters | `AppNotificationTests.swift`, `LocalJobFailureMonitorTests.swift` | Verify actual banners after opting in. Crash triggers are part of v0.6. |
| Cache, retention, and pruning | `WorkspaceCleanerTests.swift`, `StorageMaintenanceTests.swift` | Cleanup is limited to safe managed paths, as described in docs/15. |
| Jobs, queue, metrics, and account isolation | `WorkflowHistoryLoadingTests.swift`, `WorkflowHistoryMetricsTests.swift` | Show the loaded window and age of observations. Logs open via explicit GitHub links. Local live logs follow the engine plan. |
| Audit filters, runner selection, and export | `AuditLogDialogTests.swift`, `RunnerFilterRegressionTests.swift` | Engine start, stop, and crash events follow the corresponding v0.6 features. |
| Telemetry and API budget | `HostTelemetryDashboardTests.swift`, `HostDiskIOMonitorTests.swift`, `TelemetryKitTests.swift` | Report measured or unavailable values. Ping and an IPC watchdog are outside scope. |
| Process details and confirmed SIGTERM | `RunnerProcessInspectorTests.swift`, `RunnerProcessInspectorUITests.swift` | Recheck process identity. The remaining POSIX race is documented. |
| Empty filter states and window resizing | `RunnerFilterRegressionTests.swift`, `ResponsiveLayoutTests.swift`, NSHostingView tests | The user approved Settings readability and resizing. Recheck after later changes. |
| Cancellation during API and view work | `WorkflowHistoryLoadingTests.swift` and process and storage tests | Account changes and late responses have explicit safeguards. Add targeted checks for gaps during final acceptance. |

The user deferred changes to the development build's displayed version. The release versioning process runs separately.

## Known Test Coverage Gaps

The locally verified SPM LLVM report includes **13,239 of 16,985 instrumented source lines (77.9%)**. It covers instrumented package code. Native UI runs and operating system dialogs require their own behavior checks.

- `RunnerProvisionerActor.swift` reached 30.7%. The migration plan calls for targeted tests at each failure stage and for compensating actions.
- `GitHubRunnerProvisioningAPI.swift` reached 5.0%. The v0.6 registration and sync scope calls for transport, decoding, and permission tests using a stub transport.
- `GitHubRunnerSyncActor.swift` reached 8.5%. The sync plan covers typed errors, cancellation, pagination, and account isolation.
- `AppUpdaterActor.swift` reached 24.8%. The v0.7 plan covers failure and rollback paths.
- Some SwiftUI wrappers show 0% in the SPM report even though their contents render in separate tests. Verify actual navigation and task wiring with native UI tests and targeted lifecycle tests.
- The trivial assertion `isEnabled == true || isEnabled == false` was removed. `AppIntegrationTests` covers actual login registration, errors, pending macOS approval, and stale status replies.

## CI Review Follow-Up

Commit `d39cb3b` unregisters closed stdout from the watchdog selector. The failing profiling test had counted 370,433 loop iterations in 0.8 seconds. Regressions verify bounded waiting, preserved exit status, and enforcement of idle and total deadlines. The fix addresses the observed busy loop.

## Acceptance and Versioning Rules

For each code change, start with a failing test, implement the minimum change, verify it passes, then go through review, PR CI, merge, and main CI. Each release also requires signing, notarization, stapling, GitHub Release publication, the Homebrew tap update, and local Homebrew and Gatekeeper checks. Xcode and the signed ZIP provide acceptance paths without Homebrew. [Development acceptance](./10-development-and-acceptance.md)

Use the screenshots under `docs/assets/screens` as a functional reference for each dialog. Preserve the readable native navigation and responsive layouts. Group manual acceptance into at most three related checks.

**Stop after v0.7.0. Ask the user for explicit approval before starting v1.0.0.**

## Feature Comparison With Screenshots 07–09

The user approved the native Settings pages. The screenshots document intended functions. The app adapts its layout and system integration for macOS.

| Reference | Outcome and Evidence |
|---|---|
| 07 General, including appearance, language, versions, and updates | Implemented in `GeneralSettingsTab` and `SettingsUpdateCard`. Covered by preference, integration, and update tests. macOS login approval requires interactive testing. |
| 07 Launch at Login and Background, and 07d Failover | Uses `SMAppService.mainApp`, shell and PATH configuration, and KeepAlive for new LaunchAgents. Existing services require an explicit change. Process supervision, quarantine, and global concurrency are part of v0.6. |
| 07c Auth and the additional Cache & Storage page | Implements verified managed paths, cleanup preview and confirmation, retention, Keychain, and actual permission metadata as described in docs/15 and docs/13. Global host caches, token lifetime estimates, and Touch ID are outside this scope. |
| 07e Notifications | Native macOS notifications with opt-in and event filters. System Settings control banners and sounds. Crash events require the runner engine. Covered by `AppNotificationTests` and event monitor tests. |
| 08 Jobs and queue | Implements account isolation, filters, saved history, the current queue, and metrics for the loaded window as described in docs/12. GitHub logs open on demand. Local streaming is part of v0.6. |
| 09 Host Telemetry | Shows CPU, RAM, I/O, API budget, memory pressure, and thermal state as described in docs/17. CPU topology shows performance and efficiency core counts. I/O reflects host devices. |
| 09 Process inspector and related audit features | The inspector shows CPU, RAM, and uptime, checks process identity, and requires confirmation before SIGTERM. Audit filters, runner selection, and export follow docs/16. Full engine lifecycle events and local live logs are part of v0.6. |

### Differences From the Original Settings Mockup

- **Service PID and uptime, reload, plist preview, and syntax validation (07)** were open for the LaunchAgent operations view and tracked in task 1 of the v0.6 engine plan. The existing telemetry process uptime serves the process inspector.
- **Organization and workpool permissions table and manual permission sync (07c)** were tracked in task 3 of the v0.6 sync plan. At this point the Auth page displayed account and scope metadata. The plan called for group support and explicit reconciliation, with missing permissions reported as errors.
- **Graceful drain and timeout (07d)** were open in tasks 1 and 3 of the v0.6 engine plan. The existing restart preferences applied to restarting.
- **Standby host (07d, Phase 2 Preview)** is a separate Phase 2 proposal outside the agreed v0.5–v0.7 scope. Automated host failover requires a separate design and approval. Local automatic restart covers local processes.

### Five Review Scenarios

1. Settings take effect as documented. Evidence includes `AppIntegrationTests.loginFailure/loginApproval/loginSuccess/dockStartupActivation`, `RunnerLaunchConfigurationTests`, and storage and notification tests. Controls that require the engine wait for their implementation.
2. Account changes discard late responses before persistence. Covered by `WorkflowHistoryLoadingTests.accountSwitch/invalidatedResponse/globalRefreshCancellation`.
3. Empty filter states distinguish no registered runners, no filter matches, and no search results, including historical runners. Covered by `RunnerFilterRegressionTests.emptyStates/runnerChoices`.
4. Closing a window prevents late results and model access. Covered by `RunnerProcessInspectorTests.cancellation`, history cancellation tests, and `SettingsUpdateTests.cancelledCheck`. Periodic telemetry checks for cancellation after every await.
5. `SettingsUpdateTests.failedCheck/cancellationError` distinguish errors from successful release checks. Installation rollback belongs to v0.7. At this review point, the signed release, Homebrew, and Gatekeeper checks were still pending.

### Local Verification on November 19, 2026

**293 Swift tests in 62 suites** passed, including new Settings tests and existing regressions. All **33 Python tests** passed with the access needed for process diagnostics and compiler caches. An earlier sandbox-restricted run was excluded from the pass and product failure counts. The native Debug Xcode build succeeded. New Settings cards were rendered and visually checked in German and English, Light and Dark, at 620 and 960 points. Local native XCTest interaction was blocked by uninitialized macOS automation. The native run remained a PR and main CI gate. The user had previously accepted Settings readability, resizing, single-window behavior, and startup without a Documents prompt.

## Additional v0.5 Gate for GitHub Details

PR #30 and main CI 44511598034 passed. The follow-up branch added validated PR links, jobs and steps per known run attempt, and on-demand job log snapshots. Screenshot 08 served as a functional reference. The scope covered read-only GitHub operations and excluded webhooks, REST live streaming, reruns, and cancellation. [Main CI](https://github.com/loesch-digital/octorunner/actions/runs/44511598034)

An independent review led to regression tests and fixes for six items. These were complete history pagination, separate GitHub and download budgets, explicit attempt validation, refresh for queued workflows without jobs, shared status colors, and the actual accessibility text of the native log view. Locally, **330 Swift tests in 67 suites**, **33 Python tests**, and the native Xcode 27.2 and Swift 6.4.2 build passed. PR CI, main CI, and release verification remained separate gates.

The German and English log and detail views were rendered in narrow and wide layouts, in Light and Dark. Native authenticated detail and log interactions still required a short hands-on check. CI checks Jobs navigation without private GitHub fixtures. One remaining optimization was to avoid repeating the bounded commit lookup on a completed PR run when GitHub metadata remained empty.
