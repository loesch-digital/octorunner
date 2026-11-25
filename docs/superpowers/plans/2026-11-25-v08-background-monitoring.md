# OctoRunner v0.8 Background Monitoring Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans and complete each task with the project's red, green, and refactor sequence.

**Goal:** Keep monitoring registered runners and delivering opted-in alerts after the GUI quits.

**Architecture:** A signed per-user LaunchAgent and the GUI share the monitoring algorithms and coordinate exclusive ownership. The GUI exports configuration and remains the SwiftData owner. The helper keeps independently recoverable observations and status.

**Tech stack:** Swift 6 Strict Concurrency, macOS 15+, Service Management, authenticated XPC as needed, Security, UserNotifications, and XcodeGen.

**Spec:** [v0.8 Background Monitoring](../specs/2026-11-25-v08-background-monitoring.md).

## 1. Verify the signed macOS integration

- [ ] Build a disposable signed helper in a separate bundle identity. Verify registration, approval, launch after GUI exit, system stop, and re-enable using `SMAppService`. Capture evidence for the macOS 27 Dock text and stop action.
- [ ] On macOS 15 and 27, verify background notification authorization and delivery under the intended application identity. Verify the intended shared Keychain entitlement in the notarized Developer ID distribution setup. Use disposable credentials, fail closed on unsigned or mismatched peers, and unregister the disposable helper.
- [ ] Record the results and final helper packaging decision. If the native Dock status or authenticated background access cannot be reproduced, bring the result back for review before changing production behavior.

## 2. Share monitoring inputs and coordinate ownership

Files: `Packages/OctoRunnerKit/Package.swift`, a new `BackgroundMonitoringKit` target, and new `BackgroundMonitoringRuntimeTests.swift` in `OctoRunnerKitTests`. Reuse existing process samplers, GitHub clients, state transition policies, and job result matching.

- [ ] Test decoding and replacement of versioned configurations, refusal of incompatible and corrupt snapshots, and absence of credential fields. Use registered runner IDs and process metadata only. Extend persistence tests to assert that exporting configuration leaves the original SwiftData schema and values intact.
- [ ] Test lock acquisition across two real test processes, idempotent release, failed takeover while the original owner remains alive, and automatic release when it exits. Test task cancellation and stale observations across ownership changes.
- [ ] Define `MonitoringConfiguration`, `MonitoringObservation`, and `MonitoringLease` in the new target. Use value types for actor boundaries, one SwiftData-to-snapshot adapter in the GUI, atomic writes in a user-private directory, and a non-inheritable lock descriptor. Keep the existing monitor-specific rules in their current modules when they can be shared without duplicating behavior.
- [ ] Run the full Swift suite and commit this checkpoint.

## 3. Package the service and connect its observers

Files: a new `BackgroundAgent/` target, `project.yml`, `AppServices.swift`, `RunnerHealthMonitor.swift`, `RunnerRemoteSyncMonitor.swift`, `LocalJobFailureMonitor.swift`, and `AppNotificationsController.swift`. Changes to `SecurityKit` follow the verified distribution design from task 1.

- [ ] Test absent, approved, revoked, incompatible, and crash-restarted agent states. Verify exclusive monitoring, same-account configuration changes, unavailable credential behavior, and no duplicate alert across helper restart and GUI handoff. Verify authentication rejects an unrelated signed client and test the same case in the signed installation.
- [ ] Package the helper and register it only for explicit opt-in. Share observation logic with the foreground implementation. Read GitHub credentials from the verified shared Keychain, preserve configured notification categories, and bind the observations and status to the current configuration revision. Keep GitHub mutations and direct runner supervision in the GUI.
- [ ] Test that missing or denied protected-folder access never prompts or interferes with pure process monitoring. Verify read-only behavior against a running LaunchAgent fixture.
- [ ] Run Swift and packaging tests, inspect the signed nested helper, and commit.

## 4. Add the settings, quit, and update integration

Files: `Settings/BackgroundSettingsTab.swift`, `AppPreferencesStore.swift`, `AppIntegrationController.swift`, `AppQuitConfirmation.swift`, `App/OctoRunnerApp.swift`, update handoff code, and `Localizable.xcstrings`.

- [ ] Test opt-in defaults, approval feedback, switching off while monitoring, system revocation, failure on quit, unchanged window-close behavior, and independent login-item settings. Extend the native settings navigation test with the new control and background status. Check both translations, VoiceOver labels, and light and dark contrast.
- [ ] Test helper quiescence before update handoff and safe restoration after a verified upgrade or rollback. Test failed quiescence with a stuck helper and verify the update does not replace the bundle then.
- [ ] Wire settings to actual service status and health. Keep the GUI shutdown and updater contract intact. Display the native status using the macOS integration verified in task 1 and settings status on older systems.
- [ ] Run the full Swift and Python suites and commit.

## 5. Signed acceptance and release

- [ ] Document operation, permissions, managed runner behavior, and the change to the GUI-only monitoring architecture in `docs/01-architecture-and-modules.md` and `docs/user-guide.md`. Add English release notes.
- [ ] Run the spec's signed macOS 27 and macOS 15 acceptance matrix, including disconnect, logout/login, quit, system stop, update failure recovery, and no protected-folder prompt. Confirm that on shutdown, the runner used for validation completes an active job according to its existing policy.
- [ ] Wait for PR CI, then for main CI after merge. Verify notarization, the published ZIP, Homebrew installation, Gatekeeper, and helper registration on the release build before completing v0.8.
