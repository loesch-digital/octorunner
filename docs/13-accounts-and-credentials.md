# Accounts and Credentials During v0.5.0 Development

Authentication stores tokens exclusively in the macOS Keychain. SwiftData holds account metadata and nonsecret lookup keys. The displayed OAuth scopes come from GitHub's response. For fine-grained PATs with missing scope headers, permissions remain unknown.

New credentials get a unique key made from the immutable GitHub ID and a version ID. Renaming or reassigning a login therefore leaves other accounts' tokens intact. Existing login-based keys remain readable. Signing in again moves the account to the new format and retains old keys for targeted cleanup. The app exposes at most one active account at a time. The wizard, runner sync, label updates, and Jobs all use that account's stored key.

Closing the sign-in dialog cancels device-code, PAT, and polling requests. Late responses leave the clipboard and account data untouched. The app removes saved credentials that had yet to be adopted. If saving metadata fails, the app rolls back the authentication changes and preserves other pending changes in the shared model context.

Disconnecting first removes the account's current and previous credentials, then removes its metadata and records a success event in the audit log. Lookup keys referenced by other accounts are preserved. The app reports errors and records success only after completion. A concurrent sign-in is preserved through its separate credential version and a metadata check. Local sign-out leaves tokens valid on GitHub and installed runner services running.

Automated regression tests cover reassigned logins, legacy cleanup, cancellation immediately after saving to Keychain, late responses, account changes, concurrent sign-out, and save failures followed by a later successful context save. Keychain integration tests use synthetic values in separate UUID-based test services.

Open **Auth & Tokens** from Settings in the main window or from the native Settings scene. The selected account appears first. You can connect, sign in again, select an account, and confirm disconnection. Opening the view leaves token contents unread. It shows scope metadata where available. Token expiration and Touch ID controls are outside this view's scope. The API requests use REST version `2026-03-10`. Invalid token characters are rejected before the request constructs an HTTP credential header. [GitHub REST API versions](https://docs.github.com/en/rest/about-the-rest-api/api-versions)

NSHostingView tests and reviewed renders cover empty views and 80 accounts with long names and permission lists at 620 and 900 points, in German and English and in Light and Dark appearances. Native dialogs still require manual acceptance with real accounts.

- Open Settings from the main window. Then press `⌘,` and open the Auth tab again.
- Connect two test accounts, switch the selection, and verify that Jobs and the wizard use the selected account. Signing in again as the same identity replaces its credentials. Signing in under another identity adds a separate account.
- Start PAT or device sign-in, cancel it, and reopen it. Verify that no late success message appears and the accounts and selection remain intact.
- Choose **Disconnect account…**, cancel, then confirm disconnection for a test account. Verify that the other account and running runner services remain available.
- If OAuth scope headers are missing, verify that permissions are shown as unknown. Verify that the view exposes no token values or guessed expiration dates.

At this milestone, interactive acceptance and the remaining Step 5 features were still open, particularly storage, full telemetry, and the audit UI.
