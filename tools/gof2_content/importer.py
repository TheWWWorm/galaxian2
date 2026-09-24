"""Transactional, streamed desktop content ingestion; caches are private data."""
from collections import Counter
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import tempfile

from .bundle import Bundle, CHUNK, MAX_RESOURCE, MAX_TOTAL, safe_name
from .formats import ContentError, MAX_LANGUAGE, envelope, language

SCHEMA = 1
# Counts describe supported structural layouts, not decoded ship semantics.
LAYOUTS = {'ios-hd': {64: 3402}, 'mac-full-hd': {61: 3371, 64: 3385}}


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')


def identity(profile, files):
    resources = {name: {'bytes': row['bytes'], 'sha256': row['sha256']}
                 for name, row in files.items() if name.startswith('resources/')}
    return hashlib.sha256(encoded({'schema': SCHEMA, 'edition': profile['edition'],
                                  'layout': profile['layout'], 'resources': resources})).hexdigest()


def checked_path(root, name):
    safe_name(name)
    path = root / name
    current = path
    while current != root:
        if current.is_symlink():
            raise ContentError(f'Cache contains a symbolic link: {name}')
        current = current.parent
    if not path.is_file():
        raise ContentError(f'Missing cache file: {name}')
    return path


def verify_cache(root: Path, checkpoint=lambda *_: None):
    root = root.absolute()
    if root.is_symlink():
        raise ContentError('Cache directory must not be a symbolic link')
    manifest_path = checked_path(root, 'manifest.json')
    if manifest_path.stat().st_size > 16 * 1024 * 1024:
        raise ContentError('Oversized content manifest')
    try:
        manifest = json.loads(manifest_path.read_text('utf-8'))
        files = manifest['files']
        profile = manifest['profile']
        if (manifest['schema'] != SCHEMA or not isinstance(files, dict) or not 1 <= len(files) <= 20000
                or profile['edition'] not in LAYOUTS or profile['layout'] != 'gof2-bundle-v1'
                or not re.fullmatch('[0-9a-f]{64}', manifest['content_id'])):
            raise ContentError('Unsupported content manifest')
        if identity(profile, files) != manifest['content_id']:
            raise ContentError('Content identity does not match its resources')
        ships = manifest['ship_table']
        count = ships['records']
        strings = LAYOUTS[profile['edition']].get(count) if type(count) is int else None
        if (strings is None or ships['record_bytes'] != 36
                or files['resources/data/bin/ships.bin']['bytes'] != count * 36
                or not manifest['languages']
                or any(row['records'] != strings for row in manifest['languages'].values())):
            raise ContentError('Ship and language metadata do not match the content layout')
        total = 0
        for index, (name, row) in enumerate(files.items()):
            if not name.startswith(('resources/', 'definitions/')):
                raise ContentError('Unexpected cache file category')
            expected_size = row['bytes']
            if (not isinstance(expected_size, int) or not 0 < expected_size <= MAX_RESOURCE
                    or not re.fullmatch('[0-9a-f]{64}', row['sha256'])):
                raise ContentError(f'Invalid cache file record: {name}')
            path = checked_path(root, name)
            if path.stat().st_size != expected_size:
                raise ContentError(f'Cache file size mismatch: {name}')
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                while block := stream.read(CHUNK):
                    checkpoint(name, index / len(files))
                    total += len(block)
                    if total > MAX_TOTAL:
                        raise ContentError('Oversized cache')
                    digest.update(block)
            if digest.hexdigest() != row['sha256']:
                raise ContentError(f'Cache checksum mismatch: {name}')
        return manifest
    except (KeyError, TypeError, AttributeError, json.JSONDecodeError, UnicodeError) as error:
        raise ContentError('Malformed content manifest') from error


