# Host Telemetry Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task with Red → Green → Refactor.

**Goal:** Deliver the working hardware and runner-process monitor from docs/07 and screenshot 09.
**Architecture:** Keep sampling in TelemetryKit actors and pass Sendable values to a resizable SwiftUI dashboard. Use existing CPU/RAM sampling and volume-capacity APIs. Add device I/O counters via IOKit; show scope explicitly (host devices, not invented per-APFS-volume throughput). Keep GitHub header observations scoped by account and show their age. Runner process metadata excludes arguments and environment variables.
**Tech stack:** macOS 15+, Swift 6 strict concurrency, SwiftUI, IOKit, libproc, existing SwiftData queries.
**Spec:** docs/07-step-05-settings-telemetry-and-jobs.md §3, docs/assets/screens/09_host_telemetry.png; existing user authorization to continue implementation.

## Global constraints
- Keep deployment target and dependencies unchanged. Existing feature branch workflow, CI gates and four repo skills apply.
- No Documents/home-folder enumeration or automatic diagnostics export. No credentials in telemetry.
- Report missing readings as unavailable. Core counts do not establish a reliable CPU-index mapping; never fabricate E/P load percentages.
- Thermal state and memory pressure are distinct. Use the memory-pressure sysctl for the latter and retain unknown if unsupported.
- Native adaptive cards and scrolling replace fixed screenshot dimensions. Controls receive DE/EN labels and hints.

## Review focus
- I/O counters decrease or devices disappear: reset baseline, never display negative or enormous throughput.
- Initial/missing samples: unavailable rather than zero; monotonic uptime for rate deltas.
- Account changes: never display a different account's API quota.
- Runner processes exit/PIDs are reused: inspect fresh identity before any signal; refuse changed identity or attribution.
- Closing/changing screen: cancel periodic work and avoid SwiftData access after cancellation.

### Task 1: Measured host cards and navigation
- [x] Add failing tests for device-counter deltas (initial sample, reset, invalid elapsed time), rate-header account isolation and rendered dashboard at 680/1100 points in Light/Dark and DE/EN.
- [x] Add HostDiskIOSample/Snapshot, sampler protocol and SystemHostDiskIOSampler with IOKit registry ownership balanced. Actor computes rates using monotonic uptime and independent device identities.
- [x] Add HostTelemetryDashboardView, adaptive CPU/memory/storage/API cards, interval picker and manual refresh through .task(id:), sidebar navigation.
- [x] Preserve observed API headers in WorkflowHistoryRateBudget when a current history response arrives; use no extra polling requests just for telemetry.
- [x] Full Swift/Python tests, local build, review, PR CI, merge, main CI.

### Task 2: Runner process inspector
- [x] Red tests for process tree association, malformed/missing process samples, duplicate runner roots, unrelated services, PID reuse and cancellation.
- [x] Add libproc metadata sampler and Sendable identities, CPU deltas and runner-descendant association. No process command arguments.
- [x] Add runner filter, process rows and detailed read-only sheet. SIGTERM requires confirmation and fresh identity/ancestry checks; record audit outcome without arguments.
- [x] Full tests, native UI coverage, review and both CI gates before merge (PR #25; main CI 43457564239).

### Task 3: Telemetry acceptance and documentation
- [x] Compare to screenshot 09, document factual departures (no fake per-app RAM/cache totals, no fabricated 60-Hz IPC watchdog or CoreSimulator attribution).
- [x] Verify public Apple API support and degradation on unsupported systems; document scope and remaining v0.5 work.

### Task 4: Memory pressure and thermal state

**Spec:** docs/07 §3 and the global constraints above. Existing authorization to continue the plan covers these measurements and the established adaptive cards.
**Interfaces:** Add optional `HostMemoryPressure` and `HostThermalState` to HostTelemetrySample/Snapshot; SystemHostTelemetrySampler reads sysctl/ProcessInfo, HostTelemetryActor carries the current sample. HostTelemetryCards localizes both independently.
**Files:** TelemetryKit host sample/snapshot/actor/system sampler, new enum files, telemetry cards/string catalog, TelemetryKitTests/HostTelemetryDashboardTests/native HostTelemetryUITests.
**Review focus:** sysctl exposes dispatch flags 1/2/4, not internal pressure levels 0/1/3; unknown or denied reads stay unavailable; thermal state never substitutes for pressure; each refresh replaces stale state; text works at narrow/wide sizes in DE/EN and Light/Dark. No pressure/thermal stress is generated on the real host.

- [x] Add red tests for sysctl-flag decoding, independent thermal mapping and snapshot transitions including unavailable readings. Run `swift test --package-path Packages/OctoRunnerKit --no-parallel`; expect new API missing until implemented.
- [x] Implement failable raw enums, read-only sysctl with exact byte-size validation and ProcessInfo thermalState mapping; add optional DTO fields with nil defaults and propagate each fresh sample.
- [x] Add localized text rows in CPU/memory cards; extend NSHostingView fixtures and native UI assertions. Existing polling/cancellation stays unchanged.
- [ ] Run full Swift/Python tests and local app build; inspect layout captures, review, commit/PR, wait for PR CI, merge and wait for main CI. Expected all checks green.
