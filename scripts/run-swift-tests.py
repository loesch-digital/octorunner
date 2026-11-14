#!/usr/bin/env python3
"""Bound a CI test process and retain diagnostics when its output stops.

Only the private process group created here is inspected/signalled. No process
arguments, environment dumps, existing app or runner processes are collected.
"""
import argparse
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


def stop_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    # The parent may have exited while a descendant still owns the output pipe.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def diagnose(process, directory):
    """Sample only members of the newly created group, preferring test runners."""
    try:
        listing = subprocess.run(["ps", "-axo", "pid=,pgid=,comm="],
                                 capture_output=True, text=True, timeout=3, check=True)
        members = []
        for line in listing.stdout.splitlines():
            fields = line.strip().split(None, 2)
            if len(fields) == 3 and int(fields[1]) == process.pid:
                members.append((int(fields[0]), fields[2]))
        members.sort(key=lambda item: ("testing" not in item[1].lower(), item[0]))
        for pid, _ in members[:8]:
            path = directory / f"sample-{pid}.txt"
            try:
                sampled = subprocess.run(["sample", str(pid), "1", "-file", str(path)],
                                         capture_output=True, text=True, timeout=4)
                if sampled.returncode != 0:
                    path.write_text("Stack sample unavailable for this test process.\n")
            except (OSError, subprocess.TimeoutExpired):
                path.write_text("Stack sample unavailable for this test process.\n")
    except (OSError, ValueError, subprocess.SubprocessError):
        (directory / "sampling-unavailable.txt").write_text("Could not enumerate the private test group.\n")


def positive_seconds(value):
    result = float(value)
    if not 0 < result < float("inf"):
        raise argparse.ArgumentTypeError("deadline must be a finite positive number")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diagnostics", type=Path, default=Path("DerivedData/SwiftTestDiagnostics"))
    parser.add_argument("--idle-timeout", type=positive_seconds, default=120)
    parser.add_argument("--timeout", type=positive_seconds, default=600)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    command = options.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a test command is required after --")
    options.diagnostics.mkdir(parents=True, exist_ok=True)
    started = last_output = time.monotonic()
    tests_started = False
    recent = b""

    def cancelled(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, cancelled)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=True)
    try:
        with process.stdout, selectors.DefaultSelector() as selector, (options.diagnostics / "swift-tests.log").open("wb") as log:
            os.set_blocking(process.stdout.fileno(), False)
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                now = time.monotonic()
                reason = None
                if now - started >= options.timeout:
                    reason = "total deadline"
                elif tests_started and now - last_output >= options.idle_timeout:
                    reason = "no test output"
                if reason:
                    message = f"\n::error::Swift test watchdog timeout: {reason}; sampling private test group.\n"
                    sys.stdout.buffer.write(message.encode())
                    sys.stdout.buffer.flush()
                    log.write(message.encode())
                    log.flush()
                    diagnose(process, options.diagnostics)
                    return 124
                ready = selector.select(timeout=0.1)
                if ready:
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if chunk:
                        sys.stdout.buffer.write(chunk)
                        sys.stdout.buffer.flush()
                        log.write(chunk)
                        log.flush()
                        last_output = time.monotonic()
                        recent = (recent + chunk)[-4096:]
                        tests_started = tests_started or b"Test run started" in recent or b"Test Suite 'All tests' started" in recent
                        continue
                    if process.poll() is not None:
                        return process.returncode if process.returncode >= 0 else 128 - process.returncode
                elif process.poll() is not None:
                    return process.returncode if process.returncode >= 0 else 128 - process.returncode
    finally:
        stop_group(process)


if __name__ == "__main__":
    raise SystemExit(main())
