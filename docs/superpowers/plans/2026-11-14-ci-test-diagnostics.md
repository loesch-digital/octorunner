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
- [ ] PR/main CI for lifecycle fix. This does not by itself prove every application hang resolved.
