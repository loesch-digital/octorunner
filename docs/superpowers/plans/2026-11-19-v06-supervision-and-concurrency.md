# v0.6 Process Supervision and Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use the existing authorization to continue with native implementation.

**Goal** — Provide working start, stop, and restart controls, crash policies, live logs, and an enforceable limit for runners managed by OctoRunner.

**Architecture** — A supervisor actor owns the lifecycle of directly managed processes. Keep launchd mode under its own ownership and ensure each listener has exactly one owner. GitHub owns job assignment.

**Tech stack** — Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement, and the existing Python and GitHub Actions tools.

**Spec** — ADR-01 and ADR-03 in `docs/01-architecture-and-modules.md`, `docs/05-step-03-runner-wizard-and-engine.md`, `docs/06-step-04-dashboard-detail-and-menubar.md`, and the user-approved v0.6 scope. The November 19, 2026 scope decision places the global concurrency limit in v0.6.

## Global Constraints

Source paths such as `RunnerEngine/...` and `CoreModels/...` are relative to `Packages/OctoRunnerKit/Sources/`. Test filenames are relative to `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests/`. Create new files in the corresponding directories.

- Target macOS 15+ with Swift 6 strict concurrency, SwiftUI, and SwiftData. Preserve the minimum supported version when selecting the CI image.
- Read the four repo skills and relevant `references/*.md` files before making changes. Follow `AGENTS.md`.
- Start every production change with a regression test that demonstrably fails, then make it pass and refactor. Run Swift tests with `swift test --package-path Packages/OctoRunnerKit --no-parallel` and Python tests with `python3 -m unittest discover -s scripts/tests`.
- Use a feature branch, semantic commits, and a PR. After pushing, wait for all PR CI checks to pass before merging, then wait for all main CI checks to pass before starting the next feature.
- Keep secrets out of logs, models, and exports. Access Documents only when needed. Preserve SwiftData defaults, SQLite header checks, and cancellation checks before model access.
- Give new controls labels and hints, keyboard support, and OctoTheme styling. Meet WCAG 2.2 AA in Light and Dark appearances. Use NSHostingView to check narrow and wide layouts in German and English.
- Verify exact tool and API versions against official sources immediately before changing them.

## Review Focus

1. Concurrent start and stop calls and delayed exit callbacks must target only the intended process (Task 1).
2. Quarantine repeated crashes before a runner enters an endless restart loop (Task 2).
3. Preserve active jobs when lowering the limit (Task 3).
4. Bound memory during file rotation and when log consumers fall behind (Task 4).
5. Show which processes continue after GUI shutdown and whether a supervisor is active (Tasks 1 and 3).

### Task 1: Process Ownership and Control

**Files** — Modify `Packages/OctoRunnerKit/Sources/RunnerEngine/RunnerSupervisorActor.swift` and ADR-01. Create `RunnerProcessControlling.swift` and `ManagedRunnerProcess.swift` in the same source directory. Test in `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests/RunnerSupervisorTests.swift`.

**Interfaces** — Pass new Sendable snapshots across actor boundaries. The supervisor exposes `start(runnerID: UUID) async throws`, `stop(runnerID: UUID) async throws`, and `restart(runnerID: UUID) async throws`. The process adapter identifies exit events by launch generation.

- [x] Documented the ownership matrix for direct child processes, existing LaunchAgents, and imported external listeners. Direct mode takes ownership of external listeners only after a verified migration.
- [x] Used fake processes to test duplicate starts, late exits from earlier generations, canceled startup, and unrelated processes.
- [x] Tested graceful drain, deadlines, and separately confirmed force stops. The quit dialog explains which runners keep running. Recheck local job state before a voluntary stop or quit.
- [x] Implemented the direct process adapter without blocking on `waitUntilExit`. The exit remains associated with the launch generation and is reported only after its process group has ended. Native tests use short-lived test processes.
- [x] Connected app controls for direct runners with confirmed PID, uptime, status, and audit entries. Storage cleanup and startup share a directory lock.
- [x] Verified all PR and main CI checks passed for direct process supervision.
- [x] Added the LaunchAgent diagnostics from screenshot 07 to Settings and runner details. Show the installed plist with its syntax validation result and allow reloading a verified OctoRunner service that is unloaded. A loaded service can keep running. Tests cover missing, unrelated, and replaced definitions.

