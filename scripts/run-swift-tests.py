#!/usr/bin/env python3
"""Bound a CI test process and retain diagnostics when its output stops.

Only the private process session created here is inspected/signalled. No process
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


def private_members(process):
    """SwiftPM creates additional groups inside our new private session."""
    listing = subprocess.run(["ps", "-axo", "pid=,pgid=,stat=,comm="],
                             capture_output=True, text=True, timeout=3, check=True)
    members = []
    for line in listing.stdout.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) != 4 or fields[2].startswith("Z"):
            continue
        pid, group = int(fields[0]), int(fields[1])
        try:
            if os.getsid(pid) == process.pid:
                members.append((pid, group, fields[3]))
        except (ProcessLookupError, PermissionError):
            continue
    return members


def signal_private_groups(process, members, sig):
    sent = set()
    for pid, group, _ in members:
        if group in sent:
            continue
        try:
            # Both values can change after enumeration; never trust stale rows.
            if os.getsid(pid) == process.pid and os.getpgid(pid) == group:
                os.killpg(group, sig)
                sent.add(group)
        except (ProcessLookupError, PermissionError):
            continue


def stop_session(process):
    try:
        remaining = private_members(process)
    except (OSError, ValueError, subprocess.SubprocessError):
        remaining = []
    # An unreaped child reserves its PID even if ps is unavailable. Never use
    # this numerical fallback after poll()/wait() has already reaped it.
    leader = [(process.pid, process.pid, "")] if process.returncode is None else []
    signal_private_groups(process, remaining + leader, signal.SIGTERM)
    deadline = time.monotonic() + 2
    # Keep the leader unreaped while group identifiers are still in use.
    # Zombie rows are excluded by private_members and need no grace period.
    while time.monotonic() < deadline:
        try:
            remaining = private_members(process)
        except (OSError, ValueError, subprocess.SubprocessError):
            break
        if not remaining:
            break
        time.sleep(0.02)
    # Always refresh after the grace period; if ps fails, the last candidates
    # remain safe to consider only after signal_private_groups revalidates them.
    try:
        remaining = private_members(process)
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    signal_private_groups(process, remaining + leader, signal.SIGKILL)
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        print("Private test command did not exit within the cleanup deadline.", file=sys.stderr)


def diagnose(process, directory):
    """Sample only members of the newly created session, preferring test runners."""
    try:
        members = private_members(process)
        members.sort(key=lambda item: ("testing" not in item[2].lower(), item[0]))
        for pid, _, _ in members[:8]:
            try:
                if os.getsid(pid) != process.pid:
                    continue
            except (ProcessLookupError, PermissionError):
                continue
            path = directory / f"sample-{pid}.txt"
            try:
                sampled = subprocess.run(["sample", str(pid), "1", "-file", str(path)],
                                         capture_output=True, text=True, timeout=4)
                if sampled.returncode != 0:
                    path.write_text("Stack sample unavailable for this test process.\n")
            except (OSError, subprocess.TimeoutExpired):
                path.write_text("Stack sample unavailable for this test process.\n")
    except (OSError, ValueError, subprocess.SubprocessError):
        (directory / "sampling-unavailable.txt").write_text("Could not enumerate the private test session.\n")


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
                    message = f"\n::error::Swift test watchdog timeout: {reason}; sampling private test session.\n"
                    sys.stdout.buffer.write(message.encode())
                    sys.stdout.buffer.flush()
                    log.write(message.encode())
                    log.flush()
                    try:
                        diagnose(process, options.diagnostics)
                    except OSError:
                        # Evidence is best-effort, including the fallback report.
                        # Unavailable storage must never mask a timed-out test.
                        pass
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
                        output = recent + chunk
                        tests_started = tests_started or b"Test run started" in output or b"Test Suite 'All tests' started" in output
                        recent = output[-4096:]
                        continue
                    # EOF remains permanently readable. Remove it so select waits
                    # for the next deadline tick while the command is still alive.
                    selector.unregister(process.stdout)
                    if process.poll() is not None:
                        return process.returncode if process.returncode >= 0 else 128 - process.returncode
                elif process.poll() is not None:
                    return process.returncode if process.returncode >= 0 else 128 - process.returncode
    finally:
        stop_session(process)


if __name__ == "__main__":
    raise SystemExit(main())
