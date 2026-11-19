# CI Test Diagnostics Implementation Plan

> Use superpowers:executing-plans inline with TDD and fresh final review.

**Goal:** Bound the observed CI test hang and retain evidence for its actual cause.
**Spec:** docs/release-signing.md diagnostic limits; user requires log-based investigation, green CI gates and pipeline optimization.
**Architecture:** Python standard-library subprocess wrapper streams test output, tracks monotonic deadlines, samples only its new private process group, fails honestly on timeouts and preserves logs as artifacts. No retries, test skipping, app changes or existing process signals.
**Constraints:** Keep existing toolchain, Actions versions, branch triggers and job limits unchanged. No process arguments/environment dumps in diagnostics; no secrets. Unknown underlying hang remains documented.
**Review focus:** Preserve child error status; output progress resets idle limit; silence during compilation uses total limit; cleanup includes descendants but excludes unrelated processes; sample failures cannot mask timeout; outer cancellation cleans up child group.

### Task 1: Diagnostic test launcher
- [x] Add failing subprocess regressions for command status/output, silent test sampling, pre-test total deadline, quiet compilation, live progress and unrelated process isolation. Original missing-script red log: /tmp/octorunner-watchdog-red.log.
- [x] Add scripts/run-swift-tests.py with 120s test-idle / 600s total deadline, bounded private-group sampling/termination, live output and persistent transcript.
- [x] Use launcher in ci.yml/release.yml, preserve diagnostics artifact and document observed hang without claiming its root cause fixed.
- [x] Full Python/Swift launcher integration, native sampling check, fresh review; PR #27 merged; PR CI 44463655972 and main CI 44464836288 green.

### Task 2: Include SwiftPM child groups in the private session
- [x] Reproduce missing helper sampling with a private child using `process_group=0`; RED `/tmp/octorunner-watchdog-session-red.log`.
- [x] Enumerate only members of the new POSIX session, recheck SID/PGID before signals, and sample Swift testing helpers first. A fixture leaving via setsid remains excluded.
- [x] Full Python suite GREEN 29 tests in `/tmp/octorunner-watchdog-session-green.log`.
- [x] Fresh review of changed ownership boundary and regression fixes; 31 Python / 282 Swift tests green; PR/main CI green. Local repeated suite then captured actual helper stack (see Task 3).


### Task 3: Fix the reproduced test-server lifecycle stall
- [x] Reproduce full suite with `--maximum-repetitions 3 --repeat-until fail`; watchdog exit 124; `/tmp/octorunner-full-repeat-diagnostics/sample-59011.txt` shows `Process.waitUntilExit()` at `GitHubActionsTransportTests.swift:19`.
- [x] Add initially red lifecycle regression tests (`/tmp/octorunner-server-lifecycle-red.log`) and an async owned server fixture; preserve real redirect/cache integration coverage.
- [x] Verify fast exit, startup failure, body failure and actual cancellation, including PID-exit assertions. Removing the exit wait fails both cleanup tests (`/tmp/octorunner-server-mutation-red.log`). Fresh review findings corrected; final full suite: 286 tests, three repetitions each, 33.583s (`/tmp/octorunner-server-reviewed-green.log`).
- [x] Lifecycle fix merged as PR #28; PR CI 44466663572 green (8m50). Main CI 44467709824 passes Swift tests but exposes a separate cold-launch UI activation failure; see Task 4. User clarified that the reported hangs concern GitHub test runs.


### Task 4: Preserve foreground activation during first window presentation
- [x] Inspect main CI 44467709824 failed logs and downloaded xcresult. First AuditLog UI launch stays Running Background; following telemetry/settings tests pass. Session log records accessory activation while XCTest waits for foreground.
- [x] Reproduce the premature Dock demotion in `AppIntegrationTests.dockStartupActivation`: three false/no-window startup updates fail the `.regular` expectation (`/tmp/octorunner-dock-startup-behavior-red.log`).
- [x] Keep regular policy until the first visible window; retain existing close/reopen/menu visibility rules afterward. Full Swift suite GREEN 287 tests (`/tmp/octorunner-dock-startup-green.log`); fresh review has no findings.
- [x] PR #29 merged; PR CI 44469664743 and main CI 44470817545 fully green, including actual native UI tests. Local native test could not initialize macOS automation mode and is not counted as passed (`/tmp/octorunner-dock-activation-ui.log`); no permission bypass, skips or failure retries.
