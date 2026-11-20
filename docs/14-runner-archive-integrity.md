# Runner Archive Integrity

This guide records the v0.5.0 feature branch before release.

OctoRunner requires a valid SHA-256 checksum before using an archive. Empty or malformed checksums fail verification. The app verifies the bytes of cached files and new downloads. It hashes blocks of up to 64 KiB and checks for task cancellation between blocks.

The app determines the expected checksum as follows.

1. Download metadata must identify an official macOS ARM64 archive at `github.com/actions/runner/releases/download/<Tag>/<Filename>`. The app rejects unexpected path components, external destinations, URL credentials, and query parameters.
2. If the metadata includes a valid `sha256_checksum`, use it.
3. If the checksum is missing, fetch the exact public release from `api.github.com/repos/actions/runner/releases/tags/<Tag>`. The request is anonymous and requires no additional OAuth permissions.
4. Check that the release tag, stable publication status, asset name, download URL, and asset state match. Require exactly one matching asset with a valid `sha256:` digest. Cache successful resolutions in a bounded in-memory cache.

Missing, inconsistent, or unreachable metadata stops setup before installation. Verification trusts the GitHub API over TLS and the official `actions/runner` release data. It provides no independent publisher attestation.

A corrupt download leaves the existing cache entry intact. Temporary files are cleaned up after verification. Error messages omit private transport diagnostics and download URLs that could contain temporary credentials after a redirect.

## Verification

Tests use independent SHA-256 vectors (`abc` and one million `a` characters), controlled HTTP metadata, and a real local HTTP server for successful, corrupt, and failed downloads. They cover missing checksums, path and URL restrictions, anonymous requests, incorrect releases, duplicate assets, rate-limit and HTTP errors, and late responses after cancellation. Tests use only synthetic credentials.

At this stage, protecting managed directories against symlinks and concurrent file system changes remained part of the storage and pruning work. Archive verification addresses the archive's content. [Runner download API](https://docs.github.com/en/rest/actions/self-hosted-runners) · [Release and asset metadata](https://docs.github.com/en/rest/releases/releases)
