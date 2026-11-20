# v0.5 Acceptance and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use the existing authorization to continue with native implementation.

**Goal** — Complete acceptance testing for the existing v0.5 features before publishing the signed v0.5.0 release.

**Architecture** — Use the existing modules. Verify that settings take effect and that evidence supports each feature. Process supervision and global concurrency belong to v0.6.

**Tech stack** — Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement, and the existing Python and GitHub Actions tools.

**Spec** — `docs/07-step-05-settings-telemetry-and-jobs.md`, `docs/release-signing.md`, and `docs/18-remaining-delivery-plan.md`, which links to detailed designs 11–17. The November 19, 2026 scope decision places the global concurrency limit in v0.6.

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

1. For each persisted setting, use tests to show its effect or document any limitation (Task 1).
2. Discard API responses for the previous account after an account switch (Task 1).
3. Show a filter-specific empty state when runners exist but none match (Task 1).
4. Stop model access when the window closes during a measurement (Task 1).
5. Verify Gatekeeper and Homebrew before calling installation or update successful (Task 2).

### Task 1: Acceptance Matrix and Targeted Fixes

**Files** — `docs/18-remaining-delivery-plan.md`, `docs/07-step-05-settings-telemetry-and-jobs.md`, `docs/17-host-telemetry.md`, and the existing `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests/{SettingsTests,AppPreferencesTests,WorkflowHistoryLoadingTests,RunnerFilterRegressionTests,HostTelemetryDashboardTests,AuditLogDialogTests}.swift`.

**Interfaces** — Use the existing Settings scene and AppPreferencesStore, job history, AuditLogEntity, and TelemetryKit. Use the current engine interface.

- [ ] Before acceptance, fix the watchdog EOF issue from the work index as a separate red-to-green bug fix. Closing stdout while the child is alive must leave the watchdog waiting without spinning. Preserve deadline, exit code, and cleanup behavior.
- [ ] Compare screens 07, 07c, 07d, 07e, 08, and 09 with the implemented features. Record each requirement as present, adapted with a rationale, or open, with evidence from code or tests. Assign concurrency to v0.6.
- [ ] Review the coverage gaps and trivial assertions in the work index. Add missing tests for substantive Settings and lifecycle behavior. Record existing native UI tests as separate evidence and describe what SPM coverage actually measures.
- [ ] Map existing tests to the five review cases. For each gap, add a named failing test first, then correct only the affected implementation. Reuse existing tests where they already cover the behavior.
- [ ] Verify that the login item, Dock, language, shell and retention settings, and new LaunchAgent policies work within the documented scope. Keep crash notifications disabled until the process supervisor ships. Use measured or verified data for token expiration, SLAs, and performance- and efficiency-core load.
- [ ] Run the full local test suites and native app build. Group manual acceptance into at most three checks covering settings, Jobs and Audit filters, and telemetry and resizing. Retain earlier user acceptance as evidence.
- [ ] Commit the acceptance matrix and required fixes with semantic messages. Wait for PR and main CI.

### Task 2: Ship Signed v0.5.0

**Files** — Release versioning through the existing release-it configuration, `docs/releases/v0.5.0.md`, and `docs/10-development-and-acceptance.md`.

**Interfaces** — Use the passing main commit from Task 1 and the additional plan `2026-11-19-workflow-github-details.md`, which records the November 19 user request for a still-pending PR, step, and log view. Produce an immutable tag, a signed and notarized app ZIP, and a Homebrew cask.

- [ ] Check current releases, the toolchain, and outstanding CI runs. Document features, verified limitations, and the move of concurrency to v0.6 in the release notes.
- [ ] After main CI passes, run `npx release-it 0.5.0 --ci`. Monitor the entire release run, including the tap update, through completion.
- [ ] Verify `brew update && brew upgrade --cask octorunner`, app launch, and `spctl --assess --type execute -vv /Applications/OctoRunner.app`. Keep the ZIP acceptance procedure without Homebrew available as described in docs/10.
- [ ] If a check fails, investigate the logs, fix the issue through a PR, and create a new patch tag. Keep published archives immutable. Provide a German summary for the user with CI and release links and up to three manual checks.
