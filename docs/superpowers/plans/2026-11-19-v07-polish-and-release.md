# v0.7 Polish and Final Planned Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use the existing authorization to continue with native implementation.

**Goal** — Ship v0.7.0 with accessible, consistently localized dialogs and verify the update path with real releases.

**Architecture** — Run acceptance checks on existing functionality. Make update failures and rollback states verifiable. Limit new functionality to the explicitly approved scope.

**Tech stack** — Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement, and the existing Python and GitHub Actions tools.

**Spec** — `docs/02-design-system-and-hig.md`, screens 01–09, `docs/10-development-and-acceptance.md`, `docs/release-signing.md`, and the user-approved v0.7 scope. The November 19, 2026 scope decision places the global concurrency limit in v0.6.

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

1. Keep controls reachable with long German strings and many runners (Task 1).
2. Make features available via VoiceOver and the keyboard, with alternatives to color and hover (Task 1).
3. Distinguish missing permissions, network access, or runners from success and a fresh installation (Task 2).
4. Preserve the working installation if the update is corrupt (Task 2).
5. Verify first launch after an update with an older store and handle rollback if launch fails (Task 2).

### Task 1: Localization, Layout, and Accessibility

**Files** — `AppShellFeature/Resources/Localizable.xcstrings`, the affected views and OctoTheme, the existing `ResponsiveLayoutTests.swift`, `AppShellUITests.swift`, and `RunnerStatusColorTests.swift`, and targeted accessibility tests in the existing test target.

**Interfaces** — Use shared status labels and show availability separately from the latest job result. Running is blue in the app and menu. Guard against regressions in SwiftUI menu bar invalidation.

- [ ] Compare each dialog with screens 01–09 and document how its features correspond to the designs. Check the string catalog for missing German and English strings and pluralization and formatting errors.
- [ ] For each gap, start with a failing test and apply a targeted fix. Cover long names and labels, many wizard runners, narrow and wide windows, Settings search, and empty, error, and loaded states.
- [ ] Verify VoiceOver reading order, focus, keyboard actions, and contrast in Light and Dark appearances. Provide status cues in addition to color. Use NSHostingView checks alongside manual VoiceOver acceptance.
- [ ] Pass tests and build, review, commit, and pass both CI gates.

### Task 2: Error Handling and Update Rollback

**Files** — `GitHubAPI/AppUpdaterActor.swift`, the associated UI and update installer, `OctoRunnerPersistence.swift`, the existing `AppUpdatePrereleaseTests.swift`, and a new `AppUpdateRecoveryTests.swift` in the test target.

**Interfaces** — Expose checking, downloading, validating, installing, restarting, failed, and recovering states. Keep the last working installation until the replacement has been installed and validated. Keep secrets out of the update state and access folders only as needed.

- [ ] Add failing tests for a corrupt archive, missing write permissions, mismatched app identity, interrupted replacement, failed launch, and an existing SQLite store. Document recovery limits for production stores.
- [ ] Add safe staging, validation, and rollback. Verify version, signatures, Gatekeeper, atomic file replacement where supported, and the recovery state after process exit.
- [ ] Test update initiation and rollback from an existing signed release in a separate test installation. Use disposable fixtures. If a schema upgrade is irreversible, define the backup and recovery behavior before migrating the store.
- [ ] Pass tests, review, commit, and pass both CI gates.

### Task 3: Documentation and v0.7.0

**Files** — `README.md`, `LICENSE`, `docs/README.md`, `docs/18-remaining-delivery-plan.md`, `docs/assets/screens/`, and `docs/releases/v0.7.0.md`.

**Interfaces** — Use verified v0.6 and the results of Tasks 1 and 2 to deliver current public documentation and an immutable signed release.

- [ ] Write the public `README.md` in US English. Follow the structure and clarity of [Podman Desktop](https://github.com/podman-desktop/podman-desktop) with the product name, a brief description, an actual app screenshot near the top, clear navigation, and screenshots for relevant features. Describe only shipped features as available.
- [ ] Provide verified copy-and-paste Homebrew tap and cask commands and instructions for installing the signed release ZIP. Explain macOS and architecture requirements, updates, and first launch. Follow the standard Gatekeeper flow.
- [ ] Write a quick start for connecting GitHub, granting the minimum permissions for each feature, adding or importing a runner, setting workflow `runs-on` labels, and viewing runner status and jobs. Explain GUI and LaunchAgent lifetimes and the limits of restarts and concurrency.
- [ ] Document development acceptance without Homebrew using Xcode and the existing local launch scripts. Include requirements and verified build and test commands. Link the detailed developer and architecture documentation from the README.
- [ ] Capture current app screenshots of the dashboard, runner wizard, details and logs, jobs and workflows, and settings. Keep tokens and private data out of screenshots. Use the mockups in `docs/assets/screens/` as design references. Give images US English alt text, working relative links, and appropriate dimensions.
- [ ] Add verified CI and release badges and links for releases, support, and licensing where they exist. Publish a single US English README and use Apache-2.0 for the project license. Check all links, Homebrew and ZIP steps, and image files before release.
- [ ] Bring `docs/README.md`, the delivery plan, and release notes up to the verified feature state. Use US English for all public-facing material, including release notes.
- [ ] Run the full tests and native build and wait for PR and main CI to pass. Run `npx release-it 0.7.0 --ci`, then verify the release run, Homebrew installation, app launch, and Gatekeeper.
- [ ] Provide a German completion summary for the user with open limitations and up to three manual checks.
- [ ] **Stop after v0.7.0.** Ask the user whether and when to release v1.0.0. Wait for their decision before tagging v1.0.0 or continuing.
