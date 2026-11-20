# Job History Data and Metrics

This guide records work in progress for v0.5.0. The API, persistence, metrics, and handling of loading and account changes are implemented and connected to the Jobs view in the main window. The full v0.5.0 milestone was still in progress at this point.

The Actions client uses GET for workflow runs, jobs, steps, and available job logs. It requires no additional write permissions. The client rejects JSON redirects and limits pagination to HTTPS on `api.github.com` for the requested repository and endpoint. Rate limits and retry delays come from the actual response headers. Error details include status codes and omit response bodies and credentials.

Accounts, repositories, workflow runs, run attempts, and individual matrix jobs have distinct identities. A missing attempt number stays unknown. Once a numbered attempt is available, it takes the place of the unnumbered snapshot in the visible workflow list and metrics. Older attempts stay in storage. Remote history snapshots runner metadata and retains it when a local runner is removed. Existing cascade behavior for legacy local jobs is preserved.

Metrics describe the loaded history window.

- The workflow count uses one entry per workflow run at its latest known attempt. Matrix jobs leave that count unchanged.
- The success rate is `success / (success + failure + timed_out + startup_failure + action_required + stale)`. It excludes canceled, skipped, neutral, and unknown results. A percentage requires at least one eligible result.
- Average duration includes completed workflows with known durations, regardless of conclusion. It excludes missing or negative intervals and preserves legacy durations.
- The duration SLA is the fraction of known durations at or below a configured time limit. It requires both a limit and a sample. It measures elapsed time independently of the outcome.
- The count of runs completed today uses known completion times and the supplied calendar. Runs with missing completion times are excluded.
- Live counts for running and queued workflows require an observation within the past 90 seconds. Older open states are counted as stale, and history retains the last observed status.

The loader fetches ten workflow runs per page and all associated job pages, up to 20 job pages per attempt. It rejects cyclic pagination. Completed attempts with complete job data reuse their stored details. In-progress attempts are fetched again. Missing attempt numbers stay unknown.

Account changes, selection changes, and cancellation discard late data before every SwiftData access. Rate-limit metadata applies to the response's account, even if a response arrives after the selection changes. An existing longer wait remains in effect. All repositories on the same account share the restriction, and other accounts remain available. When the budget is exhausted, the loader stops sending job requests and marks partial details as incomplete.

Before each request, the loader honors both `Retry-After` and the reset time for an exhausted budget. If the server provides no usable time, the wait starts at one minute and doubles on further rate-limit errors, up to one hour. Retrying requires a new load operation. [GitHub REST API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)

The loader derives workflow completion from a complete job list with known completion times. GitHub's `updated_at` records an update time. Partial pages or in-progress jobs leave the completed workflow duration unknown.

The migration test copies a real SQLite file from the v0.4 schema and opens it directly with the expanded SwiftData schema. It checks that accounts, runners, job relationships, audit entries, and stored values survive without deleting or recreating the store. It also verifies that new history entries can be saved after migration and read in a fresh model context.

## Using and Refreshing History

Select **Jobs & Workflow Runs** in the sidebar to open history in the main window. Status, repository, runner, and workflow/branch/commit/PR filters apply to the latest known attempt. Expand a job to see details, or click the GitHub link to open the associated workflow and logs. Links are limited to the verified host and run.

**History sources** uses repository URLs from local runners. For organization runners, explicitly add an `owner/repository` or a GitHub repository URL. Additional sources are saved for the active account. Removing a source keeps its saved history. The app uses these sources without enumerating all account repositories or requesting additional GitHub write permissions.

While the app is active and the view is open, it refreshes the first ten runs for each selected source every 60 seconds. Select a specific repository to **Load older runs**. Each run shows its own observation time. **Last response** indicates when the most recent source was loaded. Open runs on older pages can become stale and are labeled accordingly.

A repository error allows the batch to continue with other sources. The view lists the affected sources together. Authentication errors, rate limits, and cancellation stop the batch. After an error, automatic refresh pauses until you retry. The shared account budget lives in AppServices, so active rate restrictions persist across Runner and Jobs views and Jobs view model recreation.

The duration target starts unset and is saved when selected. Metrics follow the current filters and use a dash when data is missing.

## Verification

On November 12, 2026, 141 coverage-instrumented Swift tests and ten Python tests passed, and the full Xcode Debug build succeeded. Line coverage was 99% for the history store, 100% for metrics, 97% for history filters, 100% for the loader, 99% for the loading view model, and 100% for budget state and history preferences. NSHostingView tests cover the Jobs view at 560 and 900 points in Light and Dark appearances with long names, 80 repository choices, and 80 job snapshots. German and English status labels and safe GitHub links have dedicated tests.

Interactive acceptance of the full app and testing across supported macOS versions remained separate. Verify the following manually.

1. Expand **History sources**, add a readable test repository, and remove it again.
2. Combine status, repository, runner, and search filters in narrow and wide windows.
3. Expand jobs and open the workflow link.
4. Load older runs for one repository. Leave the SLA target unset and verify the SLA remains unknown.
5. Switch accounts, then return to the dashboard while a load is in progress. Check that prior-account data stays out of the view and cancellation alone produces no error.
6. When a genuine API or permission error occurs, verify the message and that refresh pauses. Observe naturally occurring errors so the test stays within normal request volumes.

## Pull Request Association and Actions Details

**View workflow details** opens the selected, numbered attempt with expandable jobs and individual steps. Attempt number, state, result, and available timestamps are shown individually. A duration requires known timestamps. The open detail view refreshes in-progress jobs every 30 seconds and shows the observation time. It flags errors and incomplete job pages. Closing the view or switching accounts discards late data.

PR references come from the base repository in the API response. When references are missing for a PR event, history performs a limited lookup for PRs associated with the commit. A fine-grained token needs **Pull requests: read** for that lookup. **Actions: read** is sufficient for jobs, steps, and logs. Without PR read access, the PR remains unknown and Actions history remains available. The app requests no additional OAuth write permissions. Derived web links point only to the validated repository and PR, run, or job on github.com.

**Load job log** opens a separate view. Use its load button to request a log snapshot. The snapshot is available on demand in the view, with GitHub as a fallback. Private log export is outside this workflow. A separate byte stream reads up to 1 MiB plus one byte to detect truncation, then stops the transfer. The view displays only UTF-8 text and shows truncation and load time. Logs that are unavailable or have expired get a distinct message.

The log endpoint may redirect once to a temporary HTTPS download URL. That second request omits authorization and cookies. The client rejects further redirects. Signed URLs and log contents stay out of SwiftData, audit logs, and diagnostic output. Local runner live streaming follows separately in v0.6.
