import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "sign-and-notarize.sh"


class NotarizedReleaseTests(unittest.TestCase):
    def run_release(self, status="Accepted", reject_gatekeeper=False, missing_secret=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "OctoRunner.app"
            app.mkdir()
            log = root / "commands.jsonl"
            stub = root / "stub"
            stub.write_text('''#!/usr/bin/env python3
import base64, json, os, pathlib, sys
command = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps([command, *args]) + "\\n")
if command == "security" and args[:2] == ["list-keychains", "-d"] and "-s" not in args:
    print('    "/Users/runner/Library/Keychains/login.keychain-db"')
if command == "security" and args[0] == "find-identity":
    print('1) ABCDEF0123456789ABCDEF0123456789ABCDEF01 "Developer ID Application: Test (TEAM123)"')
if command == "fastlane":
    assert os.environ["CI"] == "true"
    assert os.environ["MATCH_GIT_URL"] == "https://github.com/example/certificates"
    assert os.environ["MATCH_KEYCHAIN_NAME"].endswith("release.keychain-db")
    assert os.environ["MATCH_KEYCHAIN_PASSWORD"]
    assert os.environ["MATCH_PASSWORD"]
    assert base64.b64decode(os.environ.get("MATCH_GIT_BASIC_AUTHORIZATION", "")).decode() == "x-access-token:test-token"
if command == "xcrun" and args[:2] == ["notarytool", "submit"]:
    print(json.dumps({"status": os.environ["NOTARY_STATUS"]}))
if command == "spctl" and os.environ["REJECT_GATEKEEPER"] == "1":
    sys.exit(1)
if command == "ditto":
    pathlib.Path(args[-1]).write_bytes(b"archive")
''')
            stub.chmod(0o755)
            for command in ["security", "codesign", "xcrun", "ditto", "spctl", "fastlane"]:
                (root / command).symlink_to(stub)
            env = {
                **os.environ,
                "PATH": f"{root}:{os.environ['PATH']}",
                "COMMAND_LOG": str(log),
                "NOTARY_STATUS": status,
                "REJECT_GATEKEEPER": str(int(reject_gatekeeper)),
                "MATCH_GIT_URL": "https://github.com/example/certificates",
                "MATCH_PASSWORD": "test-password",
                "MATCH_GIT_TOKEN": "test-token",
                "APP_STORE_CONNECT_API_KEY_CONTENT": "test-private-key",
                "APP_STORE_CONNECT_API_KEY_ID": "TESTKEY",
                "APP_STORE_CONNECT_API_KEY_ISSUER_ID": "test-issuer",
            }
            if missing_secret:
                env.pop("APP_STORE_CONNECT_API_KEY_CONTENT")
            output = root / "release.zip"
            result = subprocess.run(
                ["bash", str(SCRIPT), str(app), str(output)],
                env=env, capture_output=True, text=True,
            )
            commands = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, commands, output.exists()

    def test_missing_credentials_prevent_signing_and_packaging(self):
        result, commands, packaged = self.run_release(missing_secret=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("APP_STORE_CONNECT_API_KEY_CONTENT", result.stderr)
        self.assertFalse(commands)
        self.assertFalse(packaged)

    def test_rejected_notarization_never_produces_release_archive(self):
        result, commands, packaged = self.run_release(status="Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(packaged)
        self.assertFalse(any(command[:3] == ["xcrun", "stapler", "staple"] for command in commands))
        self.assertTrue(any(command[:2] == ["security", "delete-keychain"] for command in commands))

    def test_gatekeeper_rejection_prevents_release_archive(self):
        result, _, packaged = self.run_release(reject_gatekeeper=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(packaged)

    def test_signing_keychain_is_in_search_list_before_codesign_and_restored_afterwards(self):
        result, commands, _ = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        searches = [i for i, c in enumerate(commands) if c[:2] == ["security", "list-keychains"] and "-s" in c]
        sign = next(i for i, c in enumerate(commands) if c[0] == "codesign" and "--sign" in c)
        self.assertGreaterEqual(len(searches), 2, "search list must be set and restored")
        self.assertLess(searches[0], sign)
        self.assertTrue(any(a.endswith("release.keychain-db") for a in commands[searches[0]]))
        self.assertGreater(searches[-1], sign)
        self.assertFalse(any(a.endswith("release.keychain-db") for a in commands[searches[-1]]))
        self.assertIn("login.keychain-db", " ".join(commands[searches[-1]]))

    def test_success_packages_only_after_stapling_and_gatekeeper_verification(self):
        result, commands, packaged = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(packaged)
        sync = next(i for i, command in enumerate(commands) if command == ["fastlane", "mac", "sync_certificates"])
        staple = next(i for i, command in enumerate(commands) if command[:3] == ["xcrun", "stapler", "staple"])
        gatekeeper = next(i for i, command in enumerate(commands) if command[0] == "spctl")
        final_zip = max(i for i, command in enumerate(commands) if command[0] == "ditto")
        self.assertLess(staple, gatekeeper)
        self.assertLess(sync, staple)
        self.assertLess(gatekeeper, final_zip)
        signature = next(command for command in commands if command[0] == "codesign" and "--sign" in command)
        self.assertIn("--timestamp", signature)
        self.assertIn("runtime", signature)


if __name__ == "__main__":
    unittest.main()
