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
- [ ] Add failing tests for device-counter deltas (initial sample, reset, invalid elapsed time), rate-header account isolation and rendered dashboard at 680/1100 points in Light/Dark and DE/EN.
- [ ] Add HostDiskIOSample/Snapshot, sampler protocol and SystemHostDiskIOSampler with IOKit registry ownership balanced. Actor computes rates using monotonic uptime and independent device identities.
- [ ] Add HostTelemetryDashboardView, adaptive CPU/memory/storage/API cards, interval picker and manual refresh through .task(id:), sidebar navigation.
- [ ] Preserve observed API headers in WorkflowHistoryRateBudget when a current history response arrives; use no extra polling requests just for telemetry.
- [ ] Full Swift/Python tests, local build, review, PR CI, merge, main CI.

### Task 2: Runner process inspector
- [ ] Red tests for process tree association, malformed/missing process samples, duplicate runner roots, unrelated services, PID reuse and cancellation.
- [ ] Add libproc metadata sampler and Sendable identities, CPU deltas and runner-descendant association. No process command arguments.
- [ ] Add runner filter, process rows and detailed read-only sheet. SIGTERM requires confirmation and fresh identity/ancestry checks; record audit outcome without arguments.
- [ ] Full tests, native UI coverage, review and both CI gates before merge.

### Task 3: Telemetry acceptance and documentation
- [ ] Compare to screenshot 09, document factual departures (no fake per-app RAM/cache totals, no fabricated 60-Hz IPC watchdog or CoreSimulator attribution).
- [ ] Verify public Apple API support and degradation on unsupported systems; document scope and remaining v0.5 work.
