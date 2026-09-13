#!/usr/bin/env python3
"""Recover resource declarations from an original bundle without running its code."""
import argparse
from pathlib import Path
import signal
import sys
import time

from gof2_content.bindings import prepare
from gof2_content.formats import ContentError


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Original IPA, Mac app or app ZIP')
    parser.add_argument('base', type=Path, help='Matching imported base content directory')
    parser.add_argument('--output', required=True, type=Path, help='Separate private declaration cache root')
    args = parser.parse_args()
    cancelled = False
    last = 0.0
    def cancel(*_):
        nonlocal cancelled
        cancelled = True
    def progress(name, ratio):
        nonlocal last
        if cancelled:
            raise InterruptedError('Declaration import cancelled; installed content unchanged')
        now = time.monotonic()
        if now - last > 0.5:
            print(f'{ratio:6.1%} {name}', file=sys.stderr, flush=True)
            last = now
    signal.signal(signal.SIGINT, cancel)
    signal.signal(signal.SIGTERM, cancel)
    try:
        path, header, diagnostics = prepare(args.source, args.base, args.output, progress)
        print(path)
        print(f'Architecture {header["architecture"]}; binding identity {header["binding_id"]}')
        print(f'{len(diagnostics["ambiguous_ids"])} ambiguous IDs; '
              f'{len(diagnostics["missing_resources"])} missing resources; '
              f'{diagnostics["unmapped_resource_count"]} resources without a recovered binding')
        return 0
    except (ContentError, OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        return 130 if cancelled else 1


if __name__ == '__main__':
    sys.exit(main())
