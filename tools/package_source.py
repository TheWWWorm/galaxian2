#!/usr/bin/env python3
"""Build an explicitly allowlisted engine-only source ZIP outside the repository."""
import argparse
from pathlib import Path
import zipfile

from source_checks import ALLOWED, manifest_files, source_closure

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        parser.error('Choose an output outside the engine source repository')
    names = manifest_files(ROOT)
    source_closure(ROOT)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in names:
            archive.write(ROOT / name, 'galaxian2/' + name)
    print(f'{output}: {len(names)} engine source files')


if __name__ == '__main__':
    main()
