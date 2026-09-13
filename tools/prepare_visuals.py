#!/usr/bin/env python3
"""Decode original AEI textures into private native-runtime derivatives."""
import argparse
from pathlib import Path
import signal
import sys
import time

from gof2_content.formats import ContentError
from gof2_content.visuals import prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', type=Path, help='Imported base content identity directory')
    parser.add_argument('--output', type=Path, required=True, help='Separate private visual cache root')
    parser.add_argument('--resource', action='append', help='Manifest texture path; repeat or omit for all textures')
    args = parser.parse_args()
    cancelled = False
    last = 0.0
    def cancel(*_):
        nonlocal cancelled
        cancelled = True
    def progress(name, ratio):
        nonlocal last
        if cancelled:
            raise InterruptedError('Visual preparation cancelled; base cache unchanged')
        now = time.monotonic()
        if now - last > 0.5:
            print(f'{ratio:6.1%} {name}', file=sys.stderr, flush=True)
            last = now
    signal.signal(signal.SIGINT, cancel)
    signal.signal(signal.SIGTERM, cancel)
    try:
        path, result = prepare(args.base, args.output, args.resource, progress)
        print(path)
        print(f'{len(result["textures"])} textures; base {result["recipe"]["base_content_id"]}')
        return 0
    except (ContentError, OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        return 130 if cancelled else 1


if __name__ == '__main__':
    sys.exit(main())
