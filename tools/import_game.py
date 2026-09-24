#!/usr/bin/env python3
"""Player Mac import worker. Reports progress and supports cooperative cancellation."""
import argparse
import json
import os
from pathlib import Path
import signal
import sys
import time

from gof2_content.game_install import prepare


def write_status(path, record):
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    staged = path.with_suffix('.tmp')
    staged.write_text(json.dumps(record) + '\n', encoding='utf-8')
    # The game polls this file every frame, and Windows refuses to replace a file
    # while any process holds it open. Each hold lasts microseconds, so retry briefly.
    for attempt in range(100):
        try:
            os.replace(staged, path)
            return
        except PermissionError:
            if attempt == 99:
                raise
            time.sleep(0.02)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Mac .dmg file or extracted .app directory')
    parser.add_argument('--store', type=Path, required=True)
    parser.add_argument('--status', type=Path)
    parser.add_argument('--cancel-file', type=Path)
    args = parser.parse_args()
    cancelled = False
    last = 0.0

    def cancel(*_):
        nonlocal cancelled
        cancelled = True

    def checkpoint(message, ratio):
        nonlocal last
        if cancelled or args.cancel_file is not None and args.cancel_file.exists():
            raise InterruptedError('Import cancelled; the previous game and saves are unchanged')
        now = time.monotonic()
        if now - last > 0.2:
            last = now
            try:
                write_status(args.status, {'state': 'working', 'message': message, 'progress': ratio})
            except PermissionError:
                pass  # A progress update is never worth aborting the import; the next one retries.

    signal.signal(signal.SIGINT, cancel)
    signal.signal(signal.SIGTERM, cancel)
    try:
        receipt, record = prepare(args.source, args.store, checkpoint)
        write_status(args.status, {'state': 'ready', 'message': 'Mac game is ready', 'receipt': str(receipt)})
        if args.status is None:
            print(json.dumps({'receipt': str(receipt), **record}, indent=2))
        return 0
    except Exception as error:
        stopped = isinstance(error, InterruptedError)
        write_status(args.status, {'state': 'cancelled' if stopped else 'failed', 'message': str(error)})
        if args.status is None:
            print(str(error), file=sys.stderr)
        return 130 if stopped else 1


if __name__ == '__main__':
    sys.exit(main())
