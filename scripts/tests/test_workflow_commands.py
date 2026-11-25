"""Execute workflow shell blocks with local boundary stubs; no GitHub writes."""
import os
import re
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]


def workflow_run(workflow, step):
    source = (ROOT / ".github/workflows" / workflow).read_text()
    block = source.split(f"      - name: {step}\n", 1)[1].split("\n      - name:", 1)[0]
    lines = block.split("        run: |\n", 1)[1].splitlines()
    shell = []
    for line in lines:
        if line.strip() and not line.startswith("          "):
            break
        shell.append(line)
    return textwrap.dedent("\n".join(shell))


class WorkflowCommandTests(unittest.TestCase):
    def test_homebrew_publishers_only_stage_the_octorunner_cask(self):
        workflow = workflow_run("release.yml", "Update Homebrew Tap (loesch-digital/tap)")
        script = (ROOT / "scripts/update-homebrew-cask.sh").read_text()
        for publisher in (workflow, script):
            with self.subTest(publisher=publisher.splitlines()[0]):
                self.assertIn("loesch-digital/homebrew-tap", publisher)
                self.assertEqual(re.findall(r"^git add (.+)$", publisher, re.MULTILINE),
                                 ["Casks/octorunner.rb"])
                self.assertNotIn("README.md", publisher)
                self.assertIn('scripts/release_tools.py cask "v${VERSION}" "${SHA256}"', publisher)
                self.assertNotIn('cask "octorunner" do', publisher)

    def test_build_workflows_use_the_same_current_toolchain(self):
        for workflow in ("ci.yml", "release.yml"):
            with self.subTest(workflow=workflow):
                source = (ROOT / ".github/workflows" / workflow).read_text()
                self.assertEqual(re.findall(r"^    runs-on: (xcode-.+)$", source, re.MULTILINE), ["xcode-27"])
                self.assertIn("DEVELOPER_DIR: /Applications/Xcode_27.2.app/Contents/Developer", source)
                self.assertNotIn("matrix.", source)

    def test_ci_skips_the_mac_build_only_for_website_changes(self):
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("- name: Detect website-only changes\n", source)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*arguments):
                return subprocess.check_output(["git", *arguments], cwd=root, text=True).strip()

            git("init", "--quiet")
            git("config", "user.name", "Workflow Test")
            git("config", "user.email", "workflow@example.test")
            git("commit", "--quiet", "--allow-empty", "-m", "Base")
            base = git("rev-parse", "HEAD")
            output = root / "outputs"
            for paths, expected in [
                (["website/index.html", ".github/workflows/website.yml"], "true"),
                (["website/style.css", "App/OctoRunnerApp.swift"], "false"),
            ]:
                with self.subTest(paths=paths):
                    for name in paths:
                        path = root / name
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text("change")
                        git("add", name)
                    git("commit", "--quiet", "-m", "Update files")
                    output.write_text("")
                    result = subprocess.run(
                        ["bash", "-euo", "pipefail", "-c", workflow_run("ci.yml", "Detect website-only changes")],
                        cwd=root, env={**os.environ, "BASE_SHA": base, "GITHUB_SHA": git("rev-parse", "HEAD"),
                                       "GITHUB_OUTPUT": str(output)}, capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_text(), f"website_only={expected}\n")

    def run_step(self, workflow, step, command, stub, extra_env=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / command
            executable.write_text("#!/usr/bin/env bash\n" + stub)
            executable.chmod(0o755)
            # Other commands in the generation block are irrelevant boundaries here.
            for name in ("swift", "xcodegen"):
                (root / name).write_text("#!/bin/sh\nexit 0\n")
                (root / name).chmod(0o755)
            return subprocess.run(
                ["bash", "-euo", "pipefail", "-c", workflow_run(workflow, step)],
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}", **(extra_env or {})},
                capture_output=True, text=True,
            )

    def test_installed_xcodegen_probe_is_silent_in_both_workflows(self):
        for workflow in ("ci.yml", "release.yml"):
            with self.subTest(workflow=workflow):
                result = self.run_step(workflow, "Generate App Icons & Xcode Project", "brew",
                                       'echo /opt/homebrew/Cellar/xcodegen\necho probe-warning >&2\nexit 0\n')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "")

    def test_missing_xcodegen_is_installed_and_install_failure_stops_build(self):
        result = self.run_step("ci.yml", "Generate App Icons & Xcode Project", "brew",
                               'if [[ "$1" == list ]]; then exit 1; fi\necho install-failed >&2\nexit 7\n')
        self.assertEqual(result.returncode, 7)
        self.assertIn("install-failed", result.stderr)

    def test_release_workflow_extracts_beta_distribution_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", workflow_run("release.yml", "Extract Release Version from Git Tag")],
                cwd=ROOT, env={**os.environ, "GITHUB_REF_NAME": "v0.5.0-beta.1", "GITHUB_OUTPUT": str(output)},
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            values = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(values.get("bundle_version"), "0.5.0")
            self.assertEqual(values.get("update_homebrew"), "false")

    def test_published_release_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "release.zip"
            archive.write_bytes(b"synthetic archive")
            result = self.run_step("release.yml", "Publish New GitHub Release", "gh", '''
case "$2" in
  view) exit 0 ;;
  upload) echo archive-overwritten; exit 0 ;;
  create) echo release-already-exists >&2; exit 1 ;;
esac
''', {"TAG": "v0.4.3", "VERSION": "0.4.3", "ZIP_PATH": str(archive)})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release-already-exists", result.stderr)
            self.assertNotIn("archive-overwritten", result.stdout)


if __name__ == "__main__":
    unittest.main()
