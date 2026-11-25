#!/usr/bin/env python3
"""Validate release tags and keep prereleases outside stable distribution."""
import argparse
import os
import plistlib
from pathlib import Path
import re
import subprocess

TAG_PATTERN = re.compile(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(beta|rc)\.([1-9][0-9]*))?', re.ASCII)


def release_metadata(tag):
    match = TAG_PATTERN.fullmatch(tag)
    if match is None:
        raise ValueError('Expected vX.Y.Z, vX.Y.Z-beta.N or vX.Y.Z-rc.N with positive N')
    preview = match.group(4) is not None
    return {'tag': tag, 'version': tag[1:], 'bundle_version': '.'.join(match.group(1, 2, 3)),
            'prerelease': str(preview).lower(), 'update_homebrew': str(not preview).lower()}


def render_cask(values, sha256):
    if values['update_homebrew'] != 'true':
        raise ValueError('Only stable releases are distributed through Homebrew')
    if re.fullmatch(r'[0-9a-f]{64}', sha256) is None:
        raise ValueError('Expected a lowercase SHA-256 checksum')
    return f'''cask "octorunner" do
  version "{values['version']}"
  sha256 "{sha256}"

  url "https://github.com/loesch-digital/octorunner/releases/download/v#{{version}}/OctoRunner-#{{version}}-arm64.zip"
  name "OctoRunner"
  desc "Native macOS manager for self-hosted GitHub Actions runners"
  homepage "https://github.com/loesch-digital/octorunner"

  depends_on macos: :sequoia
  depends_on arch: :arm64

  app "OctoRunner.app"

  uninstall quit: "io.octorunner.macos"

  zap trash: [
    "~/Library/Application Support/io.octorunner.macos",
    "~/Library/Caches/io.octorunner.macos",
    "~/Library/Preferences/io.octorunner.macos.plist",
  ]
end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    metadata = commands.add_parser('metadata')
    metadata.add_argument('tag')
    stamp = commands.add_parser('stamp')
    stamp.add_argument('tag')
    stamp.add_argument('app', type=Path)
    publish = commands.add_parser('publish')
    publish.add_argument('tag')
    publish.add_argument('archive', type=Path)
    publish.add_argument('--notes-file', type=Path)
    cask = commands.add_parser('cask')
    cask.add_argument('tag')
    cask.add_argument('sha256')
    args = parser.parse_args()
    try:
        values = release_metadata(args.tag)
        if args.command == 'metadata':
            content = ''.join(f'{key}={value}\n' for key, value in values.items())
            output = os.environ.get('GITHUB_OUTPUT')
            if output:
                with open(output, 'a', encoding='utf-8') as stream:
                    stream.write(content)
            else:
                print(content, end='')
        elif args.command == 'cask':
            print(render_cask(values, args.sha256), end='')
        elif args.command == 'stamp':
            info = args.app / 'Contents' / 'Info.plist'
            with info.open('rb') as stream:
                properties = plistlib.load(stream)
            if (properties.get('CFBundleIdentifier') != 'io.octorunner.macos'
                    or properties.get('CFBundleShortVersionString') != values['bundle_version']
                    or properties.get('CFBundleVersion') != values['bundle_version']):
                raise ValueError('Bundle identity or numeric version does not match the release tag')
            properties['OctoRunnerReleaseVersion'] = values['version']
            with info.open('wb') as stream:
                plistlib.dump(properties, stream)
        else:
            if not args.archive.is_file():
                raise ValueError('Release archive is missing')
            if args.notes_file is not None and not args.notes_file.is_file():
                raise ValueError('Release notes file is missing')
            command = ['gh', 'release', 'create', args.tag, str(args.archive), '--verify-tag',
                       '--title', f'OctoRunner {args.tag}']
            if values['prerelease'] == 'true':
                command += ['--prerelease', '--latest=false']
            else:
                command += ['--latest=true']
            if args.notes_file is not None:
                command += ['--notes-file', str(args.notes_file)]
            else:
                command += ['--generate-notes']
            subprocess.run(command, check=True)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Release preparation failed: {error}\n')


if __name__ == '__main__':
    main()
