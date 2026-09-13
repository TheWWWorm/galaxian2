"""Verify same-edition texture quality variants from shared source declarations."""
import hashlib
import re

from .aei import Texture
from .formats import ContentError
from .importer import checked_path

QUALITY_PATH = re.compile(r'^(resources/data/assets/[^/]+/3d/textures/)(high|low)(/dx5/.+\.aei)$')


def quality_key(path):
    match = QUALITY_PATH.fullmatch(path)
    return (match[1] + match[3], match[2]) if match else None


def compatible(high, low):
    if high.cube or low.cube or high.fonts or low.fonts:
        return False
    # Original quality pairs can change BC1/BC3 compression and stored mips.
    # Both are decoded to the same native RGBA representation; source ID,
    # material parameter, aspect ratio and scaled atlas layout establish the
    # association. Compression equality would reject genuine original variants.
    if high.width % low.width or high.height % low.height:
        return False
    scale = high.width // low.width
    if scale not in (1, 2, 4, 8, 16) or high.height // low.height != scale:
        return False
    return high.regions == [tuple(v * scale for v in rect) for rect in low.regions]


def verify_variants(rows, base, manifest, checkpoint=lambda *_: None):
    if manifest['profile']['edition'] != 'mac-full-hd':
        return []
    by_id = {}
    for row in rows:
        by_id.setdefault(row['id'], []).append(row)
    result = []
    for identifier, declarations in by_id.items():
        paths = {r['resource'] for r in declarations}
        if len(paths) != 2 or any(r['kind'] != 'texture' or r['registration_type'] != 2 for r in declarations):
            continue
        if len({r.get('texture_parameter_bits') for r in declarations}) != 1 or any('texture_parameter_bits' not in r for r in declarations):
            continue
        keys = [quality_key(p) for p in paths]
        if any(k is None for k in keys) or len({k[0] for k in keys}) != 1 or {k[1] for k in keys} != {'high', 'low'}:
            continue
        choices = {quality_key(path)[1]: path for path in paths}
        if any(p not in manifest['files'] for p in paths):
            continue
        textures = {}
        for quality, path in choices.items():
            checkpoint('Checking texture quality variants: ' + path, len(result) / len(by_id))
            expected = manifest['files'][path]
            source = checked_path(base, path)
            if source.stat().st_size != expected['bytes'] or expected['bytes'] > 192 * 1024 * 1024:
                raise ContentError('Texture quality source size mismatch: ' + path)
            data = source.read_bytes()
            if hashlib.sha256(data).hexdigest() != expected['sha256']:
                raise ContentError('Texture quality source checksum mismatch: ' + path)
            textures[quality] = Texture(data)
        if not compatible(textures['high'], textures['low']):
            continue
        result.append({'id': identifier, 'high': choices['high'], 'low': choices['low'],
                       'high_sha256': manifest['files'][choices['high']]['sha256'],
                       'low_sha256': manifest['files'][choices['low']]['sha256'],
                       'high_size': [textures['high'].width, textures['high'].height],
                       'low_size': [textures['low'].width, textures['low'].height]})
    return sorted(result, key=lambda row: row['id'])
