"""Private executable-derived declarations, bound to matching imported resources."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from .bundle import Bundle, CHUNK
from .formats import ContentError
from .importer import encoded, verify_cache, write_bytes
from .registrations import extract, MAX_EXECUTABLE
from .texture_variants import verify_variants
from .fev import read as read_audio_events


def binding_id(base_id, executable_hash, architecture, records_hash):
    return hashlib.sha256(('gof2-bindings-v1\n' + base_id + '\n' + executable_hash + '\n'
                           + architecture + '\n' + records_hash + '\n').encode('ascii')).hexdigest()


def prepare(source: Path, base: Path, output: Path, checkpoint=lambda *_: None):
    original_source, original_base = source.absolute(), base.absolute()
    source, base, output = source.resolve(), base.resolve(), output.resolve()
    engine = Path(__file__).resolve().parents[2]
    if (output.is_relative_to(engine) or output.is_relative_to(base) or base.is_relative_to(output)
            or source.is_dir() and (output.is_relative_to(source) or source.is_relative_to(output))):
        raise ContentError('Keep declarations outside the engine, original app and base cache')
    checkpoint('Verifying imported base', 0.0)
    manifest = verify_cache(original_base, checkpoint)
    with Bundle(original_source, checkpoint) as bundle:
        if bundle.profile['edition'] != manifest['profile']['edition']:
            raise ContentError('Executable and imported base use different editions')
        resources = bundle.resources()
        expected = {n.removeprefix('resources/'): r for n, r in manifest['files'].items()
                    if n.startswith('resources/')}
        if set(resources) != set(expected):
            raise ContentError('Source resource set does not match the imported base')
        total = sum(resources.values())
        done = 0
        for name, size in resources.items():
            if size != expected[name]['bytes']:
                raise ContentError('Source resource size differs from the base: ' + name)
            digest = hashlib.sha256()
            read = 0
            with bundle.open(bundle.root + name) as stream:
                while block := stream.read(CHUNK):
                    checkpoint('Matching source: ' + name, done / total)
                    read += len(block)
                    if read > size:
                        raise ContentError('Source grew during declaration import')
                    digest.update(block)
                    done += len(block)
            if read != size or digest.hexdigest() != expected[name]['sha256']:
                raise ContentError('Source resource checksum differs from the base: ' + name)
        declarations = extract(bundle.read(bundle.executable(), MAX_EXECUTABLE), bundle.profile['edition'], checkpoint,
                               ship_count=manifest['ship_table']['records'])
    audio = {}
    event_files = [name for name, record in manifest['files'].items() if record.get('kind') == 'audio_events']
    if len(event_files) > 1:
        raise ContentError('Multiple FMOD event projects are not supported')
    if event_files:
        from .importer import checked_path
        event_resource = event_files[0]
        event_path = checked_path(base, event_resource)
        if event_path.stat().st_size > 8 * 1024 * 1024:
            raise ContentError('Oversized FMOD event project')
        event_data = event_path.read_bytes()
        if hashlib.sha256(event_data).hexdigest() != manifest['files'][event_resource]['sha256']:
            raise ContentError('FMOD event project checksum differs from the base')
        audio = read_audio_events(event_data)
        for bank in audio['banks']:
            for variant in bank['variants']:
                if manifest['files'].get(variant['resource'], {}).get('kind') != 'audio_bank':
                    raise ContentError('FMOD event project refers to a missing sound bank: ' + variant['resource'])
        audio['source_resource'] = event_resource
        audio['source_sha256'] = manifest['files'][event_resource]['sha256']
    rows = declarations.pop('registrations')
    materials = declarations.pop('materials')
    ship_models = declarations.pop('ship_models')
    hangars = declarations.pop('hangars')
    ship_placement = declarations.pop('ship_placement')
    ship_lights = declarations.pop('ship_lights')
    ship_lod = declarations.pop('ship_lod')
    lod_refresh = declarations.pop('lod_refresh')
    opening_sky = declarations.pop('opening_sky')
    damage_particles = declarations.pop('damage_particles')
    environment_colors = declarations.pop('environment_colors')
    reflection_selection = declarations.pop('reflection_selection')
    surface_material = declarations.pop('surface_material')
    scenery_population = declarations.pop('scenery_population')
    scenery_resources = declarations.pop('scenery_resources')
    scenery_effects = declarations.pop('scenery_effects')
    weapon_parameters = declarations.pop('weapon_parameters')
    cruise = declarations.pop('cruise')
    manual_rotation = declarations.pop('manual_rotation')
    pilot_response = declarations.pop('pilot_response')
    vehicle_response = declarations.pop('vehicle_response')
    frame_clock = declarations.pop('frame_clock')
    opening_loadout = declarations.pop('opening_loadout')
    opening_dialogue = declarations.pop('opening_dialogue')
    arrival_dialogue = declarations.pop('arrival_dialogue')
    arrival_staging = declarations.pop('arrival_staging')
    arrival_environment = declarations.pop('arrival_environment')
    arrival_actor_motion = declarations.pop('arrival_actor_motion')
    arrival_actor_construction = declarations.pop('arrival_actor_construction')
    arrival_world_initialization = declarations.pop('arrival_world_initialization')
    opening_handoff = declarations.pop('opening_handoff')
    arrival_session = declarations.pop('arrival_session')
    station_entry = declarations.pop('station_entry')
    station_departure = declarations.pop('station_departure')
    first_flight = declarations.pop('first_flight')
    mining_briefing = declarations.pop('mining_briefing')
    mining_drill = declarations.pop('mining_drill')
    mining_targeting = declarations.pop('mining_targeting')
    mining_approach = declarations.pop('mining_approach')
    mining_session = declarations.pop('mining_session')
    flight_notices = declarations.pop('flight_notices')
    mining_objective = declarations.pop('mining_objective')
    station_exterior = declarations.pop('station_exterior')
    station_autopilot = declarations.pop('station_autopilot')
    station_flight = declarations.pop('station_flight')
    station_return = declarations.pop('station_return')
    full_hold_departure = declarations.pop('full_hold_departure')
    full_hold_flight = declarations.pop('full_hold_flight')
    full_hold_pirate = declarations.pop('full_hold_pirate')
    full_hold_control = declarations.pop('full_hold_control')
    full_hold_destruction = declarations.pop('full_hold_destruction')
    full_hold_story = declarations.pop('full_hold_story')
    full_hold_appearance = declarations.pop('full_hold_appearance')
    full_hold_return = declarations.pop('full_hold_return')
    station_equipment = declarations.pop('station_equipment')
    combat_training = declarations.pop('combat_training')
    combat_training_control = declarations.pop('combat_training_control')
    combat_training_weapons = declarations.pop('combat_training_weapons')
    combat_training_destruction = declarations.pop('combat_training_destruction')
    combat_training_visuals = declarations.pop('combat_training_visuals')
    combat_training_story = declarations.pop('combat_training_story')
    fast_forward = declarations.pop('fast_forward')
    ordinary_music = declarations.pop('ordinary_music')
    physical_scenery_contacts = declarations.pop('physical_scenery_contacts')
    mido_travel = declarations.pop('mido_travel')
    early_contracts = declarations.pop('early_contracts')
    engine_particles = declarations.pop('engine_particles')
    engine_particle_owners = declarations.pop('engine_particle_owners')
    deep_science_stock = declarations.pop('deep_science_stock')
    persistent_contacts = declarations.pop('persistent_contacts')
    ambient_population = declarations.pop('ambient_population')
    ambient_combat = declarations.pop('ambient_combat')
    freighter_destruction = declarations.pop('freighter_destruction')
    ambient_lifecycle = declarations.pop('ambient_lifecycle')
    player_destruction = declarations.pop('player_destruction')
    full_hold_particles = declarations.pop('full_hold_particles')
    game_over_presentation = declarations.pop('game_over_presentation')
    station_presentation = declarations.pop('station_presentation')
    desktop_text = declarations.pop('desktop_text')
    text_aliases = declarations.pop('text_aliases')
    fonts = declarations.pop('font_bindings')
    portraits = declarations.pop('portrait_textures')
    speakers = declarations.pop('speaker_bindings')
    image_regions = declarations.pop('image_regions')
    portrait_layers = declarations.pop('portrait_layers')
    opening_actors = declarations.pop('opening_actors')
    opening_staging = declarations.pop('opening_staging')
    opening_camera = declarations.pop('opening_camera')
    camera_follow = declarations.pop('camera_follow')
    opening_clock = declarations.pop('opening_clock')
    opening_drift = declarations.pop('opening_drift')
    flight_projection = declarations.pop('flight_projection')
    texture_variants = verify_variants(rows, base, manifest, checkpoint)
    by_id = {}
    for row in rows:
        by_id.setdefault(row['id'], set()).add((row['resource'], row['registration_type']))
    used = {row['resource'] for row in rows} | {name for row in portraits.get('rows', []) for name in row['variants'].values()}
    material_ids = {row['id'] for row in materials}
    material_variants = {}
    for row in materials:
        material_variants.setdefault(row['id'], set()).add((row['render_type'], tuple(row['texture_ids']), tuple(row['parameter_bits'])))
    payload = encoded({'schema': 1, 'reader': declarations['reader'], 'registrations': rows, 'materials': materials,
                       'texture_variants': texture_variants,
                       'audio': audio,
                       'ship_models': ship_models,
                       'hangars': hangars,
                       'ship_placement': ship_placement,
                       'ship_lights': ship_lights,
                       'ship_lod': ship_lod,
                       'lod_refresh': lod_refresh,
                       'opening_sky': opening_sky,
                       'damage_particles': damage_particles,
                       'environment_colors': environment_colors,
                       'reflection_selection': reflection_selection,
                       'surface_material': surface_material,
                       'scenery_population': scenery_population,
                       'scenery_resources': scenery_resources,
               'scenery_effects': scenery_effects,
                       'weapon_parameters': weapon_parameters,
                       'cruise': cruise,
                       'manual_rotation': manual_rotation,
                       'pilot_response': pilot_response,
                       'vehicle_response': vehicle_response,
                       'frame_clock': frame_clock,
                       'opening_loadout': opening_loadout,
                       'opening_dialogue': opening_dialogue,
                       'arrival_dialogue': arrival_dialogue,
                       'arrival_staging': arrival_staging,
                       'arrival_environment': arrival_environment,
                       'arrival_actor_motion': arrival_actor_motion,
                       'arrival_actor_construction': arrival_actor_construction,
                       'arrival_world_initialization': arrival_world_initialization,
                       'opening_handoff': opening_handoff,
                       'arrival_session': arrival_session,
                       'station_entry': station_entry,
                       'station_departure': station_departure,
                       'first_flight': first_flight,
                       'mining_briefing': mining_briefing,
                       'mining_drill': mining_drill,
                       'mining_targeting': mining_targeting,
                       'mining_approach': mining_approach,
                       'mining_session': mining_session,
                       'flight_notices': flight_notices,
                       'mining_objective': mining_objective,
                       'station_exterior': station_exterior,
                       'station_autopilot': station_autopilot,
                       'station_flight': station_flight,
                       'station_return': station_return,
                       'full_hold_departure': full_hold_departure,
                       'full_hold_flight': full_hold_flight,
                       'full_hold_pirate': full_hold_pirate,
                       'full_hold_control': full_hold_control,
                       'full_hold_destruction': full_hold_destruction,
                       'full_hold_story': full_hold_story,
                       'full_hold_appearance': full_hold_appearance,
                       'full_hold_return': full_hold_return,
                       'station_equipment': station_equipment,
                       'combat_training': combat_training,
                       'combat_training_control': combat_training_control,
                       'combat_training_weapons': combat_training_weapons,
                       'combat_training_destruction': combat_training_destruction,
                       'combat_training_visuals': combat_training_visuals,
                       'combat_training_story': combat_training_story,
                       'fast_forward': fast_forward,
                       'ordinary_music': ordinary_music,
                       'physical_scenery_contacts': physical_scenery_contacts,
                       'mido_travel': mido_travel,
                       'early_contracts': early_contracts,
                       'engine_particles': engine_particles,
                       'engine_particle_owners': engine_particle_owners,
                       'deep_science_stock': deep_science_stock,
                       'persistent_contacts': persistent_contacts,
                       'ambient_population': ambient_population,
                       'ambient_combat': ambient_combat,
                       'freighter_destruction': freighter_destruction,
                       'ambient_lifecycle': ambient_lifecycle,
                       'player_destruction': player_destruction,
                       'full_hold_particles': full_hold_particles,
                       'game_over_presentation': game_over_presentation,
                       'station_presentation': station_presentation,
                       'desktop_text': desktop_text,
                       'text_aliases': text_aliases,
                       'font_bindings': fonts,
                       'portrait_textures': portraits,
                       'speaker_bindings': speakers,
                       'image_regions': image_regions,
                       'portrait_layers': portrait_layers,
                       'opening_actors': opening_actors,
                       'opening_staging': opening_staging,
                       'opening_camera': opening_camera,
                       'camera_follow': camera_follow,
                       'opening_clock': opening_clock,
                       'opening_drift': opening_drift,
                       'flight_projection': flight_projection,
                       'diagnostics': {
                           'ambiguous_material_ids': sorted(k for k, variants in material_variants.items() if len(variants) > 1),
                           'missing_material_ids': sorted({r['material_id'] for r in rows if 'material_id' in r and r['material_id'] != 65535} - material_ids),
                           'missing_material_texture_ids': sorted({t for r in materials for t in r['texture_ids'] if t != 65535} - by_id.keys()),
                           'mesh_declarations_without_material': sum(r['kind'] == 'mesh' and r['registration_type'] == 4 and 'material_id' not in r for r in rows),
                           'ambiguous_ids': sorted(k for k, alternatives in by_id.items() if len(alternatives) > 1),
                           'missing_resources': sorted(used - manifest['files'].keys()),
                           'unverified_type_ids': sorted({r['id'] for r in rows if r['registration_type'] != (4 if r['kind'] == 'mesh' else 2)}),
                           'unmapped_resource_count': len({n for n, r in manifest['files'].items()
                                                          if r['kind'] in ('mesh', 'texture')} - used)}})
    digest = hashlib.sha256(payload).hexdigest()
    identity = binding_id(manifest['content_id'], declarations['source_executable_sha256'],
                          declarations['architecture'], digest)
    header = dict(declarations, schema=1, base_content_id=manifest['content_id'],
                  binding_id=identity, records_sha256=digest, records_bytes=len(payload))
    output.mkdir(parents=True, exist_ok=True)
    destination = output / identity
    if destination.exists():
        raise ContentError('These declarations already exist. Choose a new output root to rebuild.')
    stage = Path(tempfile.mkdtemp(prefix='.bindings-stage-', dir=output))
    try:
        write_bytes(stage / 'registrations.json', payload)
        write_bytes(stage / 'bindings.json', encoded(header))
        checkpoint('Activating resource declarations', 1.0)
        os.rename(stage, destination)
        stage = None
        return destination, header, json.loads(payload)['diagnostics']
    finally:
        if stage is not None:
            shutil.rmtree(stage)
