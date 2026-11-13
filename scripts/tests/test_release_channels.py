"""Release policy: a preview must never replace stable distribution."""
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'release_tools.py'


class ReleaseChannelTests(unittest.TestCase):
    def run_tool(self, *arguments, env=None):
        child_env = dict(os.environ if env is None else env)
        if env is None:
            child_env.pop('GITHUB_OUTPUT', None)
        child_env.pop('GH_TOKEN', None)
        child_env.pop('GITHUB_TOKEN', None)
        return subprocess.run([sys.executable, str(SCRIPT), *arguments],
                              capture_output=True, text=True, env=child_env)

    def test_metadata_distinguishes_numeric_bundle_and_full_beta_version(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'outputs'
            result = self.run_tool('metadata', 'v0.5.0-beta.1', env={**os.environ, 'GITHUB_OUTPUT': str(output)})
            self.assertEqual(result.returncode, 0, result.stderr)
            metadata = dict(line.split('=', 1) for line in output.read_text().splitlines())
            self.assertEqual(metadata, {'tag': 'v0.5.0-beta.1', 'version': '0.5.0-beta.1',
                'bundle_version': '0.5.0', 'prerelease': 'true', 'update_homebrew': 'false'})

    def test_invalid_tags_never_append_workflow_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'outputs'
            output.write_text('existing=value\n')
            for tag in ['', '0.5.0', 'v01.5.0', 'v0.5.0-beta.0', 'v0.5.0\nupdate_homebrew=true',
                        'v0.5.0/../../file', 'v0.5.0-unknown.1', 'v0.5.0-beta.01']:
                with self.subTest(tag=tag):
                    result = self.run_tool('metadata', tag, env={**os.environ, 'GITHUB_OUTPUT': str(output)})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(output.read_text(), 'existing=value\n')

    def test_publish_policy_uses_verified_tag_and_never_clobbers_archives(self):
        with tempfile.TemporaryDirectory(prefix='release fixtures ') as directory:
            root = Path(directory)
            archive = root / 'OctoRunner archive.zip'
            archive.write_bytes(b'synthetic archive')
            notes = root / 'notes.md'
            notes.write_text('Preview notes\n\nOpen work remains.\n')
            gh = root / 'gh'
            gh.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                          'from pathlib import Path\nPath(os.environ["GH_ARGS"]).write_text(json.dumps(sys.argv[1:]))\n')
            gh.chmod(0o700)
            recorded = root / 'args.json'
            env = {**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH'], 'GH_ARGS': str(recorded)}
            for tag, preview in [('v0.5.0-beta.1', True), ('v0.5.0-rc.2', True), ('v0.5.0', False)]:
                with self.subTest(tag=tag):
                    result = self.run_tool('publish', tag, str(archive), '--notes-file', str(notes), env=env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    args = json.loads(recorded.read_text())
                    self.assertEqual(args[:4], ['release', 'create', tag, str(archive)])
                    self.assertIn('--verify-tag', args)
                    self.assertNotIn('--clobber', args)
                    self.assertEqual('--prerelease' in args, preview)
                    self.assertIn('--latest=false' if preview else '--latest=true', args)
                    self.assertEqual(args[args.index('--notes-file') + 1], str(notes))
            recorded.unlink()
            for tag, path in [('v0.5.0', root / 'missing.zip'), ('unsafe', archive)]:
                result = self.run_tool('publish', tag, str(path), env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(recorded.exists())

    def test_beta_identity_is_written_only_to_matching_unsigned_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'OctoRunner.app'
            contents = app / 'Contents'
            contents.mkdir(parents=True)
            info = contents / 'Info.plist'
            original = {'CFBundleIdentifier': 'io.octorunner.macos', 'CFBundleShortVersionString': '0.5.0', 'CFBundleVersion': '0.5.0'}
            info.write_bytes(plistlib.dumps(original))
            result = self.run_tool('stamp', 'v0.5.0-beta.1', str(app))
            self.assertEqual(result.returncode, 0, result.stderr)
            stamped = plistlib.loads(info.read_bytes())
            self.assertEqual(stamped, {**original, 'OctoRunnerReleaseVersion': '0.5.0-beta.1'})
            before = info.read_bytes()
            result = self.run_tool('stamp', 'v0.6.0-beta.1', str(app))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(info.read_bytes(), before)

    def test_cli_fixture_does_not_write_to_the_parent_workflow_output(self):
        with tempfile.TemporaryDirectory() as directory:
            parent_output = Path(directory) / 'parent-output'
            parent_output.write_text('parent=value\n')
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(parent_output)}):
                result = self.run_tool('metadata', 'v0.5.0')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(parent_output.read_text(), 'parent=value\n')
            self.assertIn('update_homebrew=true', result.stdout)

    def test_stable_metadata_allows_homebrew(self):
        result = self.run_tool('metadata', 'v0.5.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('update_homebrew=true', result.stdout)
        self.assertIn('prerelease=false', result.stdout)
