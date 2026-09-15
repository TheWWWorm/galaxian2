"""Validate the engine source allowlist and its local resource dependencies."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

ALLOWED = {'.md', '.py', '.gd', '.uid', '.tscn', '.godot', '.json', '.gitignore', '.gdshader', '.gdshaderinc', '.txt'}


PROMOTIONAL_IMAGES = {'screenshots/02-portal-and-freighters.png': '283378cb4fbe230d0b7b60d578247aff085f6b6e6cffcaf3aff46479926c714b', 'screenshots/01-alioth-orbit.png': '88e7d2f609bd40364e746b7a985fffbe5d0a50878f24d985c1aeb4cce601c960', 'screenshots/03-native-flight.png': '1f98b7bc6a21967e4ad6cf9d857af126df8c4587e4f8af461a79a7f5e4c13e79'}

def manifest_files(root):
    root = Path(root).resolve()
    names = json.loads((root / 'source-manifest.json').read_text())['files']
    if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
        raise ValueError('Source entries must be a list of paths')
    if len(names) != len(set(names)):
        raise ValueError('Duplicate source entries')
    for name in names:
        rel = PurePosixPath(name)
        path = root / name
        if (rel.is_absolute() or '..' in rel.parts or '\\' in name or rel.as_posix() != name
                or not path.resolve().is_relative_to(root) or not path.is_file()):
            raise ValueError(f'Invalid source entry: {name}')
        for part in [path, *path.parents]:
            if part == root:
                break
            if part.is_symlink():
                raise ValueError(f'Symlink in source entry: {name}')
        if name in PROMOTIONAL_IMAGES:
            if hashlib.sha256(path.read_bytes()).hexdigest() != PROMOTIONAL_IMAGES[name]:
                raise ValueError('Changed promotional screenshot: ' + name)
        elif (path.suffix if name != '.gitignore' else name) not in ALLOWED:
            raise ValueError(f'Non-source file in allowlist: {name}')
        if any(part in ('.git', '.godot', '__pycache__', 'local') for part in rel.parts):
            raise ValueError(f'Private or generated directory in allowlist: {name}')
    return names


def source_closure(root):
    root = Path(root).resolve()
    names = manifest_files(root)
    allowed = set(names)
    counts = {'files': len(names), 'literal_load_preload_references': 0,
              'script_inheritance_references': 0, 'shader_includes': 0,
              'scene_resource_references': 0, 'unique_uids': 0, 'engine_only_allowlist': True}
    uids = set()
    patterns = {
        '.gd': [('literal_load_preload_references', r'''(?:load|preload)\(\s*["']res://([^"']+)["']\s*\)'''),
                ('script_inheritance_references', r'''extends\s+["']res://([^"']+)["']''')],
        '.gdshader': [('shader_includes', r'''#include\s+["']res://([^"']+)["']''')],
        '.gdshaderinc': [('shader_includes', r'''#include\s+["']res://([^"']+)["']''')],
        '.tscn': [('scene_resource_references', r'''path="res://([^"]+)"''')],
        '.godot': [('scene_resource_references', r'''="res://([^"]+)"''')],
    }
    for name in names:
        path = root / name
        if path.suffix in patterns:
            text = path.read_text()
            for count, pattern in patterns[path.suffix]:
                for target in re.findall(pattern, text):
                    if 'game/' + target not in allowed:
                        raise ValueError(f'{name}: resource missing from source allowlist: {target}')
                    counts[count] += 1
        if path.suffix == '.uid':
            value = path.read_text().strip()
            if name[:-4] not in allowed or not re.fullmatch(r'uid://[a-z0-9]+', value) or value in uids:
                raise ValueError(f'Invalid, orphaned or duplicate UID: {name}')
            uids.add(value)
    for path in (root / 'game').rglob('*.uid'):
        if '.godot' not in path.parts and path.relative_to(root).as_posix() not in allowed:
            raise ValueError(f'Resource UID missing from allowlist: {path.relative_to(root)}')
    counts['unique_uids'] = len(uids)
    return counts
