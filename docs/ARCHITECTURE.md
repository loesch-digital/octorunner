# OctoRunner architecture

OctoRunner is a SwiftUI and SwiftData macOS app for Apple Silicon and macOS 15 or later. XcodeGen generates the native project from [project.yml](../project.yml). The app and its local Swift package use Swift 6.

## Modules

| Module | Responsibilities |
| --- | --- |
| `App` | macOS scenes, app lifecycle, service composition, and update handoff at launch. |
| `AppShellFeature` | Dashboard, runner dialogs, Jobs & Workflow Runs, Settings, menu bar, telemetry, and audit UI. |
| `DesignSystem` | Shared theme, typography, and interface components. |
| `CoreModels` | SwiftData entities, migrations, preferences, and shared types. |
| `SecurityKit` | Credential storage in the macOS Keychain. |
| `GitHubAPI` | GitHub authentication, REST clients, and application update checks and installation. |
| `RunnerEngine` | Runner provisioning, process supervision, LaunchAgents, logs, and storage maintenance. |
| `SyncKit` | Local runner discovery and reconciliation with GitHub. |
| `TelemetryKit` | Host and process measurements. |

[Swift package manifest](../Packages/OctoRunnerKit/Package.swift)

## Runtime boundaries

- UI and SwiftData view contexts are main-actor isolated. Asynchronous runner, network, and telemetry work crosses module boundaries through explicit values and actor APIs.
- Directly managed runners run as owned process groups. A user LaunchAgent can run without the UI. Imported external runners remain outside process supervision until migrated.
- GitHub account credentials live in Keychain. The selected account governs GitHub requests and the associated history.
- The host grants access to external runner folders during explicit user selection. Update installation validates the signed app and protects the local store before replacing the bundle.

[Architecture decisions and original module specification](01-architecture-and-modules.md#4-architecture-decision-records-adrs) · [Development and acceptance](10-development-and-acceptance.md) · [Release signing](release-signing.md)
