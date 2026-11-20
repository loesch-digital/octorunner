# Host Telemetry

> **Scope updated November 19, 2026.** The global runner concurrency limit moved to v0.6 by user decision. References to v0.5 for that work are historical. [Remaining delivery plan](./18-remaining-delivery-plan.md)

Select **Host Telemetry** in the sidebar to see available local measurements. The view refreshes every 1, 5, or 15 seconds while open. **Refresh telemetry** takes a new measurement. Leaving the view stops its periodic measurements.

- **CPU** shows total utilization from two Mach counter readings and the detected performance and efficiency core counts. The first reading needs a second sample before utilization can be calculated. Per-type utilization requires a verified mapping of CPU indices and is unavailable here.
- **Memory** shows total physical memory, memory in use, and app, wired, and compressed memory from host-wide VM statistics. The card excludes file system caches as a RAM category. An unknown measurement appears as a dash.
- **Storage and I/O** shows available and total capacity on the user volume. Read and write throughput uses the host's available `IOBlockStorageDriver` statistics across block devices. The calculation handles new devices, missing samples, and counter resets without reporting artificial spikes. Analyze cache sizes in **Settings → Cache & Storage**.
- **GitHub API** shows the last rate-limit headers observed by Jobs for the active account, including measurement age and reset time. Switching accounts shows only the selected account's observation. Refresh Jobs to update the measurement. Host Telemetry uses no additional GitHub API requests. Older responses cannot overwrite newer observations.

Queries read system counters, device metadata, and volume capacity. They leave Documents and runner work directories untouched. An unavailable reading stays unknown.

The cards follow the main sections of the mockup and adapt to the window width. The per-runner process inspector is included at this point in v0.5.0 development. [Screenshot 09](./assets/screens/09_host_telemetry.png)

## Verification

Unit tests cover device deltas, device additions and removals, counter resets, missing samples, and time baselines. Other tests verify that Jobs supplies actual API headers and that account observations stay isolated. NSHostingView renders cover available and missing values in narrow and wide layouts, in German and English and Light and Dark appearances. A native UI test checks navigation, measurement cards, and refresh. [Apple's IOBlockStorageDriver statistics](https://developer.apple.com/documentation/iokit/ioblockstoragedriver_h_user-space/defines) · [Apple's system capabilities documentation](https://developer.apple.com/documentation/kernel/1387446-sysctlbyname/determining_system_capabilities)

## Per-Runner Process Inspector

Below the host cards, **Processes by Runner** lists uniquely matched `Runner.Listener` and `Runner.Worker` processes and their identifiable child processes under the same macOS user. Use the dropdown to filter by runner. PID, process name, runner, CPU, resident memory, and uptime refresh at the selected interval. **Details** opens a snapshot with the start time, parent PID, user ID, executable, and measurement time.

CPU utilization uses two cumulative libproc samples and monotonic elapsed time. The app converts Mach ticks to seconds with `mach_timebase_info`. A fully utilized core is 100%, so values can exceed 100%. A dash indicates the first sample, missing counters, a reused PID, or a counter reset. Matching excludes unreadable or missing processes, incomplete parent chains, other users' processes, and duplicate runner paths. The inspector reads process metadata without process arguments, environment variables, or runner directory scans.

**Terminate…** asks you to confirm the process, PID, runner, and effect on active jobs. The app then checks the current process tree, PID and start time, user, executable, and parent PID again. It sends only `SIGTERM` to that individual process. The app excludes its own GUI PID and system PIDs. The POSIX API can only address a PID, so a small race remains between the last identity check and the signal.

The app records the intent in the audit log before requesting termination. It then records **Process termination signal sent** or **Process termination refused or failed**. An interrupted request may leave only the intent entry. A successfully sent signal records delivery of the request. The process can still be running, and a LaunchAgent can restart it. Canceling the view stops further SwiftData access.

### Comparison With Screenshot 09

The process list implements the main functions with native rows that wrap as needed. A `CoreSimulatorService` appears only if its actual parent chain proves the association. A service reparented to `launchd` may therefore be absent. The app reports verified processes, core counts, and VM categories. It uses public libproc and Darwin interfaces for process metadata and signals under the existing GitHub permissions.

On November 19, 2026, the global runner concurrency limit moved to v0.6 alongside start, stop, restart, and crash and KeepAlive policies. v0.5 follows the updated acceptance plan.

### Technical References and Tests

- Public process metadata calls. [Apple's libproc interface](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h)
- Cumulative user and system time from `recount_times_mach` and resident memory. [Apple XNU's `fill_taskprocinfo`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c)
- Unit tests cover unique matches, unrelated and other users' processes, duplicate roots and PIDs, cyclic parent chains, start time verification, CPU deltas and resets, changed identity or association before SIGTERM, and cancellation.
- Native libproc and SIGTERM tests use only a dedicated process created by the test.
- NSHostingView tests cover empty and populated lists and the detail view at 680 and 1,100 points, in German and English and Light and Dark appearances. CI also runs native UI tests for navigation and the runner dropdown.

## Memory Pressure and Thermal State

The memory card shows current **Memory pressure** (Normal, Elevated, or Critical). The CPU card shows **Thermal state** (Normal, Slightly elevated, High, or Critical). Both refresh at the selected interval and on manual refresh. A failed or unknown reading replaces the prior value with **Unavailable**. Memory pressure comes from its own system reading.

The read-only sysctl `kern.memorystatus_vm_pressure_level` provides Dispatch flags **1, 2, and 4**. Missing, denied, incorrectly sized, and unknown future values remain unknown. Thermal state comes from `ProcessInfo.thermalState`, a system-wide stress level. These checks use public interfaces and require no settings changes or additional permissions. [Apple XNU's sysctl output and Dispatch mapping](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c) · [Apple's ProcessInfo.ThermalState documentation](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)

Tests cover level mapping, independent readings, missing and unknown follow-up readings, and localized labels. NSHostingView renders cover elevated and unavailable states at 680 and 1,100 points, in German and English and Light and Dark appearances. Native CI checks both status rows. Tests simulate pressure and thermal states.
