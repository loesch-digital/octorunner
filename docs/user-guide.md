# Dialogs and workflows

OctoRunner manages GitHub Actions runners on the Mac where it is installed. [Install OctoRunner](../README.md#install) and [choose the GitHub permissions you need](../README.md#github-permissions).

## Runners

Open **Runners** in the main window. Each runner shows its current availability and, when available, its last observed job result. A runner can be idle and ready for work after its previous job failed.

- **New Runner** opens the setup assistant. Choose a GitHub repository or organization, set the runner name and labels, and review the configuration. You can create a separate registration for each selected personal repository. Labels route jobs and organization runner groups govern repository access.
- **Import Folder…** asks you to select an existing runner installation. OctoRunner requests access when you choose a folder. The runner stays under its existing process manager until you explicitly migrate it. Review the migration confirmation before proceeding.
- **Sync Runners** checks for local runners and refreshes the displayed state. GitHub-backed reconciliation uses the selected account and shows conflicts that need attention.
- **Runner details** shows the registration and service configuration. Start, stop, and restart are available when OctoRunner manages the runner and can perform the action.
- **Runner console** shows local live output and available diagnostic logs. Choose a source, filter or pause the display, and copy or export the entries you need. The available sources depend on the runner and its log files.

Use `GITHUB_WORKSPACE` in a workflow to get the checkout directory. On GitHub's self-hosted runner, `RUNNER_WORKSPACE` points to the per-repository parent directory under the runner's work folder. Use an explicit cache or build directory there when a job needs files outside the checkout. With several runners, `RUNNER_NAME` identifies the assigned runner. Use unique paths or locking for any files deliberately shared between concurrent jobs.

### Runner resources

In **Runners**, CPU and RAM update every five seconds while the dashboard is active. CPU can exceed 100% because 100% represents one fully used logical core. RAM totals the resident memory reported for detected runner processes. Shared memory can be counted by more than one process. CPU appears once a second sample is available.

Select **Measure Work Folder** to add up the logical sizes of regular files in that runner’s configured work folder. The scan skips symbolic links and runs only when requested. macOS may ask for access if the folder is protected. Select the refresh button next to the result to measure it again.

## Menu bar

The menu bar icon summarizes runner availability while OctoRunner is open. Select it to see runner states or return to the dashboard. Closing the dashboard leaves the menu bar available. Quitting OctoRunner stops its monitoring and directly managed processes. Installed user LaunchAgents can continue through `launchd`.

## Jobs & Workflow Runs

Open **Jobs & Workflow Runs** in the sidebar to see stored observations and refresh history from GitHub. For an organization runner, use **History sources** to select the repositories you want to follow. Use the filters to focus on relevant repositories or outcomes. The displayed metrics describe the loaded history. The sidebar counts running workflows across the configured repositories. When a running job can be matched to a local runner, the dashboard links to its workflow details. Elapsed time updates while a workflow, job, or step is running and GitHub provides a start time.

Open a workflow run to see its GitHub link and associated pull request when GitHub provides the data. Expand jobs to see their steps and status. **Load job log** fetches the available log from GitHub on demand. Use the runner console for live output from a local runner.

When a job requests the `self-hosted` label and is queued without an assigned runner, expand it in the workflow details to see its queue hint. OctoRunner compares the requested labels with current GitHub observations of registered runners scoped to that repository. It shows the job’s age when GitHub supplies its creation time. GitHub assigns the job, and other runners and scheduling constraints may be outside OctoRunner’s view.

## Host Telemetry

Open **Host Telemetry** in the sidebar for CPU, memory, storage, and I/O measurements, plus the last observed GitHub API rate limit. Choose a sampling interval or refresh manually. When a runner process is available, inspect its resource usage and uptime. The process inspector asks for confirmation before terminating an identified process.

## Audit Log

Select **Audit Log** in the dashboard toolbar. Filter by category, severity, or runner to find recorded application and runner events. Select an event to see its details, or export the filtered result as JSON.

## Settings

Open **OctoRunner → Settings** or press **⌘,**. Use Settings search to find the relevant page.

| Page | What you can configure |
| --- | --- |
| **General** | Interface language, menu bar and Dock visibility, and app update checks. The interface supports English and German, plus the macOS Light and Dark appearances. |
| **Autostart & Background** | Launch at macOS login, local background monitoring, runner shell and PATH, LaunchAgent inspection, and the capacity limit for directly managed runners. |
| **Failover** | Local restart policy, delay, quarantine threshold, and Low Power Mode behavior. |
| **Cache & Storage** | Workspace age, log retention, automatic cleanup, and a review of managed storage before pruning. |
| **Auth & Tokens** | Connect, switch, reauthenticate, or disconnect GitHub accounts and inspect reported permissions. OctoRunner stores tokens in the macOS Keychain. |
| **Notifications** | Opt in to macOS notifications for runner availability or errors, local job failures, and low disk space. macOS controls delivery and presentation. |

### Local background monitoring

In **Autostart & Background**, enable **Monitor local runners after quitting**. Quit OctoRunner with **⌘Q** to hand local process monitoring to the background helper. Opening OctoRunner brings monitoring back into the app.

On macOS 27 and later, use **Stop Running in Background** in OctoRunner’s Dock menu to stop the current monitoring session. After you sign in again, monitoring starts when you open OctoRunner. Enable **Launch at Login** if you want that to happen automatically. On earlier macOS versions, approve or disable the helper under **System Settings → General → Login Items & Extensions**.

The helper observes registered runner processes on your Mac. GitHub refreshes and OctoRunner notifications run while the app is open. Runner LaunchAgents follow their own configuration. OctoRunner stops its background helper before replacing the app during an in-app update. Turn the monitoring setting back on after the update if you want it to continue.

If GitHub lists workflow write access under **Existing access** for OctoRunner, that permission is part of a prior OAuth grant. Revoke OctoRunner under **GitHub Settings → Applications → Authorized OAuth Apps** before reconnecting if you want to replace the prior grant. For monitoring a selected private repository, use a fine-grained token with **Actions: Read** and add **Pull requests: Read** if you want PR lookup. [Manage authorized OAuth apps](https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/reviewing-your-authorized-oauth-apps)
