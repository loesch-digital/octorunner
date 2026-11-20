# v0.6 Safe Runner Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use the existing authorization to continue with native implementation.

**Goal** — Take full control of imported runners through a confirmed, traceable migration and report recovery status accurately when a step fails.

**Architecture** — A journaled state machine records validation, stopping, new registration, starting, and commit as separate stages. The original private runner keys stay in place. File system rollback and compensating GitHub actions are distinct operations.

**Tech stack** — Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement, and the existing Python and GitHub Actions tools.

**Spec** — `docs/08-sync-kit-and-local-runner-import.md`, ADR-01, and the v0.6 supervisor plan. The November 19, 2026 scope decision places the global concurrency limit in v0.6.

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

1. Require explicit authorization before interrupting a job on a busy runner (Task 1).
2. Recheck symlinks and source paths to avoid taking ownership of unrelated files (Task 1).
3. Keep `.credentials_rsaparams` unread, uncopied, and excluded from exports (Tasks 1 and 2).
4. After a failure following GitHub registration, perform and report the actual compensating server action (Task 2).
5. Resume after a crash between stages without starting a duplicate listener (Task 2).

### Task 1: Preflight and Confirmation

**Files** — Modify `RunnerEngine/RunnerProvisionerActor.swift` and `AppShellFeature/RunnerMigrationCompletion.swift`. Create `RunnerEngine/RunnerMigrationPlan.swift` and `AppShellFeature/RunnerMigrationConfirmation.swift`. Use the existing tests in `RunnerMigrationSafetyTests.swift` and `RunnerMigrationCompletionTests.swift`.

**Interfaces** — The immutable MigrationPlan contains the runner ID, verified source and destination, account and scope, labels and group, and expected effects. Keep credentials out of the plan. Use the supervisor from the preceding plan.

- [x] Covered the previous copy path with tests for the source folder, symlinks, an active listener, a running job, and missing GitHub access.
- [x] Preflight reads only metadata from the selected source. Before registration, it rechecks source identity, stopped listener status, labels, account, GitHub target, and group when applicable.
- [x] Both UI entry points open the same confirmation. The dialog shows the operating mode, new registration, working directory, and recovery options. NSHostingView tests cover English and German.

### Task 2: Journal, Takeover, and Recovery

**Files** — Create `RunnerEngine/RunnerMigrationCoordinator.swift` and `RunnerEngine/RunnerMigrationJournal.swift`. Modify the provisioner and MigrationCompletion. Test in `RunnerMigrationTransactionTests.swift`.

**Interfaces** — Coordinator method `migrate(plan: RunnerMigrationPlan) async throws` reports verified completion or the need for recovery. The journal stores only IDs, nonsecret paths, stages, and results. Access credentials only in the existing secure registration service.

- [x] Tested failure boundaries for preflight, preparation, registration, model commit, and startup, and resumption with a new coordinator. The original key stays in the source folder. Open migrations block both paths from import.
- [x] Takeover requires a stopped old listener and disabled automatic startup. OctoRunner rejects an installed standard service and checks local and GitHub status. The new installation uses a checksum-verified archive and a short-lived registration token.
- [x] Store the verified GitHub ID before startup. OctoRunner can safely discard prepared files and resume after confirmed registration. If interruption leaves the GitHub outcome unknown, verify it in GitHub because the registration program performs replacement by name.
- [x] SwiftData reloads the runner ID after asynchronous steps. The commit includes a runner-specific audit entry. On interruption, the journal shows the last confirmed stage and available recovery steps.
- [ ] Pass tests, get independent review, commit, and pass CI gates. Use a disposable runner for user acceptance and failure simulations.
