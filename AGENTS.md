# Project Rules & Workflow Guidelines (`octorunner`)

These rules apply permanently to all agents working in `/Users/frank/Documents/apps/octorunner`:

## 1. Git Branching, Worktrees & Commit Discipline
- **Feature Branches & Worktrees:** Never develop features directly on `main`. Always develop each feature/milestone on a dedicated feature branch (e.g. `feat/step-01-infrastructure`, `feat/step-02-github-auth`) or isolated git worktree (`git worktree` / subagent `Workspace: "share"` or `"branch"`).
- **Frequent Commits & Pushes:** Commit and push progress regularly after logical sub-steps using semantic commit messages (`feat:`, `fix:`, `docs:`, `chore:`).
- **Pull Requests, Merging & Automated Releases:** Always open a GitHub Pull Request (`gh pr create`) to merge feature branches into `main` (`gh pr merge --merge --delete-branch`) so `main` is always the consolidated, verified state. Creating/pushing a release tag `v*` on `main` (via GitHub UI, `git tag v0.X.0 && git push origin v0.X.0`, or `npx release-it`) automatically triggers `.github/workflows/release.yml`, which builds `OctoRunner.app`, publishes the GitHub Release, and updates the Homebrew Tap (`loesch-digital/homebrew-octorunner`).

## 2. Critical Thinking & Architecture Validation
- Always question and verify technical assumptions from mockups/specs before implementing them (see `docs/01-architecture-and-modules.md` § 4 ADRs).
- Do not blindly use legacy or mismatched APIs just because a screenshot label mentions them (e.g., use direct Swift 6 Actor process supervision + `SMAppService.mainApp` instead of writing dynamic plists into a signed app bundle).

## 3. Mandatory Agent Skills
Before writing or reviewing code in their respective domains, follow the guidelines in:
- `.agents/skills/swiftui-pro/SKILL.md`
- `.agents/skills/swift-security-expert/SKILL.md`
- `.agents/skills/swiftdata-pro/SKILL.md`
- `.agents/skills/swift-concurrency-pro/SKILL.md`

## 4. Visual Assets & Icons
- Ensure all app icons (`AppIcon.appiconset` and `docs/assets/app_icon.png`) maintain a 100% transparent RGBA background (`hasAlpha: yes`) without white borders, and use vector SVGs (`menubar_icon.svg`) or `scripts/generate-app-icons.swift` for multi-resolution scaling.

## 5. TDD, CI/CD & Latest Versions Policy
- **Strict Latest Versions Only:** Never hardcode outdated versions from memory. Always verify and use the latest available versions (e.g., `Xcode 27.2`, `Swift 6.4`, `release-it ^21.1.2`, `actions/checkout@v7`).
- **Test-Driven Development (Strict Red → Green → Refactor):** For every new feature, module, or bugfix, always write or update the failing unit/UI test first (`swift test` → Red), then implement the production code until the test passes (`swift test` → Green), covering models, actors, security/keychain, UI layout (`NSHostingView`), and API decoding before merging and releasing.
- **CI/CD Verification:** Every push and merge must pass the GitHub Actions CI pipeline (`.github/workflows/ci.yml`).

