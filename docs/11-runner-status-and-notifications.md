# Runner Status and macOS Notifications

This guide records the v0.5.0 feature branch before release.

The menu bar icon shows the last observed **local process state**. The reading is limited to the local Mac. Every 15 seconds, the app checks for running listener and worker executables without opening runner folders or logs.

| Icon | Meaning |
| --- | --- |
| Green checkmark | All observed local runners are active. |
| Blue circular arrows | At least one local runner is working or restarting. |
| Orange pause | At least one local runner is stopped. |
| Red exclamation mark | An observed runner is in an error state. |
| Gray question mark | There are no runners, the measurement failed, or status data is incomplete or stale. |

A fresh error or offline status takes precedence over other states. Green requires complete, fresh measurements. The icons use distinct shapes, and VoiceOver reads the status as text. Measurements become stale after 60 seconds.

Open Settings from the gear in the main window or press `⌘,`. In **Notifications**, you can enable macOS notifications and select online and offline events individually. The app requests system permission the first time you enable notifications. Background measurements run without prompting for permission. macOS System Settings control banners, history, and sound.

Online and offline notifications reflect local process transitions. The first measurement establishes a baseline. Identical follow-up measurements, busy/idle transitions, and measurement failures do not send notifications. After a measurement fails, the next successful measurement establishes a fresh baseline. New event settings preserve existing consent and disabled events. New event types require their own opt-in.

**At this milestone, runner error notifications are disabled pending crash detection in v0.6.0.** The event pipeline can handle error states. Process sampling can detect when an externally managed process disappears, with no exit code available. Full crash detection, KeepAlive and quarantine monitoring, and GitHub reconciliation are part of the next engine milestone.

Monitoring starts when the app launches, continues while its windows are closed, and ends when the app quits. Installed runner LaunchAgents run independently. Monitoring runs in the app process.

## Low Disk Space Alerts

Every 30 seconds, the app reads only the capacity metadata of the volume that contains the home directory. The check touches no directory listings or documents. It measures the capacity macOS makes available for important data, which may include reclaimable space. Measurements stay on the Mac. The app's privacy manifest declares Apple's reason `85F4.1`.

Turn on both **Low disk space** and macOS notifications to receive alerts. The warning triggers below the storage policy threshold, which defaults to 20 decimal GB. Change the threshold in **Cache & Storage**. The app sends one alert per low-space period and resets once available capacity reaches at least 2 GB above the threshold. Failed or stale measurements leave the current period in effect. The app can retry failed deliveries. [Storage cleanup](15-cache-and-storage.md)

Enabling the alert can report an existing shortage. The disk space check leaves files and system notification permissions untouched. The app must be running to send alerts.

## Failed Local Jobs

When you enable **Local workflow job fails**, OctoRunner checks recent GitHub runs while the app is running, including while its windows are closed. The monitor uses the history polling interval (60–900 seconds) and the same per-account rate-limit budget. The monitor reads credentials and sends requests only when both macOS notifications and this event are enabled. An open Jobs view can also refresh independently. They share rate-limit enforcement, and each can fetch its own data.

Repository runners get history sources from their saved scope. For organization runners, add the repositories explicitly under **Jobs → History sources**. A local match requires both a matching GitHub runner ID and a valid repository or organization scope. Name-only matches, unknown IDs, ambiguous local records, and the personal multi-repository model at this milestone are excluded from notifications.

The first check after launch, an account or credential change, or re-enabling notifications establishes the time baseline. Failures that already completed at that point remain silent. The first baseline can take until the next scheduled poll. Afterward, new completed jobs with `failure` or `timed_out` trigger notifications if they belong to the latest known attempt. Canceled or skipped jobs and jobs with unknown or inconsistent completion times are excluded. A notification contains the local runner name and repository. Job output and private transport diagnostics stay out of the notification.

The monitor deduplicates successfully reported job identities for the current opt-in and a rolling 24-hour window. This handles older jobs observed late and jobs with identical completion times. Failed deliveries can be retried. Turning the setting off and back on between polls discards the prior baseline and any late responses. The monitor checks for account, source, and consent changes, as well as shutdown and cancellation, before writing to the store.

Polling covers the most recent ten runs per repository and can miss events outside that window. Alerts are generated while the app is running, and high-volume repositories or extended network or API outages can push events out of that window. Load older runs from the Jobs view.

## Manual Acceptance Testing

1. Build and launch the development version using the [development and acceptance guide](10-development-and-acceptance.md), without installing it through Homebrew.
2. Check long runner names and many labels at small and large window sizes. **Live Log** opens the log on demand. The dashboard no longer keeps a log panel open.
3. Open **New Runner** with many repositories, shrink the window, and scroll down. Cancel and Create should stay visible. The number of runners started should equal repositories × instances.
4. Enable notifications and allow them in macOS System Settings. Start and stop a test runner with no active jobs using its normal controls. Expect at most one alert per detected transition, according to the event settings. Leave production jobs running.
5. Close the dashboard and verify monitoring continues. Quit OctoRunner and verify the menu bar item and monitoring stop. Launch normally and check that startup does not generate a burst of notifications.
6. Enable job failure notifications, configure a matching repository scope or explicit organization source, and wait for the first check. Run a new test workflow that fails on that local runner. Expect one alert after the next poll and no repeat on identical follow-up samples. Successful and canceled jobs should stay silent.

Automated tests cover paths with spaces, unknown and stale data, state priority, event filters and duplication, older preferences, real process sampling, and late results after cancellation. Verify notification presentation, VoiceOver, and the menu bar on a logged-in desktop.

Injected capacity measurements test thresholds, hysteresis, opt-in, retries, German formatting, and late results. The native volume query and periodic app lifecycle integration still require additional verification. Check the banner in normal use or with a controlled development test adapter so the disk can remain at its normal capacity.

# Runner States and Job Results

Runner state describes local readiness. Green **IDLE** means the runner is waiting for work. Blue **RUNNING** means it is executing a job. A workflow job failure leaves the runner's operational state unchanged.

The dashboard and menu show the **last completed job** separately, with its result, completion time, name, and a GitHub link to the run and attempt. The previous completed result stays visible while a retry runs. If no local job can be verified, the app shows **No completed job loaded**.

Unacknowledged job failures show a separate red error icon in the menu bar alongside the status dot and OctoRunner logo. The dashboard and menu offer an action to acknowledge those failures. It records each job identity (account, repository, run, attempt, and job) so older jobs that arrive late can still be detected. Acknowledgment leaves history, the last result, and runner state intact. The failure count uses the latest known attempt.

These displays reflect **loaded GitHub history**. Existing opt-in background polling continues for job notifications. You can also refresh the history in **Jobs & Workflow Runs** with polling disabled. Job results come from GitHub history under the existing permissions. Matching requires the active account, runner ID, and exact repository or organization scope. Ambiguous identities and name-only matches are excluded.
