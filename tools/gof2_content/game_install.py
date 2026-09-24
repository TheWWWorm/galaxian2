"""Prepare one player installation from a Mac DMG or app, then activate its receipt."""
from contextlib import nullcontext
import hashlib
from importlib.metadata import PackageNotFoundError, version
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

from .bundle import Bundle, CHUNK
from .dmg import DmgApp
from .formats import ContentError
from .importer import checked_path, encoded, install, verify_cache


def requirements():
    for name, expected in [('capstone', '5.0.6'), ('texture2ddecoder', '1.0.6')]:
        try:
            found = version(name)
        except PackageNotFoundError as error:
            raise ContentError(f'The source importer needs {name}=={expected}. Install tools/requirements-bindings.txt and tools/requirements-visuals.txt.') from error
        if found != expected:
            raise ContentError(f'The source importer needs {name}=={expected}; found {found}')


def read_receipt(path):
    if path.is_symlink() or path.stat().st_size > 32768:
        raise ContentError('Invalid Mac import receipt')
    record = json.loads(path.read_text('utf-8'))
    if (not isinstance(record, dict) or record.get('schema') != 1
            or record.get('format') not in ('mac-dmg', 'mac-app')
            or not re.fullmatch('[0-9a-f]{64}', str(record.get('source_sha256')))):
        raise ContentError('Choose a completed import from a Mac .dmg or .app')
    for name, key in [('content', 'base_content_id'), ('bindings', 'binding_id'), ('visuals', 'visual_id')]:
        if not re.fullmatch('[0-9a-f]{64}', str(record.get(key))) or record.get(name) != name + '/' + record[key]:
            raise ContentError('Invalid content path in the Mac import receipt')
    return record


def verify_derivatives(root, record, manifest, checkpoint):
    from .bindings import binding_id
    definitions = root / record['bindings']
    header_path = checked_path(definitions, 'bindings.json')
    payload_path = checked_path(definitions, 'registrations.json')
    if header_path.stat().st_size > 32768 or payload_path.stat().st_size > 64 * 1024 * 1024:
        raise ContentError('The existing gameplay data is oversized')
    header = json.loads(header_path.read_text('utf-8'))
    payload = payload_path.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    if (header.get('base_content_id') != record['base_content_id'] or header.get('binding_id') != record['binding_id']
            or header.get('records_bytes') != len(payload) or header.get('records_sha256') != digest
            or binding_id(record['base_content_id'], header['source_executable_sha256'], header['architecture'], digest) != record['binding_id']):
        raise ContentError('The existing gameplay data has changed; keep the previous import unchanged')
    visuals = root / record['visuals']
    path = checked_path(visuals, 'visuals.json')
    if path.stat().st_size > 32 * 1024 * 1024:
        raise ContentError('The existing texture manifest is oversized')
    visual = json.loads(path.read_text('utf-8'))
    if (visual.get('pack_id') != record['visual_id'] or visual.get('recipe', {}).get('base_content_id') != record['base_content_id']
            or hashlib.sha256(encoded(visual['recipe'])).hexdigest() != record['visual_id']):
        raise ContentError('The existing texture manifest has changed')
    textures = visual.get('textures', {})
    if not textures or set(textures) != set(visual['recipe']['resources']):
        raise ContentError('The existing texture set is incomplete')
    for index, (name, row) in enumerate(textures.items()):
        checkpoint('Checking the existing textures', index / len(textures))
        path = checked_path(visuals, row['path'])
        if (path.stat().st_size != row['bytes'] or path.stat().st_size > 192 * 1024 * 1024
                or row['source_sha256'] != manifest['files'].get(name, {}).get('sha256')):
            raise ContentError('An existing texture has changed: ' + name)
        digest = hashlib.sha256()
        with path.open('rb') as texture:
            while block := texture.read(CHUNK):
                checkpoint('Checking the existing textures', index / len(textures))
                digest.update(block)
        if digest.hexdigest() != row['sha256']:
            raise ContentError('An existing texture is damaged: ' + name)


