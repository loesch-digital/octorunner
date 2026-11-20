# Runner Status and Job Result

The user approved keeping runner availability at IDLE (green) or RUNNING
(blue) even when a job fails. Show the most recent completed local job, its
result and completion time, and a safe GitHub link on their own. Add a menu bar
error icon for unacknowledged failures in the loaded history. Acknowledgments
persist across app restarts and leave the job results intact.

## Implementation

1. Start with a failing NSHostingView test in Light and Dark appearances. The
   menu must display a red job-failure indicator alongside the green ready
   status for an active local runner with a failed job.
2. Test selection from GitHub snapshots. Match the active account, exact runner
   ID, repository or organization scope, and unambiguous local identity, then
   select the latest attempt. Use IDs and scope to establish ownership.
3. Use the shared SwiftData source and persist acknowledgments. Show results
   separately in the dashboard and menu, with an additional icon next to the
   existing status logo. Keep the menu bar label free of TimelineView.
4. Verify German and English, VoiceOver, narrow layouts, and screenshots
   rendered using NSHostingView.
5. Run the Swift and Python suites and the debug build. Open a PR, wait for CI
   to pass, merge, and verify CI on main.

## Data Limits and Next Step

Use the existing GitHub history as the source of job results. Show the latest
result as unknown until history has loaded. Keep the existing opt-in background
polling and notification permissions. The Jobs view also supports an explicit
refresh with notifications disabled. Continue with the missing Cache & Storage
tab in the v0.5.0 plan.

## Local Verification

- The NSHostingView regression first failed in Light and Dark appearances
  because the red indicator was missing.
- Tests also reproduced the in-progress retry and singular translation issues
  before their fixes.
- All 241 Swift tests across 50 suites and all 18 Python tests passed. The
  debug app built successfully.
- Reviewed screenshots of the menu and runner row in both appearances.
- An independent read-only review found no significant issues. The query wrapper
  in the menu label reads state and avoids TimelineView. A local interactive
  launch of the scene still needs separate acceptance testing.
