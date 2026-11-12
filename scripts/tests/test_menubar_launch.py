"""A real MenuBarExtra scene must return control to the main run loop at startup."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MenuBarLaunchTests(unittest.TestCase):
    def test_production_label_does_not_block_scene_startup(self):
        with tempfile.TemporaryDirectory(prefix='octorunner-menu-probe-') as directory:
            root = Path(directory)
            executable = root / 'MenuBarLaunchProbe'
            compile_result = subprocess.run([
                'xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                str(ROOT / 'scripts/tests/fixtures/MenuBarLaunchProbe.swift'),
                str(ROOT / 'Packages/OctoRunnerKit/Sources/AppShellFeature/RunnerMenuBarLabel.swift'),
                '-o', str(executable)
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            heartbeat = root / 'heartbeat'
            try:
                launched = subprocess.run([str(executable), str(heartbeat)],
                    capture_output=True, text=True, timeout=8)
            except subprocess.TimeoutExpired:
                self.fail('MenuBarExtra blocked the main thread: no startup heartbeat within 8 seconds')
            self.assertEqual(launched.returncode, 0, launched.stderr)
            self.assertEqual(heartbeat.read_text(), 'responsive')
