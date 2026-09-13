"""Build private, versioned texture derivatives without altering base content."""
import hashlib
import json
from pathlib import Path
import os
import shutil
import struct
import tempfile
import zlib

from .aei import Texture
from .formats import ContentError
from .importer import checked_path, encoded, write_bytes

SCHEMA = 1


def convert_texture(texture):
    compressor = zlib.compressobj(level=3)
    compressed, decoded_size = [], 0
    for i, level in enumerate(texture.levels):
        pixels = texture.pixels(i)
        decoded_size += len(pixels)
        compressed.append(compressor.compress(pixels))
    compressed.append(compressor.flush())
    header = struct.pack('<4s5I', b'G2TX', SCHEMA, texture.width, texture.height, len(texture.levels), decoded_size)
    return header + b''.join(compressed)


def prepare(base: Path, output: Path, resources=None, checkpoint=lambda *_: None):
    base, output = base.resolve(), output.resolve()
    engine = Path(__file__).resolve().parents[2]
    if output.is_relative_to(engine) or output.is_relative_to(base) or base.is_relative_to(output):
        raise ContentError('Keep visual derivatives outside engine source and separate from the base cache')
    manifest_path = checked_path(base, 'manifest.json')
    if manifest_path.stat().st_size > 16 * 1024 * 1024:
        raise ContentError('Oversized base manifest')
    manifest = json.loads(manifest_path.read_text('utf-8'))
    if manifest.get('schema') != 1 or not isinstance(manifest.get('files'), dict):
        raise ContentError('Unsupported base manifest')
    from .importer import identity
    if identity(manifest['profile'], manifest['files']) != manifest.get('content_id'):
        raise ContentError('Base identity mismatch')
    available = {n for n in manifest['files'] if n.startswith('resources/') and n.endswith('.aei')}
    selected = sorted(available if resources is None else resources)
    if not selected or len(set(selected)) != len(selected) or not set(selected) <= available:
        raise ContentError('Choose unique texture resources present in this base manifest')
    recipe = {'schema': SCHEMA, 'base_content_id': manifest['content_id'], 'resources': selected,
              'decoder': 'texture2ddecoder-1.0.6', 'pixels': 'rgba8-original-mip-chain'}
    pack_id = hashlib.sha256(encoded(recipe)).hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / pack_id
    if destination.exists():
        raise ContentError('This visual derivative already exists. Choose another output root to rebuild it.')
    stage = Path(tempfile.mkdtemp(prefix='.visual-stage-', dir=output))
    try:
        files = {}
        for i, name in enumerate(selected):
            checkpoint(name, i / len(selected))
            source = checked_path(base, name)
            row = manifest['files'][name]
            if source.stat().st_size != row['bytes'] or source.stat().st_size > 192 * 1024 * 1024:
                raise ContentError(f'Invalid texture size: {name}')
            data = source.read_bytes()
            if hashlib.sha256(data).hexdigest() != row['sha256']:
                raise ContentError(f'Base texture checksum mismatch: {name}')
            texture = Texture(data)
            normalized = convert_texture(texture)
            path = 'textures/' + hashlib.sha256(name.encode()).hexdigest() + '.g2tx'
            write_bytes(stage / path, normalized)
            files[name] = {'path': path, 'sha256': hashlib.sha256(normalized).hexdigest(),
                           'bytes': len(normalized), 'source_sha256': row['sha256'], **texture.metadata()}
        result = {'schema': SCHEMA, 'pack_id': pack_id, 'recipe': recipe, 'textures': files}
        write_bytes(stage / 'visuals.json', encoded(result))
        checkpoint('Activating visual derivatives', 1.0)
        # Different unique staging roots cannot clobber an existing nonempty pack.
        os.rename(stage, destination)
        stage = None
        return destination, result
    finally:
        if stage is not None:
            shutil.rmtree(stage)
