"""Prepare one player installation from a Mac DMG, then activate its receipt."""
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
    if not isinstance(record, dict) or record.get('schema') != 1 or record.get('format') != 'mac-dmg':
        raise ContentError('Choose a completed import from a Mac DMG')
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


def prepare(dmg, store, checkpoint=lambda *_: None):
    requirements()
    from .bindings import prepare as prepare_bindings
    from .registrations import READER
    from .visuals import SCHEMA, prepare as prepare_visuals
    dmg, store = Path(dmg).absolute(), Path(store).resolve()
    if dmg.suffix.lower() != '.dmg' or dmg.is_symlink() or not dmg.is_file():
        raise ContentError('Select the Mac .dmg to play')
    if store.is_relative_to(Path(__file__).resolve().parents[2]):
        raise ContentError('Keep imported games outside the engine source')
    checkpoint('Checking your Mac disk image', 0.0)
    source_stat = dmg.stat(); digest = hashlib.sha256(); count = 0
    with dmg.open('rb') as source:
        while block := source.read(CHUNK):
            checkpoint('Checking your Mac disk image', count / source_stat.st_size)
            digest.update(block); count += len(block)
    identity = hashlib.sha256(encoded({'dmg_sha256': digest.hexdigest(), 'reader': READER,
                                      'visual_schema': SCHEMA, 'install_schema': 1})).hexdigest()
    store.mkdir(parents=True, exist_ok=True)
    destination = store / identity
    if destination.exists():
        receipt = destination / 'installation.json'
        record = read_receipt(receipt)
        if (record.get('source_sha256') != digest.hexdigest() or record.get('reader') != READER
                or record.get('visual_schema') != SCHEMA):
            raise ContentError('An existing import has different provenance; keep it unchanged')
        manifest = verify_cache(destination / record['content'], lambda *_: checkpoint('Checking the existing import', 0.0))
        verify_derivatives(destination, record, manifest, checkpoint)
        checkpoint('Mac game is ready', 1.0)
        return receipt, record
    stage = Path(tempfile.mkdtemp(prefix='.prepare-', dir=store))
    try:
        with DmgApp(dmg, lambda name, ratio: checkpoint(name, ratio), work=stage) as app:
            with Bundle(app) as bundle:
                if bundle.profile['edition'] != 'mac-full-hd':
                    raise ContentError('The DMG must contain Galaxy on Fire 2 Full HD for Mac')
            base, manifest = install(app, stage / 'content', lambda _, ratio: checkpoint('Importing the original game content', ratio))
            definitions, header, _ = prepare_bindings(app, base, stage / 'bindings', lambda _, ratio: checkpoint('Preparing the game data', ratio))
            visuals, visual = prepare_visuals(base, stage / 'visuals', checkpoint=lambda _, ratio: checkpoint('Preparing the original textures', ratio))
        after = dmg.stat()
        if (count, source_stat.st_mtime_ns, source_stat.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
            raise ContentError('The source DMG changed during preparation')
        record = {'schema': 1, 'format': 'mac-dmg', 'source_name': dmg.name,
                  'source_sha256': digest.hexdigest(), 'source_bytes': count,
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
