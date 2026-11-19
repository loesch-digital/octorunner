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
- [ ] Full Python/Swift launcher integration, native sampling check, fresh review; commit/PR CI, merge/main CI.

### Task 2: Include SwiftPM child groups in the private session
- [x] Reproduce missing helper sampling with a private child using `process_group=0`; RED `/tmp/octorunner-watchdog-session-red.log`.
- [x] Enumerate only members of the new POSIX session, recheck SID/PGID before signals, and sample Swift testing helpers first. A fixture leaving via setsid remains excluded.
- [x] Full Python suite GREEN 29 tests in `/tmp/octorunner-watchdog-session-green.log`.
- [ ] Fresh review of the changed ownership boundary, local Swift integration, PR CI with actual helper stack capture if the stall recurs; investigate cause before merge/main-CI.
