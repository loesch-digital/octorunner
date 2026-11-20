# Cache & Storage for v0.5.0

Add a sixth tab to the existing Settings navigation using the approved card
layout. Apply the persisted StoragePolicy values to storage operations.

1. Start with failing tab and search tests. Use only temporary fixture
   directories for cleaner tests.
2. Have WorkspaceCleanerActor measure logical file sizes for workspaces,
   actions, temporary files, and diagnostic logs. Report these as logical sizes
   since APFS can share blocks.
3. Limit cleanup to direct runner subdirectories of the managed Application
   Support directory. Exclude imported folders, symlinks, and external host
   caches. Keep at least the newest diagnostic log. Protect reserved tools,
   runner configuration, and binaries.
4. Before deleting any file, recheck its identity and age, verify that there are
   no listeners or workers, and confirm that the LaunchAgent is unloaded.
   Require a known process and agent state in addition to IDLE. Stop making
   changes on cancellation.
5. In Settings, let the user start analysis, see measured sizes by category and
   volume, preview and confirm cleanup, and see errors and audit entries.
   Default to manual cleanup. Explicit automatic policies apply only to the
   managed paths. Access Documents only when a specific operation requires it.
6. Verify German and English, accessibility, and NSHostingView rendering at
   narrow and wide sizes in Light and Dark appearances. Update native category
   tests for the sixth tab. Run Swift and Python tests, build, get a review,
   wait for PR CI to pass, merge, and verify CI on main.

Global DerivedData and host caches can be in use by other Xcode processes.
Keep them outside automatic cleanup. The future engine must coordinate startup
with cleanup. The current cleaner requires the runner to be unloaded and free
of running processes.

## Verification Results

- The tab and search tests started red with three expectations, and the cleaner
  tests started red with six expectations.
- A cleaner regression test reproduced a file changing during the second state
  check. The fix rechecks the file synchronously after the await.
- Review identified symlink ancestors, canonical service names, and auditing
  after partial cancellation. Regression tests for all three ran before the
  fixes. POSIX lstat follows a link when the path ends in a slash. The metadata
  check removes that trailing slash.
- Global host caches stay outside cleanup because process ownership is unknown
  and cleaning them could disrupt unrelated builds. This boundary is documented
  in docs/15.
- Persist an audit entry recording intent before any cleanup can begin. The
  completion entry confirms the counts. Cancellation invalidates the preview
  without accessing the model after cancellation. Counts are indeterminate when
  cleanup is interrupted partway through.
- Local verification passed for 255 Swift tests across 54 suites with code
  coverage, 18 Python tests, and the Xcode debug build. Line coverage was 98.1%
  for the cleaner, 100% for state checking, and 72.3% for the controller. The
  10-minute lifecycle and some interactive sheet paths still lack full
  automated coverage.
- Reviewed Settings screenshots in German and English, at 620 and 960 points,
  and in Light and Dark appearances. The existing card structure and all six
  visible categories are present. PR CI also runs native category selection
  tests that include Storage.
