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