def install(source: Path, cache: Path, checkpoint=lambda *_: None):
    cache = cache.resolve()
    source_real = source.resolve()
    engine_root = Path(__file__).resolve().parents[2]
    if cache.is_relative_to(engine_root):
        raise ContentError('Keep imported content outside the engine source tree')
    if source_real.is_dir() and (cache.is_relative_to(source_real) or source_real.is_relative_to(cache)):
        raise ContentError('Source app and cache must be separate directories')
    cache.mkdir(parents=True, exist_ok=True)
    lock = cache / '.import-lock'
    try:
        lock.mkdir()
    except FileExistsError as error:
        raise ContentError('Another import holds this cache lock. After a forced shutdown, remove .import-lock only when no importer is running.') from error
    stage = None
    try:
        with Bundle(source, checkpoint) as bundle:
            resources = bundle.resources()
            ships, remainder = divmod(resources['data/bin/ships.bin'], 36)
            strings = LAYOUTS[bundle.profile['edition']].get(ships)
            if remainder or strings is None:
                raise ContentError('Unsupported ship table layout for this edition; field semantics remain unverified')
            profile = dict(bundle.profile, layout='gof2-bundle-v1')
            stage = Path(tempfile.mkdtemp(prefix='.stage-', dir=cache))
            files, languages, counts = {}, {}, Counter()
            total, done = sum(resources.values()), 0
            for name, size in resources.items():
                checkpoint(name, done / total)
                target = stage / 'resources' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                digest, copied, header = hashlib.sha256(), 0, b''
                with bundle.open(bundle.root + name) as stream, target.open('xb') as output:
                    while block := stream.read(CHUNK):
                        checkpoint(name, done / total)
                        copied += len(block)
                        if copied > size:
                            raise ContentError(f'Resource grew during import: {name}')
                        if not header:
                            header = block[:32]
                        digest.update(block)
                        output.write(block)
                        done += len(block)
                    output.flush()
                    os.fsync(output.fileno())
                if copied != size:
                    raise ContentError(f'Truncated resource: {name}')
                metadata = envelope(name, header, size)
                if name.endswith('.lang'):
                    if size > MAX_LANGUAGE:
                        raise ContentError(f'Oversized language file: {name}')
                    values = language(target.read_bytes())
                    if len(values) != strings:
                        raise ContentError(f'Unsupported language record count for {profile["edition"]}: {name}')
                    language_id = name.removesuffix('.lang')
                    normalized = f'definitions/languages/{language_id}.json'
                    data = encoded({'schema': SCHEMA, 'language': language_id,
                                    'source_resource': name, 'strings': values})
                    write_definition(stage, normalized, data, files)
                    languages[language_id] = {'records': len(values), 'path': normalized,
                                              'source_resource': name}
                    metadata['validation'] = 'decoded_utf8_records'
                files['resources/' + name] = dict(bytes=size, sha256=digest.hexdigest(), **metadata)
                counts[metadata['kind']] += 1
            asset_sets = sorted({name.split('/')[2] for name in resources if name.startswith('data/assets/')})
            manifest = {'schema': SCHEMA, 'profile': profile, 'content_id': identity(profile, files),
                        'files': files, 'languages': languages, 'counts': dict(counts),
                        'source_asset_sets': asset_sets, 'source_resource_bytes': total,
                        'ship_table': {'record_bytes': 36, 'records': ships, 'semantics': 'unverified'},
                        'support': {'localization': 'decoded', 'assets': 'stored_header_checked',
                                    'catalogues': 'opaque', 'campaign': 'unsupported',
                                    'valkyrie': 'unsupported', 'supernova': 'unsupported',
                                    'rendering': 'unsupported', 'audio_playback': 'unsupported'},
                        'supplemental_packs': []}
            write_bytes(stage / 'manifest.json', encoded(manifest))
            checkpoint('Validating staged cache', 1.0)
            # Per-file streaming hashes and reader checks already ran; activation is one rename.
            destination = cache / manifest['content_id']
            if destination.exists() or destination.is_symlink():
                existing = verify_cache(destination, checkpoint)
                if existing != manifest:
                    # Bundle version metadata may change without changing content bytes.
                    if existing['files'] != files or existing['profile']['edition'] != profile['edition']:
                        raise ContentError('Existing content identity has conflicting definitions')
                shutil.rmtree(stage)
                stage = None
                return destination, existing
            os.rename(stage, destination)
            stage = None
            return destination, manifest
    finally:
        if stage is not None:
            shutil.rmtree(stage)
        lock.rmdir()


def write_bytes(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())


def write_definition(stage, name, data, files):
    write_bytes(stage / name, data)
    files[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                   'kind': 'normalized_localization', 'validation': 'decoded_utf8_records'}
