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
    def test_build_workflows_use_the_same_current_toolchain(self):
        for workflow in ("ci.yml", "release.yml"):
            with self.subTest(workflow=workflow):
                source = (ROOT / ".github/workflows" / workflow).read_text()
                self.assertEqual(re.findall(r"^    runs-on: (.+)$", source, re.MULTILINE), ["xcode-27"])
                self.assertIn("DEVELOPER_DIR: /Applications/Xcode_27.2.app/Contents/Developer", source)
                self.assertNotIn("matrix.", source)

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

    def test_published_release_cannot_be_overwritten(self):
        result = self.run_step("release.yml", "Publish New GitHub Release", "gh", '''
case "$2" in
  view) exit 0 ;;
  upload) echo archive-overwritten; exit 0 ;;
  create) echo release-already-exists >&2; exit 1 ;;
esac
''', {"TAG": "v0.4.3", "VERSION": "0.4.3", "ZIP_PATH": "release.zip"})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("archive-overwritten", result.stdout)


if __name__ == "__main__":
    unittest.main()
