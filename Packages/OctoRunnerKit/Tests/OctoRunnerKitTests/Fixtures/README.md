# Legacy persistence fixture

`v0_4.store` is a real SwiftData SQLite store generated before extending the jobs
schema, using the CoreModels sources at commit `83aaa4221e6bbb7901af05d7ef5fc13c7d4da9d5`.
It contains one synthetic account, runner, workflow run and audit entry, including
the runner-to-job inverse relationship. There are no credentials or user data.

JobRunEntity source SHA-256 at generation:
`efe56f162784e6910b27d1eaad54a64454921ffce37de069cbe937af389c8ab4`.

Fixture SHA-256: `4b729fa6951e527b83e8659133af09901753314403e65478fd4f6782ef015356`.

To regenerate, use a separate checkout of that revision, copy
`LegacyFixtureGenerator.swift` into its test target and run:

```sh
OCTORUNNER_LEGACY_FIXTURE_DIR=/tmp/octorunner-legacy-new swift test --package-path Packages/OctoRunnerKit --no-parallel
sqlite3 /tmp/octorunner-legacy-new/v0_4.store 'PRAGMA wal_checkpoint(TRUNCATE);'
```

Copy only the checkpointed `.store` file after the Swift test process has exited.
The generator deliberately refuses to use an extended JobRunEntity schema.
Migration tests copy this fixture to an isolated directory and open it directly
with `ModelContainer`; they must never use the store deletion/self-healing helper.
This tests migration from the v0.4 schema, not from every historical release or
across every supported macOS runtime.