def source_fingerprint(source, checkpoint=lambda *_: None):
    """Hash only the app inputs we read, never its receipt or signing credentials."""
    if source.is_symlink():
        raise ContentError('Choose a regular Mac .dmg or .app, not a symbolic link')
    if source.suffix.lower() == '.app' and source.is_dir():
        rows = {}
        with Bundle(source, checkpoint) as bundle:
            if bundle.profile['edition'] != 'mac-full-hd':
                raise ContentError('Choose Galaxy on Fire 2 Full HD for Mac')
            names = sorted({bundle.info_path, bundle.executable()} | {bundle.root + n for n in bundle.resources()})
            for index, name in enumerate(names):
                digest = hashlib.sha256(); count = 0
                with bundle.open(name) as stream:
                    while block := stream.read(CHUNK):
                        checkpoint('Checking your Mac application', index / len(names))
                        digest.update(block); count += len(block)
                if count != bundle.entries[name][0]:
                    raise ContentError('The source app changed during preparation')
                rows[name] = {'bytes': count, 'sha256': digest.hexdigest()}
        return 'mac-app', hashlib.sha256(encoded(rows)).hexdigest(), sum(r['bytes'] for r in rows.values())
    if source.suffix.lower() != '.dmg' or not source.is_file():
        raise ContentError('Select the Mac .dmg file or the extracted .app directory itself')
    before = source.stat(); digest = hashlib.sha256(); count = 0
    with source.open('rb') as stream:
        while block := stream.read(CHUNK):
            checkpoint('Checking your Mac disk image', count / max(1, before.st_size))
            digest.update(block); count += len(block)
    after = source.stat()
    if (count, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
        raise ContentError('The source DMG changed during preparation')
    return 'mac-dmg', digest.hexdigest(), count


def prepare(source, store, checkpoint=lambda *_: None):
    requirements()
    from .bindings import prepare as prepare_bindings
    from .registrations import READER
    from .visuals import SCHEMA, prepare as prepare_visuals
    source, store = Path(source).absolute(), Path(store).resolve()
    if store.is_relative_to(Path(__file__).resolve().parents[2]):
        raise ContentError('Keep imported games outside the engine source')
    if source.is_dir() and (store.is_relative_to(source.resolve()) or source.resolve().is_relative_to(store)):
        raise ContentError('Source app and import store must be separate directories')
    source_format, source_hash, count = source_fingerprint(source, checkpoint)
    # Keep the original DMG identity recipe so existing installations stay reusable.
    identity = hashlib.sha256(encoded({('dmg_sha256' if source_format == 'mac-dmg' else 'app_sha256'): source_hash, 'reader': READER,
                                      'visual_schema': SCHEMA, 'install_schema': 1})).hexdigest()
    store.mkdir(parents=True, exist_ok=True)
    destination = store / identity
    if destination.exists():
        receipt = destination / 'installation.json'
        record = read_receipt(receipt)
        if (record.get('source_sha256') != source_hash or record.get('format') != source_format or record.get('reader') != READER
                or record.get('visual_schema') != SCHEMA):
            raise ContentError('An existing import has different provenance; keep it unchanged')
        manifest = verify_cache(destination / record['content'], lambda *_: checkpoint('Checking the existing import', 0.0))
        verify_derivatives(destination, record, manifest, checkpoint)
        checkpoint('Mac game is ready', 1.0)
        return receipt, record
    stage = Path(tempfile.mkdtemp(prefix='.prepare-', dir=store))
    try:
        with (DmgApp(source, checkpoint, work=stage) if source_format == 'mac-dmg' else nullcontext(source)) as app:
            with Bundle(app) as bundle:
                if bundle.profile['edition'] != 'mac-full-hd':
                    raise ContentError('Choose Galaxy on Fire 2 Full HD for Mac')
            base, manifest = install(app, stage / 'content', lambda _, ratio: checkpoint('Importing the original game content', ratio))
            definitions, header, _diagnostics = prepare_bindings(app, base, stage / 'bindings', lambda _, ratio: checkpoint('Preparing the game data', ratio))
            # A readable resource bundle is not proof that its campaign is supported.
            if manifest.get('ship_table', {}).get('records') == 64 and manifest['profile']['edition'] == 'mac-full-hd':
                declarations = json.loads((definitions / 'registrations.json').read_text('utf-8'))
                required = ('opening_loadout', 'frame_clock', 'station_entry', 'first_flight', 'mido_travel')
                travel = declarations.get('mido_travel', {})
                contracts = declarations.get('early_contracts', {})
                # Local journeys alone do not establish the connected campaign,
                # free travel, shops and jobs offered by the player application.
                if (any(not declarations.get(key) for key in required)
                        or any(not travel.get(key) for key in ('arrival_briefing', 'ordinary_contracts', 'suttnar_visit'))
                        or not contracts.get('ordinary_generation')):
                    raise ContentError('This newer Mac edition contains the extra ships, but its gameplay data is not supported yet. Your previous import and saves are unchanged.')
            visuals, visual = prepare_visuals(base, stage / 'visuals', checkpoint=lambda _, ratio: checkpoint('Preparing the original textures', ratio))
        if source_fingerprint(source, checkpoint) != (source_format, source_hash, count):
            raise ContentError('The source Mac game changed during preparation')
        record = {'schema': 1, 'format': source_format, 'source_name': source.name,
                  'source_sha256': source_hash, 'source_bytes': count,
                  'reader': READER, 'visual_schema': SCHEMA,
                  'base_content_id': manifest['content_id'], 'binding_id': header['binding_id'],
                  'visual_id': visual['pack_id'], 'content': base.relative_to(stage).as_posix(),
                  'bindings': definitions.relative_to(stage).as_posix(), 'visuals': visuals.relative_to(stage).as_posix()}
        (stage / 'installation.json').write_bytes(encoded(record))
        checkpoint('Finishing the Mac game import', 1.0)
        os.rename(stage, destination)
        stage = None
        return destination / 'installation.json', record
    finally:
        if stage is not None:
            shutil.rmtree(stage)
