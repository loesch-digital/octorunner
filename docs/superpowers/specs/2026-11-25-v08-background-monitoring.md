# OctoRunner v0.8 Background Monitoring

Status: Draft for review.

OctoRunner can continue monitoring registered runners after the user quits the app. The user explicitly enables this per macOS account. On macOS 27, verify that the system associates the running helper with OctoRunner and presents its native Dock status. Support macOS 15 and later with status in App Settings and System Settings.

For the local-only build on macOS 27 and later, OctoRunner launches its bundled helper during Command-Q so macOS can associate the remaining process with the Dock entry. **Stop Running in Background** ends that monitoring session. After a new login, OctoRunner starts monitoring when the app opens, including through its existing optional login setting. Earlier macOS versions retain the separately registered LaunchAgent. GitHub monitoring and notifications run in the foreground in this build.

## User experience

- **App Settings → Autostart & Background** includes an off-by-default **Keep monitoring after quitting** switch. Login launch for the GUI remains a separate setting. Explain that enabling background monitoring registers a per-user service that can start at login, regardless of whether the dashboard opens.
- The settings show whether the service is off, waiting for macOS approval, starting, actively monitoring, or unavailable. A registered service alone does not qualify as active. Show the last successful observation and whether local or GitHub monitoring is unavailable.
- With monitoring active, `⌘Q` quits the GUI and the menu bar extra, and the service continues. The quit dialog describes what persists and accounts for directly managed runners that must shut down before quit. Closing the last window continues to follow the existing Dock and menu bar preferences.
- With the feature off or unavailable, `⌘Q` keeps the current behavior. An unavailable helper is disclosed in the quit dialog before the user exits.
- Turning the switch off, or disabling the background item in macOS, stops background monitoring. Detect a macOS suspension or revocation, show it accurately, and require a user action to enable the service again. Disabling monitoring does not stop independently running LaunchAgent runners.
- Provide English and German copy and accessibility labels. On macOS 27, macOS owns the localized Dock text and its stop action. Validate both on a signed installation. A native Dock indicator is not part of macOS 15 support.

## Runtime responsibilities

- Use a per-user LaunchAgent packaged and signed with OctoRunner and registered through `SMAppService.agent(plistName:)`. Use the logged-in user’s session. The helper does not need root or a separate login item for the GUI.
- The helper observes already registered local runner processes and GitHub runner status and job results for the selected account. It sends the already configured macOS notifications for supported state transitions and failed jobs. Unknown or stale data stays distinct from offline or failed.
- Retain the existing process supervisor in the GUI. The helper observes runner state and does not install, start, stop, restart, or migrate runners. On-demand history, GitHub mutations, and storage maintenance stay in the GUI. Existing shutdown safeguards for directly managed runners still apply.
- Give exactly one process ownership of periodic notifications and runner monitoring. Use an exclusive per-user OS lock while a process runs those loops. Finish or cancel the current iteration before releasing ownership. On an unexpected helper exit, the GUI may resume by taking a released lock. A timeout or stale heartbeat alone never authorizes a second owner.
- Preserve deduplication across transitions and restarts. Reuse stable runner transition and GitHub job identities with a bounded persisted ledger. Capture a baseline without replaying already observed jobs. Publish an observation timestamp, and let the GUI mark old observations as stale.

## Data and security

- The GUI owns the existing SwiftData store. The helper consumes a versioned, atomic, user-private snapshot of registered runner descriptors and the preferences required for monitoring. The helper keeps its observations and notification state outside the SwiftData store. The GUI may import eligible audit events once, using their stable event identifiers.
- Only pass the minimum local process metadata and the existing GitHub account identifier. Never persist OAuth tokens or runner registration credentials in snapshots, transport messages, logs, or preferences. The helper does not scan protected folders or read external runner installation files. Editing an external registration or changing the account remains a GUI action.
- Verify a narrowly scoped shared data protection Keychain access group under the signed distribution identity before transferring existing credentials. Preserve existing login and revocation behavior. On a locked or unavailable keychain or a revoked token, local monitoring continues and GitHub status becomes unavailable. Background mode never prompts for login or uses a less protected credential store.
- Keep process communication local. Authenticate bundle and Team IDs on both ends of any XPC connection. The protocol carries capability and health status and control signals without tokens or arbitrary commands. A process with an incompatible protocol version is shown as unavailable.
- Suspend and verify helper exit before replacing the signed bundle during an update. If update or recovery fails, do not start an unverified binary or allow two monitors. Restore the previous opt-in only when the validated app and helper versions are compatible.

## Acceptance

1. With the feature disabled, close the window and quit separately. Only closing the window leaves GUI monitoring alive. An independently configured runner retains its prior behavior.
2. On a signed macOS 27 installation, enable background monitoring, approve it in macOS, and quit. Verify the GUI and its menu bar extra disappear, the helper continues collecting observations and delivering configured alerts, and the native Dock status and stop action are available.
3. Stop the service from macOS, then reopen OctoRunner. Verify truthful settings, no silent reactivation, and no duplicate notification. Repeat without network access and with an unavailable Keychain.
4. On macOS 15, verify settings and monitoring after quit without relying on the macOS 27 Dock feature. Verify that opt-in survives a clean update and that rollback leaves a usable foreground app.
5. Use fixtures or a controlled runner. Keep active jobs safe and confirm that the helper never requests Documents access at startup or observes unregistered folders.

[Apple background processes guidance](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac) · [Service Management](https://developer.apple.com/documentation/servicemanagement/smappservice) · [XPC](https://developer.apple.com/documentation/xpc)
