# Cache & Storage

The sixth settings page uses the existing card layout. Click **Analyze storage** to start. The default policy, **Manual only**, leaves directory analysis and cleanup to the user. The feature requires no additional GitHub or macOS notification permissions.

## Scope

Analysis covers only direct runner subdirectories under `~/Library/Application Support/io.octorunner.macos/runners`. It excludes imported runners and external paths. After migration, cleanup also requires the saved service name to match the canonical provisioned name. Stale or mismatched service associations are ineligible.

Analysis checks `_work` and `_diag` for workspaces, tools, the Actions cache, temporary files, and diagnostic logs. It reports logical file sizes. Actual reclaimed APFS space can differ. Available capacity comes from volume metadata.

The preview lists each candidate with its runner ID and relative path. Eligible items are old workspaces, `_actions`, `_temp`, and `Runner_*.log` or `Worker_*.log` files. Cleanup preserves the newest diagnostic log, `_tool`, other reserved directories, runner configuration, binaries, and launchd output logs. It skips symlinks.

## Protecting Active Jobs

Before deleting anything, cleanup verifies the current model identity, checks that listener and worker processes are absent, and confirms that the LaunchAgent is unloaded. An idle runner may still be running. Cleanup skips unknown states. After asynchronous checks, the app rereads age, size, and file identity. It skips any item that changed since the preview. Later start and stop controls must coordinate cleanup with runner state.

## Policies

- **Manual only** requires a preview and explicit confirmation.
- **Remove old data automatically** runs every ten minutes while the app is running.
- **Only when disk space is low** uses the same age limits and stops once the configured capacity is available. It requires a reliable capacity measurement before deleting anything.

The existing AppPreferencesStore saves workspace age, log retention, and minimum capacity. Changing the policy during cleanup stops further deletions. The audit log records cleanup success and errors. The app saves a start entry before the first possible deletion. Cancellation retains that entry and discards the preview. The completion entry records the final counts.

## Differences From the Mockup

Global DerivedData directories and host caches are outside the scope of automatic analysis and cleanup. Other Xcode processes may use them, and there is currently no reliable way to associate them with runner jobs. Checking that no runner is busy cannot establish that those files are safe to remove. Imported Documents folders are also outside the cleanup scope.

The cleanup feature requires the runner to be stopped and unloaded. The v0.6.0 engine controls provide that operation. A preview can therefore include candidates that cleanup later skips because their LaunchAgent is still loaded. Cleanup reports deleted and skipped items separately.