### Task 2: Restart, Throttling, and Quarantine

**Files** — Create `RunnerEngine/RunnerRestartScheduler.swift`. Modify `CoreModels/RunnerRuntimePolicy.swift`, `RunnerEngine/RunnerSupervisorActor.swift`, and `AppShellFeature/Settings/FailoverSettingsTab.swift`. Test in `RunnerRestartPolicyTests.swift`.

**Interfaces** — The scheduler uses the exit code, generation, RunnerRuntimePolicy, and an injected monotonic clock. Unit tests use the injected clock to advance time. The scheduler returns a restart time or quarantine, and a separate command releases quarantine.

- [x] Tested Always, On Non-Zero, and Manual policies, voluntary stops, delays, and the exact quarantine threshold. Reset the failure count after 60 seconds of runtime. Rapid successful exits also count under Always.
- [x] Connected Battery Saver to `ProcessInfo.isLowPowerModeEnabled`. New starts wait for Low Power Mode to end. Running jobs can continue, and users can cancel deferred starts.
- [x] Applied policies to directly managed runners. Crashes and quarantine create audit events and use the existing optional macOS runner error notification.
- [x] Show quarantine and deferred starts in runner details with the latest workflow result displayed separately.
- [x] Waited for all PR and main CI checks to pass for recovery. [PR #36](https://github.com/loesch-digital/octorunner/pull/36) · [Main CI](https://github.com/loesch-digital/octorunner/actions/runs/44623341585)

### Task 3: Global Concurrency Limit

**Files** — Create `RunnerEngine/RunnerAdmissionController.swift`. Modify `CoreModels/AppPreferencesStore.swift`, `RunnerEngine/RunnerSupervisorActor.swift`, and the relevant Settings page. Test in `RunnerAdmissionTests.swift`.

**Interfaces** — `RunnerAdmissionController` tracks reserved and active slots by stable runner ID. Starting requires a valid reservation. Serve waiting managed runners in FIFO order and hold slots for active jobs until they can finish safely.

- [x] Tested starts and slot releases with two isolated process fixtures. The GitHub reference below describes shutdown risks for persistent runners and recommends ephemeral runners for autoscaling.
- [x] Documented the limits in [Settings, Telemetry, and Jobs](../../07-step-05-settings-telemetry-and-jobs.md). The limit applies to directly managed runners. GitHub assigns workflows.
- [x] Added regression tests for concurrent and failed starts, raising and lowering the limit, cancellation by generation, and reservations after Low Power Mode.
- [x] Connected the stored value to the supervisor and failover policy. Show the limit and waiting status in the UI.
- [x] Waited for all PR and main CI checks to pass for the concurrency limit. [PR #37](https://github.com/loesch-digital/octorunner/pull/37) · [Main CI](https://github.com/loesch-digital/octorunner/actions/runs/44629969576)

### Task 4: Live Logs and Dialog 05

**Files** — Modify `RunnerEngine/RunnerLogStreamerActor.swift` and `AppShellFeature/RunnerConsoleLogSheet.swift`. Create `RunnerLogStreamingTests.swift`.

**Interfaces** — Bound the AsyncStream of log lines. Direct mode reads pipes and headless mode observes file events. Reuse the existing log level and timestamp models.

- [x] Compared behavior with screenshot 05. Covered regressions for split UTF-8 characters, stdout and stderr, bounded buffers, rotation and truncation, and file descriptor cleanup.
- [x] Replaced one-time file excerpts with live sources. Added search, severity filters, automatic scrolling, pause, copy, and export. Redact detected credentials before buffering data for export.
- [x] Verified narrow and wide layouts with NSHostingView. Fixed review findings on file rotation, export context, and descriptor cleanup with regression tests.
- [x] Waited for all PR and main CI checks to pass for live logs. Migration and sync follow before the v0.6 tag. [PR #38](https://github.com/loesch-digital/octorunner/pull/38) · [Main CI](https://github.com/loesch-digital/octorunner/actions/runs/44635943478)

GitHub documents its recommendations for ephemeral runners and shutdown limits for persistent runners. The optional background agent has a separate ADR. [GitHub self-hosted runner reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
