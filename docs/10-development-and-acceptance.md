# Testing OctoRunner on a Mac

You can test a development build or signed release before installing it through Homebrew.

| What to test | Method | What it verifies |
| --- | --- | --- |
| An unpublished branch | Debug build from Xcode | Current source, debugger, and logs |
| A published release | Signed ZIP from GitHub Releases | Distributed app, signature, and notarization |
| Final installation | Homebrew upgrade | Cask, download, checksum, and upgrade |

## 1. Run locally from Xcode

Install the full current stable Xcode and XcodeGen. The November 11, 2026 check used Xcode 27.2 with Swift 6.4.2. See the [toolchain audit](09-pipeline-privacy-and-test-audit.md). XcodeGen also supports installation with Make and Swift Package Manager. [XcodeGen installation instructions](https://github.com/yonaskolb/XcodeGen#installing).

1. Fully exit the installed OctoRunner app using **Quit**. Closing the dashboard leaves the app running.
2. Check out the branch you want to test and record its commit using `git rev-parse HEAD`.
3. In the repository, run the tests and generate the project.

   ```sh
   swift test --package-path Packages/OctoRunnerKit --no-parallel
   python3 -m unittest discover -s scripts/tests
   swift scripts/generate-app-icons.swift
   xcodegen generate
   ```

4. Open `OctoRunner.xcodeproj` in Xcode. Select the **OctoRunner** scheme, **My Mac** destination, and **Debug** run configuration.
5. For a local run without a developer certificate, select **Sign to Run Locally** in the target’s **Signing & Capabilities** section if needed. Put persistent project settings in `project.yml` because `xcodegen generate` overwrites changes to the generated project.
6. Press **⌘R** to build and run. Press **⌘.** to stop the debugger session. Separately test the normal Quit dialog through **Quit** in the app.

Xcode runs the app in place from its build directory. Match secrets and notarization are unnecessary for this local run. [Apple’s documentation on ad hoc signing for Sign to Run Locally](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

**Debug and release builds share app data.** Both use the `io.octorunner.macos` bundle ID, SwiftData store, preferences, and Keychain service names. Runner actions and changes affect existing data. Use a separate macOS test account with its own test runners for an isolated run. The app has no sample data mode. The local signature may require separate Keychain or folder permissions, and the signed release needs its own permission checks.

### Build from Terminal

After generating the project, run the following command.

```sh
xcodebuild -project OctoRunner.xcodeproj \
  -scheme OctoRunner \
  -configuration Debug \
  -derivedDataPath DerivedData/Development \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build
```

Quit the installed app, then open `DerivedData/Development/Build/Products/Debug/OctoRunner.app` in Finder. Local ad hoc builds are for testing on the build Mac.

## 2. Run a signed release from GitHub

1. Download the desired `OctoRunner-<Version>-arm64.zip` from [GitHub Releases](https://github.com/loesch-digital/octorunner/releases). The release build requires Apple silicon and macOS 15 or later.
2. Extract the ZIP and fully quit any running OctoRunner instance.
3. Open the extracted app in Finder to test it in place. For normal installation, drag it to `/Applications`. If you later switch to Homebrew, account for the existing manual installation.
4. Check Developer ID approval. For an installed app, run this command.

   ```sh
   spctl --assess --type execute -vv /Applications/OctoRunner.app
   ```

The expected output is `accepted` with `source=Notarized Developer ID`. If the check rejects the app, investigate the cause with quarantine attributes and Gatekeeper in place.

### Update recovery

Use the [shared Homebrew tap](https://github.com/loesch-digital/homebrew-tap) or the signed ZIP for the first upgrade from v0.6 or earlier. The updater in the installed version controls how that upgrade is handled.

OctoRunner v0.7 and later keep the previous app bundle on the installation volume until the replacement reports that it opened the local database and finished launching. If startup fails, the installer restores the previous app and its SQLite database and sidecar files. This preserves the separately stored runner workspaces, logs, and LaunchAgent files. During installation, wait for OctoRunner to reopen automatically.

If OctoRunner asks for manual recovery, leave both bundles and the backup files in place. The update record is `~/Library/Application Support/io.octorunner.macos-update/pending.json`. The previous bundle may be in a hidden `.octorunner-update-*` folder beside the installed app. The SQLite backup is in a hidden `.octorunner-store-backup-*` folder beside `octorunner.store`. Copy these files to a safe location before repairing the installation or starting another version. [Report a recovery issue](https://github.com/loesch-digital/octorunner/issues).

For local acceptance, download the original v0.5.2 and v0.6.0 Apple Silicon ZIPs into the same test directory. This runs the actual signature and Gatekeeper checks and exercises replacement and simulated failed startup on disposable copies.

```sh
OCTORUNNER_SIGNED_UPDATE_FIXTURES=/path/to/releases \
  swift test --package-path Packages/OctoRunnerKit --no-parallel --filter AppUpdateRecoveryTests
```

## 3. Acceptance before release

Test the feature branch locally before merging and tagging a release. Record the commit, macOS version, Xcode version, and results. PR CI, main CI, and the signed release workflow must then pass. A final Homebrew upgrade verifies the additional distribution path.

Check these behaviors for the patch covered by this guide.

- Startup proceeds without a Documents access prompt. Select external runners through **Import Folder…** and open or refresh external logs explicitly.
- Select **Dashboard** at the top right of the menu bar popover several times, including while the window is minimized or closed. Exactly one dashboard should open.
- Closing the window leaves the menu bar item visible. Canceling **Quit** leaves the app running. Confirming **Quit** closes the app and removes its menu bar item.
- Runners with an installed LaunchAgent continue running. For imported runners that have yet to migrate, the Quit dialog explains the limitation.
- GitHub sign-in and runner management work with the required permissions. The app treats absent token scope headers as unknown permissions.

On November 11, 2026, the Debug build succeeded with the Terminal command above. For v0.4.4, 37 Swift tests, 9 Python tests, PR and main CI, the notarized release, the Homebrew upgrade, and Gatekeeper all passed. The user then confirmed that five Dashboard requests opened exactly one window, closing and reopening worked, **Quit** worked, a normal restart skipped the Documents prompt, and all three preview toggles were disabled. Live checks were still pending for a new external folder import and continued operation of specific runners. The computer control tool still returned `cgWindowNotFound`, and the Xcode connector awaited permission through its menu bar icon. The CLI result verified the build, and the user supplied the interactive results.

## Refresh the public dashboard screenshot

After changing the dashboard, regenerate its screenshot from the app’s SwiftUI preview with example data. Run this from the repository root on macOS:

```sh
OCTORUNNER_DASHBOARD_SCREENSHOT="$PWD/docs/assets/app-screens/dashboard.png" \
  swift test --package-path Packages/OctoRunnerKit --no-parallel --filter DashboardScreenshotTests
```

Review the image and commit it with the dashboard change. The README references that PNG directly. GitHub Pages stages the same PNG and redeploys when it changes. To preview the published layout locally, run `python3 scripts/stage-website.py <new-output-directory>` and serve that directory.
