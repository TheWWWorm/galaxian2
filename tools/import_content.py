#!/usr/bin/env python3
"""Import locally supplied GoF2 data into a private cache. Never runs game code."""
import argparse
import json
from pathlib import Path
import signal
import sys
import time
import zipfile

from gof2_content import ContentError, install, verify_cache


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    ingest = commands.add_parser('import', help='Import an Mac DMG, IPA, app ZIP or extracted .app')
    ingest.add_argument('source', type=Path)
    ingest.add_argument('--cache', type=Path, required=True, help='Private cache directory outside engine source')
    check = commands.add_parser('verify', help='Rehash all files in an installed content directory')
    check.add_argument('directory', type=Path)
    args = parser.parse_args()
    cancelled = False
    last = 0.0

    def cancel(*_):
        nonlocal cancelled
        cancelled = True

    def progress(name, fraction):
        nonlocal last
        if cancelled:
            raise InterruptedError('Import cancelled; installed caches are unchanged')
        now = time.monotonic()
        if now - last > 0.5:
            print(f'{fraction:6.1%} {name}', file=sys.stderr, flush=True)
            last = now

    signal.signal(signal.SIGINT, cancel)
    signal.signal(signal.SIGTERM, cancel)
    try:
        if args.command == 'import':
            directory, manifest = install(args.source, args.cache, progress)
        else:
            directory = args.directory
            manifest = verify_cache(directory, progress)
        print(json.dumps({'directory': str(directory), 'content_id': manifest['content_id'],
                          'profile': manifest['profile'], 'counts': manifest['counts'],
                          'support': manifest['support']}, indent=2))
        return 0
    except (ContentError, OSError, zipfile.BadZipFile, NotImplementedError) as error:
        print(str(error), file=sys.stderr)
        return 130 if cancelled else 1


if __name__ == '__main__':
    sys.exit(main())
