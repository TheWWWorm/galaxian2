#!/usr/bin/env python3
"""Build an explicitly allowlisted engine-only source ZIP outside the repository."""
import argparse
import json
from pathlib import Path, PurePosixPath
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {'.md', '.py', '.gd', '.uid', '.tscn', '.godot', '.json', '.gitignore', '.gdshader', '.gdshaderinc', '.txt'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(ROOT):
        parser.error('Choose an output outside the engine source repository')
    names = json.loads((ROOT / 'source-manifest.json').read_text())['files']
    if len(names) != len(set(names)):
        raise ValueError('Duplicate source entries')
    for name in names:
        rel = PurePosixPath(name)
        path = ROOT / name
        if (rel.is_absolute() or '..' in rel.parts or '\\' in name
                or not path.resolve().is_relative_to(ROOT) or not path.is_file()):
            raise ValueError(f'Invalid source entry: {name}')
        for part in [path, *path.parents]:
            if part == ROOT:
                break
            if part.is_symlink():
                raise ValueError(f'Symlink in source entry: {name}')
        if (path.suffix if name != '.gitignore' else name) not in ALLOWED:
            raise ValueError(f'Non-source file in allowlist: {name}')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in names:
            archive.write(ROOT / name, 'gof2-remake/' + name)
    print(f'{output}: {len(names)} engine source files')


if __name__ == '__main__':
    main()
