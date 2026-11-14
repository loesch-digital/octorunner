"""Exercise the watchdog with private subprocess fixtures, never existing runners."""
import os
import select
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/run-swift-tests.py"


class SwiftTestWatchdogTests(unittest.TestCase):
    def invoke(self, source, directory, idle="0.4", total="5"):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--diagnostics", str(directory / "diagnostics"),
             "--idle-timeout", idle, "--timeout", total, "--", sys.executable, "-u", "-c", source],
            capture_output=True, text=True, timeout=12,
            env={**os.environ, "PATH": f"{directory}:{os.environ['PATH']}"},
        )

    def test_streams_output_and_preserves_success_and_failure(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            for code in (0, 7):
                result = self.invoke(f"print('fixture output'); raise SystemExit({code})", directory)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertIn("fixture output", result.stdout)

    def test_idle_test_is_sampled_and_private_group_is_stopped(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            # Stub only the OS sampling boundary; run real processes/watchdog/timers/signals.
            sample = directory / "sample"
            sample.write_text('#!/bin/sh\necho "sampled $1" > "$4"\n')
            sample.chmod(0o755)
            source = "import subprocess, sys, time; child=subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(10)']); print('◇ Test run started.', flush=True); print('child', child.pid, flush=True); time.sleep(10)"
            started = time.monotonic()
            result = self.invoke(source, directory)
            self.assertLess(time.monotonic() - started, 8)
            self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
            self.assertIn("no test output", result.stdout)
            self.assertIn("Test run started", result.stdout)
            captures = list((directory / "diagnostics").glob("sample-*.txt"))
            self.assertGreaterEqual(len(captures), 2)
            child_pid = int(result.stdout.split("child ")[1].splitlines()[0])
            self.assertTrue(any(f"sampled {child_pid}" in p.read_text() for p in captures))
            # Termination must not wait for the private 10-second sleeper.
            self.assertEqual(result.stdout.count("watchdog timeout"), 1)

    def test_timeout_does_not_stop_a_process_outside_its_private_group(self):
        outside = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(10)"], start_new_session=True)
        try:
            with tempfile.TemporaryDirectory() as name:
                result = self.invoke("import time; time.sleep(10)", Path(name), total="0.3")
                self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
                self.assertIsNone(outside.poll())
        finally:
            outside.terminate()
            outside.wait(timeout=3)

    def test_cancellation_cleans_up_the_private_child_and_preserves_signal_status(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            marker = directory / "terminated"
            source = f"import signal, time; from pathlib import Path; signal.signal(signal.SIGTERM, lambda *_: (Path({str(marker)!r}).write_text('terminated'), exit(0))); print('ready', flush=True); time.sleep(10)"
            process = subprocess.Popen(
                [sys.executable, str(SCRIPT), "--diagnostics", str(directory / "diagnostics"),
                 "--", sys.executable, "-u", "-c", source],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            try:
                self.assertTrue(select.select([process.stdout], [], [], 3)[0])
                self.assertEqual(process.stdout.readline().strip(), "ready")
                process.send_signal(signal.SIGTERM)
                output, _ = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 143, output)
                self.assertEqual(marker.read_text(), "terminated")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
                process.stdout.close()

    def test_quiet_compilation_uses_total_deadline_not_test_idle_deadline(self):
        with tempfile.TemporaryDirectory() as name:
            result = self.invoke("import time; time.sleep(0.8); print('compiled')", Path(name))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("compiled", result.stdout)

    def test_total_deadline_also_bounds_a_silent_command_before_tests_start(self):
        with tempfile.TemporaryDirectory() as name:
            result = self.invoke("import time; time.sleep(10)", Path(name), total="0.4")
            self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
            self.assertIn("total deadline", result.stdout)

    def test_progress_resets_idle_deadline_instead_of_timing_out_a_live_suite(self):
        with tempfile.TemporaryDirectory() as name:
            source = "import time; print('◇ Test run started.', flush=True)\nfor _ in range(5):\n time.sleep(0.15); print('progress', flush=True)"
            result = self.invoke(source, Path(name))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
