# GitHub Links and Actions Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. The user has authorized native implementation.

**Goal** — Show the associated pull request in Jobs, link directly to the PR, run, and job on GitHub, and show workflow, job, and step states along with available logs.

**Architecture** — Extend the existing account-scoped history pipeline. Read workflow data from the GitHub REST API. The v0.6 local runner log stream is separate. These read-only features require only the relevant read permissions.

**Tech stack** — macOS 15+, Swift 6 strict concurrency, SwiftUI, SwiftData, and the existing GitHubActionsClient and Keychain lookup.

**Spec** — The November 19, 2026 request for PR links and Actions details, dialog 8 in docs/07, docs/assets/screens/08_jobs_workflow_runs.png, and docs/12-jobs-history-and-metrics.md.

## Global Constraints

- Follow AGENTS.md, the four repo skills, and their relevant references before changing code. Apply the existing native implementation, branching, TDD, and CI rules.
- Finish the reviewed acceptance branch and wait for PR and main CI to pass before starting production changes for Jobs. This plan is an additional dependency for the stable v0.5 release.
- Keep the existing permission boundary for read-only views. Check each REST endpoint's requirements against current official GitHub documentation. Treat OAuth scope headers as observations only.
- Keep tokens, signed download URLs, and private log contents out of diagnostics and audit records. Download logs only when the user opens them.
- Keep ModelContext and its models on MainActor. Give new model properties defaults, test migration with a real older store, and keep the SQLite header check.
- When the API cannot establish whether a PR exists, show the metadata as unavailable. Show a PR for push and dispatch runs only when its association is verified.
- Implement the relevant read-only Actions details in the native design. Keep links to GitHub for full web functionality, including Rerun and Cancel.

## Review Focus

1. Validate the repository for fork PRs before creating links (Task 1).
2. Keep jobs, steps, and logs scoped to the exact run attempt (Tasks 2 and 3).
3. Prevent late responses from changing persistence or UI after an account switch or teardown (all tasks).
4. Show missing data explicitly when API responses are empty or limited (Tasks 2 and 3).
5. Bound memory, isolate credentials across redirects, and show truncation for large logs (Task 3).

### Task 1: PR Association from API DTO to UI

**Files** — Modify `Packages/OctoRunnerKit/Sources/GitHubAPI/GitHubWorkflowRunDTO.swift`, `Sources/CoreModels/JobRunEntity.swift`, `Sources/CoreModels/WorkflowHistoryEntry.swift`, `Sources/CoreModels/WorkflowHistoryFilter.swift`, `Sources/AppShellFeature/WorkflowHistoryStore.swift`, `Sources/AppShellFeature/WorkflowRunHistoryRow.swift`, and `Sources/AppShellFeature/WorkflowHistoryPresentation.swift`. All source paths are under Packages/OctoRunnerKit. Create GitHubWorkflowPullRequestDTO.swift and WorkflowPullRequestReference.swift in the appropriate modules. Add WorkflowPullRequestTests.swift and use the existing decoding, persistence, and layout tests.

**Interfaces** — `GitHubWorkflowRunDTO.pullRequests: [GitHubWorkflowPullRequestDTO]?`. A reference contains a positive number and an explicit base repository. Convert the DTO into validated `[WorkflowPullRequestReference]`, store it as optional JSON data defaulting to nil, and expose it in the immutable history snapshot. Accept only HTTPS github.com links for the matching base repository and `/pull/<positive number>`, without user information, a query, or a fragment.

- [ ] RED — Test decoding API `pull_requests` with PR #12, push runs with the field omitted, an explicitly empty field, multiple PRs, and fork head and base. Reject links for negative numbers or incorrect hosts or paths. Check official API documentation for which run responses omit PRs. If needed, look up PRs by commit and link only a confirmed match. Otherwise keep the association unknown.
- [ ] RED — Test persistence round trips, the same run across accounts and attempts, refresh, and a late response after an account switch. Open an existing on-disk store and verify account and runner data survive.
- [ ] GREEN — Pass references through the existing pipeline without an additional automatic request. Show PR #12 as a link and keep branch, commit, and trigger separate. Find PRs by number in search. Check NSHostingView in German and English, Light and Dark appearances, and narrow and wide layouts, with long titles and multiple PRs.
- [ ] Run the full Swift and Python tests and native app build. Get an independent review, commit semantically, wait for PR CI, merge, and wait for all main CI checks to pass.

### Task 2: Workflow, Job, and Step Details

**Files** — Modify GitHubWorkflowJobDTO.swift, GitHubActionsClient.swift, and WorkflowRunHistoryRow.swift. Create GitHubWorkflowStepDTO.swift in GitHubAPI and WorkflowRunDetailModel.swift, WorkflowRunDetailView.swift, and WorkflowJobStepView.swift in AppShellFeature. Add WorkflowRunDetailTests.swift and a native navigation test.

**Interfaces** — `GitHubWorkflowJobDTO.steps: [GitHubWorkflowStepDTO]?`. A step has a number, name, status, conclusion, and actual optional start and end times. The detail selection is an immutable `(accountID, repository, runID, attempt, jobID?)`. Load details for that exact attempt, discard stale generations, stop refresh at teardown, and respect the existing RateBudget.

- [ ] RED — Test mixed step states (queued, running, succeeded, failed, skipped, cancelled, and unknown), null timestamps, missing steps, and changes in attempt. Show duration only when timestamps support it, and keep other jobs visible when one fails.
- [ ] RED — Test opening details, selecting a job, run, job, and PR links, and keyboard and VoiceOver use. Discard incoming data after teardown or account switch. Show 403, 404, 429, and incomplete pagination.
- [ ] GREEN — Show a compact run summary, expandable jobs, and steps with number, status, duration, and verified freshness. Mark historical or stale data accordingly. Make the detail view responsive and open the console on demand.
- [ ] Run the full tests, build, review, and PR and main CI as in Task 1.

### Task 3: Available Job Logs and the v0.5 Release Gate

**Files** — Create GitHubJobLogLoader.swift in GitHubAPI and WorkflowJobLogModel.swift and WorkflowJobLogView.swift in AppShellFeature. Extend DetailView, add GitHubJobLogLoaderTests.swift and WorkflowJobLogTests.swift, and update docs/12 and docs/releases/v0.5.0.md.

**Interfaces** — `loadJobLog(selection: WorkflowJobLogSelection) async throws -> WorkflowJobLogSnapshot`. The snapshot contains text, observation time, and `isTruncated`. Cap the displayed UTF-8 text at 1 MiB and enforce a streaming download limit. Use the bounded stream for job archives to avoid loading an entire archive with `data(for:)`. Use the job-specific endpoint documented in the current official API. Keep Authorization on the GitHub host across redirects and signed URLs out of persistence. Load a log only when the user selects it.

- [ ] RED — Test 401 and 403 responses, expired or pending logs, running jobs, redirects that omit Authorization to the external download host, cancellation, late responses, oversized streams, UTF-8 characters split across chunks, and binary responses. Shut down the local stub server with the existing asynchronous PythonTestServer helper to keep the Swift executor unblocked.
- [ ] GREEN — Make available logs readable and selectable. Explicitly display “Not yet available,” “Truncated,” and “Last loaded.” Show REST logs as snapshots with a direct Actions link for fallback, and surface errors.
- [ ] Add snapshot and hosting checks for long lines and narrow windows and a native selection test. Require user action to download or export private logs. Local runner live streaming belongs to v0.6.
- [ ] Complete tests, build, review, and PR and main CI before starting Task 2 of the v0.5 acceptance plan. Mention PR, step, and log features in the release notes and acceptance matrix once integrated.
