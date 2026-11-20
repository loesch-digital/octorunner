# v0.6 Periodic GitHub Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use the existing authorization to continue with native implementation.

**Goal** — Periodically reconcile local and remote runners by account and make confirmed conflicts visible and actionable.

**Architecture** — SyncKit produces immutable snapshots and computes a side-effect-free reconciliation plan. Update SwiftData on MainActor only after verifying the account and generation. Require explicit authorization for GitHub writes.

**Tech stack** — Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement, and the existing Python and GitHub Actions tools.

**Spec** — `docs/08-sync-kit-and-local-runner-import.md`, ADR-05, `docs/09-pipeline-privacy-and-test-audit.md`, and the v0.6 engine and migration plans. The November 19, 2026 scope decision places the global concurrency limit in v0.6.

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

1. Preserve distinct meanings for 401, 403, 404, and 429 (Task 1).
2. Discard late responses after an account switch (Task 1).
3. When the local process is active and GitHub reports it offline, show the conflict with timestamps (Task 2).
4. Match runner identity by remote ID and repository scope even when names are identical (Task 2).
5. Preserve partial success when permissions are missing or only some repositories succeed (Task 3).

### Task 1: Typed API Results and Lifecycle

**Files** — Modify `SyncKit/GitHubRunnerSyncActor.swift` and `SyncKit/SyncModels.swift`. Create `SyncKit/RunnerSyncScheduler.swift`. Test in `RunnerSyncSchedulingTests.swift` and the existing `SyncKitTests.swift`.

**Interfaces** — Typed results are found, notFound, unauthorized, forbidden, rateLimited, and unavailable. A snapshot contains the account ID, generation, and observation time. Preserve typed errors through the lookup and avoid collapsing distinct outcomes to nil with `try?`.

- [x] Added transport and decoding tests for `GitHubRunnerProvisioningAPI.swift` covering repository and organization endpoints, short-lived registration tokens, missing permissions, and error output that excludes response bodies and secrets. Exercise behavior beyond DTO construction.
- [x] Wrote failing transport and fake-clock tests for 200, 304, 401, 403, 404, 429, pagination, Retry-After, cancellation, and account switches.
- [x] Used the existing shared GitHub transport and verified the current API version against official documentation. Use conditional requests, bounded concurrency, and rate-limit backoff through the shared scheduler.
- [x] Start and stop the scheduler with the app lifecycle. Without a separate agent, reconciliation stops when the GUI closes.

**Implementation status** — Single-runner lookup uses the shared GitHub transport and API version 2026-03-10. ETag caching and rate-limit backoff are scoped by account. The app service starts and stops with the GUI. A new account selection revision invalidates in-flight requests even after switching back to the original account. Local folder import and remote lookup run separately. The wizard stores the runner ID during setup. After individual requests, reconciliation checks one shared runner list for all 404s in the same repository or organization. A confirmed ID match can come from a paginated list. Report absence only from a complete single-page response without a continuation. Additions and deletions during a multipage request can shift results across pages.

### Task 2: Conflict Detection and Resolution

**Files** — Create `SyncKit/RunnerReconciler.swift`, `CoreModels/RunnerSyncConflict.swift`, and `AppShellFeature/RunnerSyncConflictView.swift`. Modify IntegrationController or RunnerEntity if a schema change is required. Test in `RunnerReconciliationTests.swift`.

**Interfaces** — The pure function `reconcile(local:remote:)` returns confirmed changes and explicit conflicts, matched by account, scope, and remote ID.

- [x] Added failing tests for busy, online, offline, removed runners, duplicate names, label or group mismatches, stale responses, and contradictory local activity.
- [x] Adopt only confirmed observed status data. Show label conflicts and group membership mismatches. “Use Remote Labels” and “Apply Local Labels to GitHub” are separate actions with their own confirmations and audit entries.
- [x] Added model properties with defaults, schema and migration tests, and makeInMemoryContainer. Preserve the existing store. Passed UI and unit tests, committed, and passed CI gates.

**Implementation status** — The dashboard and runner settings show verified status and label differences with separate local and GitHub status. An unverified HTTP 404 remains ambiguous. If a complete single-page list for the scope lacks the runner ID, OctoRunner reports it and keeps the local entry. Each direction of label reconciliation requires its own confirmation and audits accepted changes. To update GitHub, OctoRunner rechecks registration, submits only custom labels, and updates local state from the verified GitHub response. An open migration recovery journal blocks label changes. Runner settings can verify membership in the stored group through a read request. If a complete single-page membership list lacks the runner, the view shows the discrepancy. Change group membership in GitHub.

### Task 3: Groups, Multiple Repositories, and the v0.6 Release

**Files** — Modify `AppShellFeature/AddRunnerWizardViewModel.swift`, `AppShellFeature/RunnerTargetLoading.swift`, `CoreModels/RunnerScopeType.swift`, and the existing wizard views. Test in `RunnerWizardProvisioningTests.swift` and `GitHubPermissionTests.swift`. Update `docs/releases/v0.6.0.md`.

**Interfaces** — Personal multi-repository setup creates separate repository registrations. Organizations can use GitHub runner groups. Prefixes are for naming, labels are for routing, and groups define access and organization.

- [x] Implemented the organization and repository permissions overview from screenshot 07c with assigned runner counts and an explicit permission sync action. Requests use actual group and target data. Tests cover missing permissions, account switches, and stale sync responses.
- [x] Compared behavior with screens 03 and 04. Tests cover separate repositories with the same prefix, group queries, partial failures, and identity after migration.
- [x] Connected the wizard, model, and API consistently. Verified endpoint permissions against current GitHub documentation. Show unknown token permissions as unknown.
- [x] Passed local tests, Xcode build, review, PR CI, and main CI for the feature. [PR #43](https://github.com/loesch-digital/octorunner/pull/43) · [Main CI](https://github.com/loesch-digital/octorunner/actions/runs/44718206244)
- [x] Completed the version PR and its main CI. Tagged the verified commit with `release-it` and pushed only the release tag. Verified the release, Homebrew upgrade, installed process launch, and Gatekeeper. [Version PR](https://github.com/loesch-digital/octorunner/pull/44) · [Main CI](https://github.com/loesch-digital/octorunner/actions/runs/44721755971) · [Release run](https://github.com/loesch-digital/octorunner/actions/runs/44723287728)

**Implementation status** — The permissions overview requests runner lists for each saved target using the active account. It shows verified read access and separate counts for GitHub registrations and matching runners on this Mac. For organizations, it also requests visible groups. The wizard creates a registration per selected repository and reports partial failures with the count of saved runners. Organization groups come from GitHub and are rechecked before registration. New registrations omit GitHub's replacement option. Confirmed migration saves the verified runner group with the new runner ID.
