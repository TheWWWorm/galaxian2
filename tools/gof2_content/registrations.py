"""Static resource declarations only. No instruction execution or control-flow traversal.

Recognizes bounded compiler record-initialization templates. Original executable
bytes never leave the reader; only resource/material fields and provenance do.
"""
import hashlib
import re
import struct

from .formats import ContentError
from .bundle import safe_name
from .materials import extract_materials, ios_mesh_metadata
from .ship_models import extract_ship_models
from .hangars import extract_hangars
from .ship_placement import extract_ship_placement
from .ship_lights import extract_ship_lights
from .ship_lod import extract_ship_lod
from .lod_refresh import extract_lod_refresh
from .opening_sky import extract_opening_sky
from .planet_resources import extract_planet_resources
from .sun_flares import extract_sun_flares
from .damage_particles import extract_damage_particles
from .damage_particle_owners import extract_damage_particle_owners
from .scenery_population import extract_scenery_population
from .scenery_resources import extract_scenery_resources
from .scenery_effects import extract_scenery_effects
from .environment_colors import extract_environment_colors
from .reflection_selection import extract_reflection_selection
from .surface_material import extract_surface_material
from .weapon_parameters import extract_weapon_parameters
from .cruise import extract_cruise
from .steering import extract_manual_rotation
from .pilot_response import extract_pilot_response
from .vehicle_response import extract_vehicle_response
from .frame_clock import extract_frame_clock
from .opening_loadout import extract_opening_loadout
from .opening_dialogue import extract_opening_dialogue, extract_arrival_dialogue
from .text_aliases import extract_text_aliases
from .font_bindings import extract_font_bindings
from .portrait_textures import extract_portrait_textures
from .speaker_bindings import extract_speaker_bindings
from .image_regions import extract_image_bindings
from .portrait_layers import extract_portrait_layers
from .opening_actors import extract_opening_actors
from .player_initialization import extract_player_initialization
from .npc_activation import extract_npc_activation
from .opening_npc_guidance import extract_opening_npc_guidance
from .npc_holding import extract_npc_holding
from .npc_hostility import extract_npc_hostility
from .player_recharge import extract_player_recharge
from .player_repair import extract_player_repair
from .flight_player_cache import extract_flight_player_cache
from .npc_routes import extract_npc_routes
from .npc_construction import extract_npc_construction
from .npc_destruction import extract_npc_destruction, extract_npc_destruction_audio
from .weapon_audio import extract_weapon_audio
from .radio_audio import extract_radio_audio
from .engine_audio import extract_engine_audio
from .npc_death_accounting import extract_npc_death_accounting
from .npc_hull import extract_npc_hull
from .npc_scanner import extract_npc_scanner
from .arrival_staging import extract_arrival_staging
from .arrival_environment import extract_arrival_environment
from .arrival_actor_motion import extract_arrival_actor_motion
from .arrival_actor_construction import extract_arrival_actor_construction
from .arrival_world_initialization import extract_arrival_world_initialization
from .opening_handoff import extract_opening_handoff
from .arrival_session import extract_arrival_session
from .station_entry import extract_station_entry
from .first_flight import extract_first_flight
from .mining_briefing import extract_mining_briefing
from .mining_drill import extract_mining_drill
from .mining_targeting import extract_mining_targeting
from .mining_approach import extract_mining_approach
from .mining_session import extract_mining_session
from .flight_notices import extract_flight_notices
from .mining_objective import extract_mining_objective
from .station_exterior import extract_station_exterior
from .station_autopilot import extract_station_autopilot
from .station_flight import extract_station_flight
from .station_return import extract_station_return
from .full_hold_departure import extract_full_hold_departure
from .full_hold_flight import extract_full_hold_flight
from .game_over_presentation import extract_game_over_presentation
from .player_destruction import extract_player_destruction
from .full_hold_particles import extract_full_hold_particles
from .full_hold_return import extract_full_hold_return
from .station_equipment import extract_station_equipment
from .combat_training import extract_combat_training
from .combat_training_control import extract_combat_training_control
from .combat_training_weapons import extract_combat_training_weapons
from .combat_training_destruction import extract_combat_training_destruction
from .combat_training_visuals import extract_combat_training_visuals
from .full_hold_appearance import extract_full_hold_appearance
from .full_hold_story import extract_full_hold_story
from .full_hold_destruction import extract_full_hold_destruction
from .full_hold_control import extract_full_hold_control
from .full_hold_pirate import extract_full_hold_pirate
from .station_departure import extract_station_departure
from .station_presentation import extract_station_presentation
from .desktop_text import extract_desktop_text
from .opening_escape import extract_opening_escape
from .opening_escape_camera import extract_opening_escape_camera
from .opening_player_motion import extract_opening_player_motion
from .opening_player_flight import extract_opening_player_flight
from .projectile_visuals import extract_projectile_visuals
from .projectile_impacts import extract_projectile_impacts
from .player_aim import extract_player_aim
from .opening_world_initialization import extract_opening_world_initialization
from .npc_flight import extract_npc_flight
from .opening_npc_weapons import extract_opening_npc_weapon
from .opening_staging import extract_opening_staging
from .opening_drift import extract_opening_drift
from .opening_clock import extract_opening_clock
from .flight_projection import extract_flight_projection
from .opening_camera import extract_opening_camera
from .camera_follow import extract_camera_follow

MAX_EXECUTABLE = 64 * 1024 * 1024
MAX_SECTIONS = 256
MAX_RECORDS = 20000
READER = 'resource-registration-v121'


class MachO:
    def __init__(self, source, edition):
        if not 28 <= len(source) <= MAX_EXECUTABLE:
            raise ContentError('Unsupported executable size')
        self.source_sha256 = hashlib.sha256(source).hexdigest()
        self.source_bytes = len(source)
        self.slice_offset = 0
        cpu = 12 if edition == 'ios-hd' else 0x1000007
        if edition not in ('ios-hd', 'mac-full-hd'):
            raise ContentError('Unsupported executable content profile')
        if source[:4] == b'\xca\xfe\xba\xbe':
            count = struct.unpack_from('>I', source, 4)[0]
            if not 1 <= count <= 16 or 8 + 20 * count > len(source):
                raise ContentError('Invalid Mach-O slice index')
            slices = [struct.unpack_from('>5I', source, 8 + 20 * i) for i in range(count)]
            selected = [row for row in slices if row[0] == cpu]
            if len(selected) != 1:
                raise ContentError('Expected one supported architecture slice')
            _, _, offset, size, _ = selected[0]
            if offset < 8 + 20 * count or size < 28 or offset + size > len(source):
                raise ContentError('Invalid Mach-O slice extent')
            self.slice_offset = offset
            source = source[offset:offset + size]
        self.data = source
        magic, found_cpu, _, file_type, count, command_size, _ = self.unpack('<7I', 0)
        is64 = cpu == 0x1000007
        if magic != (0xfeedfacf if is64 else 0xfeedface) or found_cpu != cpu or file_type != 2:
            raise ContentError('Unsupported Mach-O executable architecture/layout')
        self.architecture = 'x86_64' if is64 else 'armv7'
        start = 32 if is64 else 28
        end = start + command_size
        if not 1 <= count <= 256 or end > len(self.data):
            raise ContentError('Invalid Mach-O load commands')
        self.sections = []
        position = start
        for _ in range(count):
            if position + 8 > end:
                raise ContentError('Truncated Mach-O load command')
            command, size = self.unpack('<2I', position)
            if size < 8 or size % 4 or position + size > end:
                raise ContentError('Invalid Mach-O load command extent')
            if command == (0x19 if is64 else 1):
                header, stride, count_offset = (72, 80, 64) if is64 else (56, 68, 48)
                if size < header:
                    raise ContentError('Truncated Mach-O segment')
                section_count = self.unpack('<I', position + count_offset)[0]
                if section_count > MAX_SECTIONS or header + stride * section_count != size:
                    raise ContentError('Invalid Mach-O section index')
                for i in range(section_count):
                    at = position + header + stride * i
                    name = self.data[at:at + 16].split(b'\0', 1)[0]
                    segment = self.data[at + 16:at + 32].split(b'\0', 1)[0]
                    address, length, offset = self.unpack('<QQI' if is64 else '<3I', at + 32)
                    # Zero-fill sections are not file-backed input.
                    if offset:
                        if offset < end or offset + length > len(self.data):
                            raise ContentError('Mach-O section outside file-backed data')
                        self.sections.append(dict(name=name, segment=segment, address=address,
                                                  length=length, offset=offset))
                if len(self.sections) > MAX_SECTIONS:
                    raise ContentError('Too many Mach-O sections')
            if command in (0x21, 0x2c):
                if size < 20 or self.unpack('<I', position + 16)[0]:
                    raise ContentError('Encrypted executable declarations are unsupported')
            position += size
        if position != end:
            raise ContentError('Mach-O command sizes do not match header')
        for key in ('__text', '__cstring'):
            matches = [s for s in self.sections if s['segment'] == b'__TEXT' and s['name'] == key.encode()]
            if len(matches) != 1:
                raise ContentError('Missing or ambiguous Mach-O ' + key)
            setattr(self, key[2:], matches[0])

    def unpack(self, fmt, offset):
        size = struct.calcsize(fmt)
        if offset < 0 or offset + size > len(self.data):
            raise ContentError('Truncated Mach-O scalar')
        return struct.unpack_from(fmt, self.data, offset)

    def resource_string(self, address):
        s = self.cstring
        if not s['address'] <= address < s['address'] + s['length']:
            return None
        position = s['offset'] + address - s['address']
        if position > s['offset'] and self.data[position - 1] != 0:
            return None
        end = self.data.find(b'\0', position, min(position + 1025, s['offset'] + s['length']))
        if end < 0:
            return None
        try:
            value = self.data[position:end].decode('utf-8', errors='strict')
        except UnicodeError:
            return None
        if not value.startswith('data/') or not value.endswith(('.aem', '.aei')):
            return None
        safe_name(re.sub(r"/+", "/", value))
        return value


def mac_records(mach, checkpoint):
    # String copy into the payload object, followed by ID/type/sentinel/payload
    # fields in one registration record. The optional float is texture metadata.
    pattern = re.compile(
        rb'\x49\x89\x04\x24\x48\x8d\x35(.{4})\x48\x89\xc7\x48\x89\xda\xe8.{4}'
        rb'(?:\x41\xc7\x44\x24\x08(.{4}))?\x66\x41\xc7\x07(.{2})'
        rb'\x41\xc7\x47\x04(.{4})\x41\xc7\x47\x08\xff\xff\xff\xff\x4d\x89\x67\x10', re.S)
    section = mach.text
    text = mach.data[section['offset']:section['offset'] + section['length']]
    rows = []
    metadata = re.compile(rb'\x66\x41\xc7\x44\x24\x08(.{2})\x41\xc6\x44\x24\x0a(.)'
                          rb'\x48\x8d\x3d(.{4})\xe8.{4}\x89\xc3\xff\xc3\x48\x89\xdf\xe8.{4}$', re.S)
    for match in pattern.finditer(text):
        checkpoint('Reading x86-64 resource declarations', match.start() / len(text))
        displacement = struct.unpack('<i', match[1])[0]
        address = section['address'] + match.start() + 11 + displacement
        path = mach.resource_string(address)
        if path is not None:
            identifier = struct.unpack('<H', match[3])[0]
            kind = struct.unpack('<I', match[4])[0]
            row = record(mach, section['offset'] + match.start(), identifier, kind, path)
            if kind == 2 and path.endswith('.aei') and match[2] is not None:
                row['texture_parameter_bits'] = struct.unpack('<I', match[2])[0]
            prefix_start = max(0, match.start() - 64)
            prefix = metadata.search(text[prefix_start:match.start()])
            if kind == 4 and path.endswith('.aem') and prefix is not None:
                first_address = section['address'] + prefix_start + prefix.start() + 21 + struct.unpack('<i', prefix[3])[0]
                if mach.resource_string(first_address) == path:
                    row['material_id'] = struct.unpack('<H', prefix[1])[0]
                    row['mesh_flags'] = prefix[2][0]
            rows.append(row)
        if len(rows) > MAX_RECORDS:
            raise ContentError('Too many resource declarations')
    # A second compiler layout registers quality-selectable textures directly.
    # Preserve every declaration; quality compatibility is verified separately.
    texture_pattern = re.compile(
        rb'\x48\x8d\x3d(.{4})\xe8.{4}\x89\xc3\xff\xc3\x48\x89\xdf\xe8.{4}'
        rb'\x49\x89\x07\x48\x8d\x35(.{4})\x48\x89\xc7\x48\x89\xda\xe8.{4}'
        rb'\x41\xc7\x47\x08(.{4})\x66\x41\xc7\x06(.{2})'
        rb'\x41\xc7\x46\x04\x02\x00\x00\x00\x41\xc7\x46\x08\xff\xff\xff\xff\x4d\x89\x7e\x10', re.S)
    for match in texture_pattern.finditer(text):
        checkpoint('Reading x86-64 texture variants', match.start() / len(text))
        first = section['address'] + match.start() + 7 + struct.unpack('<i', match[1])[0]
        second = section['address'] + match.start() + 34 + struct.unpack('<i', match[2])[0]
        path = mach.resource_string(first)
        if path is None or not path.endswith('.aei') or mach.resource_string(second) != path:
            continue
        row = record(mach, section['offset'] + match.start(), struct.unpack('<H', match[4])[0], 2, path)
        row['texture_parameter_bits'] = struct.unpack('<I', match[3])[0]
        rows.append(row)
        if len(rows) > MAX_RECORDS:
            raise ContentError('Too many resource declarations')
    return rows


def thumb_immediate(data, offset, opcode):
    if offset < 0 or offset + 4 > len(data):
        return None
    first, second = struct.unpack_from('<2H', data, offset)
    # MOVW/MOVT r1, #imm16, with only immediate bits variable.
    if first & 0xfbf0 != opcode or second & 0x8f00 != 0x0100:
        return None
    return ((first & 15) << 12) | ((first & 0x400) << 1) | ((second & 0x7000) >> 4) | (second & 255)


def ios_records(mach, checkpoint):
    try:
        import capstone
        from capstone.arm_const import ARM_OP_IMM, ARM_OP_REG, ARM_REG_R1
    except ImportError as error:
        raise ContentError('Install tools/requirements-bindings.txt for ARM static declaration reading') from error
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    decoder.detail = True
    section = mach.text
    text = mach.data[section['offset']:section['offset'] + section['length']]
    rows = []
    # Candidate: the adjacent PC-relative string-address constant and its copy
    # destination. Disassemble only the bounded declaration, never the program.
    for match in re.finditer(re.escape(b'\x79\x44\x10\x60'), text):
        start = match.start() - 8
        if start < 4 or start % 2:
            continue
        low = thumb_immediate(text, start, 0xf240)
        high = thumb_immediate(text, start + 4, 0xf2c0)
        if low is None or high is None:
            continue
        path = mach.resource_string(((high << 16) | low) + section['address'] + start + 12)
        if path is None:
            continue
        checkpoint('Reading ARM resource declarations', start / len(text))
        ins = list(decoder.disasm(text[start:start + 112], section['address'] + start))
        if len(ins) < 12 or ins[4].mnemonic not in ('ldr', 'ldr.w') or not ins[4].op_str.startswith('r2, [sp') or ins[5].mnemonic != 'blx':
            continue
        previous = list(decoder.disasm(text[start - 4:start], section['address'] + start - 4))
        # The actual payload pointer must be the last instruction before MOVW.
        if not previous or not previous[-1].op_str.startswith('r2, [') or previous[-1].mnemonic not in ('ldr', 'ldr.w'):
            previous = list(decoder.disasm(text[start - 2:start], section['address'] + start - 2))
        if not previous or previous[-1].mnemonic not in ('ldr', 'ldr.w') or not previous[-1].op_str.startswith('r2, ['):
            continue
        payload_memory = previous[-1].op_str.split(', ', 1)[1]
        for k in range(6, min(22, len(ins) - 4)):
            if ins[k].op_str != 'r1, [r0]' or ins[k].mnemonic != 'strh':
                continue
            if any(i.mnemonic.startswith(('b', 'it', 'cb', 'pop')) for i in ins[6:k]):
                break
            loads = [i for i in ins[6:k] if i.mnemonic in ('ldr', 'ldr.w') and i.op_str.startswith('r0, [')]
            writes = [i for i in ins[6:k] if i.operands and i.operands[0].type == ARM_OP_REG and i.operands[0].reg == ARM_REG_R1 and i.mnemonic.startswith('mov')]
            if not loads or not writes:
                break
            value = writes[-1]
            if value.mnemonic not in ('movw', 'mov.w', 'movs') or len(value.operands) != 2 or value.operands[1].type != ARM_OP_IMM:
                break
            between = ins[ins.index(value) + 1:k]
            if any(not ((i.mnemonic in ('ldr', 'ldr.w') and i.op_str.startswith('r0, ['))
                            or (i.mnemonic == 'add.w' and i.op_str.startswith('r8, sp, #'))) for i in between):
                break
            identifier = value.operands[1].imm
            kind_ins, reload, store = ins[k + 1:k + 4]
            if kind_ins.mnemonic != 'movs' or not kind_ins.op_str.startswith('r1, #') or reload.op_str != loads[-1].op_str or reload.mnemonic not in ('ldr', 'ldr.w') or store.mnemonic != 'str' or store.op_str != 'r1, [r0, #4]':
                break
            # Require the record's payload field to refer to that same copied
            # string object, rather than accepting a nearby unrelated ID store.
            tail = ins[k + 4:k + 15]
            linked = any(a.mnemonic in ('ldr', 'ldr.w') and a.op_str in ('r1, ' + payload_memory, 'r2, ' + payload_memory)
                         and b.mnemonic == 'str' and b.op_str == a.op_str[:2] + ', [r0, #0xc]'
                         for a, b in zip(tail, tail[1:]))
            if not linked:
                break
            row = record(mach, section['offset'] + start, identifier, int(kind_ins.operands[1].imm), path)
            if row['registration_type'] == 4 and row['kind'] == 'mesh':
                row.update(ios_mesh_metadata(mach, start, path, decoder))
            rows.append(row)
            break
        if len(rows) > MAX_RECORDS:
            raise ContentError('Too many resource declarations')
    return rows


def record(mach, offset, identifier, kind, path):
    if not 0 <= identifier <= 65535 or not 0 <= kind <= 255:
        raise ContentError(f'Unsupported resource declaration: id={identifier}, kind={kind}, path={path}, offset={offset}')
    return {'id': identifier, 'registration_type': kind, 'kind': 'texture' if path.endswith('.aei') else 'mesh',
            'resource': 'resources/' + re.sub(r'/+', '/', path), 'source_path': path,
            'source_offset': offset + mach.slice_offset}


def extract(source, edition, checkpoint=lambda *_: None):
    mach = MachO(source, edition)
    rows = (ios_records if edition == 'ios-hd' else mac_records)(mach, checkpoint)
    if not rows:
        raise ContentError('No supported resource declaration templates found')
    # Repeated declarations and alternatives remain explicit. No game branches
    # are followed to choose an active registration or variant.
    rows.sort(key=lambda row: (row['id'], row['resource'], row['source_offset']))
    hangars = extract_hangars(mach, rows)
    ship_models = extract_ship_models(mach, rows, 64 if edition == 'ios-hd' else 61)
    cruise = extract_cruise(mach)
    rotation = extract_manual_rotation(mach, cruise)
    pilot = extract_pilot_response(mach, rotation)
    vehicle = extract_vehicle_response(mach, pilot)
    if vehicle:
        vehicle['audio'] = extract_engine_audio(mach, vehicle, rotation)
    staging = extract_opening_staging(mach)
    camera = extract_opening_camera(mach, staging)
    drift = extract_opening_drift(mach, camera)
    actors = extract_opening_actors(mach)
    if actors:
        actors['player_initialization'] = extract_player_initialization(mach, actors, vehicle, staging)
    if staging:
        staging['player_motion'] = extract_opening_player_motion(mach, staging, camera, cruise, actors)
        staging['player_flight'] = extract_opening_player_flight(mach, staging, actors, rotation, pilot)
    if actors.get('npc_initialization'):
        actors['npc_initialization']['activation'] = extract_npc_activation(mach, actors, camera)
        actors['npc_initialization']['flight'] = extract_npc_flight(mach, actors)
    opening = extract_opening_loadout(mach, vehicle)
    weapons = extract_weapon_parameters(mach, vehicle, opening)
    if actors.get('npc_initialization'):
        actors['npc_initialization']['primary_weapon'] = extract_opening_npc_weapon(mach, actors, opening, weapons)
        actors['npc_initialization']['guidance'] = extract_opening_npc_guidance(mach, actors)
    if staging:
        staging['projectile_visuals'] = extract_projectile_visuals(mach, staging, actors, opening)
        staging['projectile_impacts'] = extract_projectile_impacts(mach, staging, actors, weapons)
    lights = extract_ship_lights(mach, ship_models)
    lod = extract_ship_lod(mach, ship_models, lights)
    projection = extract_flight_projection(mach)
    if staging:
        staging['player_aim'] = extract_player_aim(mach, staging, projection)
    if actors.get('npc_initialization'):
        actors['npc_initialization']['holding'] = extract_npc_holding(mach, actors, projection)
        actors['npc_initialization']['hostility'] = extract_npc_hostility(mach, actors)
        actors['npc_initialization']['routes'] = extract_npc_routes(mach, actors)
        actors['npc_initialization']['construction'] = extract_npc_construction(mach, actors, vehicle)
        actors['npc_initialization']['destruction'] = extract_npc_destruction(mach, actors)
        actors['npc_initialization']['destruction_audio'] = extract_npc_destruction_audio(mach, actors)
        actors['npc_initialization']['death_accounting'] = extract_npc_death_accounting(mach, actors, weapons)
    sky = extract_opening_sky(mach, projection)
    colors = extract_environment_colors(mach, sky)
    if sky:
        sky["planet_resources"] = extract_planet_resources(mach, sky, colors)
        sky["sun_flares"] = extract_sun_flares(mach, sky)
    population = extract_scenery_population(mach)
    if actors.get('npc_initialization'):
        actors['npc_initialization']['world_initialization'] = extract_opening_world_initialization(mach, actors, opening, population)
        actors['npc_initialization']['hull'] = extract_npc_hull(mach, actors)
    if staging:
        staging['npc_scanner'] = extract_npc_scanner(mach, staging, actors)
        staging['escape'] = extract_opening_escape(mach, staging)
        staging['escape_camera'] = extract_opening_escape_camera(mach, staging)
    particles = extract_damage_particles(mach)
    if particles:
        particles['owners'] = extract_damage_particle_owners(mach, actors, staging)
    scenery_resources = extract_scenery_resources(mach, population)
    clock = extract_opening_clock(mach, drift, opening)
    if actors.get('player_initialization'):
        actors['player_initialization']['recharge'] = extract_player_recharge(mach, actors, vehicle, clock)
        actors['player_initialization']['repair'] = extract_player_repair(mach, actors, vehicle, opening)
    if weapons:
        weapons['audio'] = extract_weapon_audio(mach, weapons, actors, staging)
    dialogue = extract_opening_dialogue(mach)
    arrival_dialogue = extract_arrival_dialogue(mach, dialogue)
    arrival_staging = extract_arrival_staging(mach, staging, arrival_dialogue, actors)
    if actors.get('player_initialization'):
        actors['player_initialization']['flight_cache'] = extract_flight_player_cache(mach, opening, actors, arrival_staging)
    arrival_environment = extract_arrival_environment(mach, sky, actors, arrival_staging)
    arrival_actor_motion = extract_arrival_actor_motion(mach, arrival_staging, actors, arrival_environment)
    arrival_actor_construction = extract_arrival_actor_construction(mach, arrival_staging, actors, arrival_environment)
    arrival_world_initialization = extract_arrival_world_initialization(mach, arrival_staging, actors, arrival_actor_construction, arrival_environment)
    opening_handoff = extract_opening_handoff(mach, arrival_staging, actors, arrival_world_initialization)
    arrival_session = extract_arrival_session(mach, arrival_staging, arrival_actor_motion, arrival_world_initialization, opening_handoff)
    station_entry = extract_station_entry(mach, arrival_staging, arrival_session)
    station_departure = extract_station_departure(mach, arrival_staging, station_entry, actors.get('player_initialization', {}))
    station_presentation = extract_station_presentation(mach, arrival_staging, station_entry)
    desktop_text = extract_desktop_text(mach, arrival_staging)
    first_flight = extract_first_flight(mach, arrival_staging, station_departure, arrival_environment, arrival_world_initialization)
    fonts = extract_font_bindings(mach, rows)
    if dialogue:
        dialogue['voice'] = extract_radio_audio(mach, dialogue, fonts)
    if arrival_dialogue:
        arrival_dialogue['voice'] = extract_radio_audio(mach, arrival_dialogue, fonts)
    mining_targeting = extract_mining_targeting(mach, arrival_staging, first_flight)
    mining_approach = extract_mining_approach(mach, arrival_staging, mining_targeting)
    mining_drill = extract_mining_drill(mach, arrival_staging, first_flight)
    mining_briefing = extract_mining_briefing(mach, arrival_staging, first_flight, station_presentation, desktop_text)
    station_return = extract_station_return(mach, arrival_staging, first_flight)
    full_hold_departure = extract_full_hold_departure(mach, arrival_staging, station_departure, station_return)
    full_hold_flight = extract_full_hold_flight(mach, arrival_staging, full_hold_departure, first_flight, actors)
    full_hold_pirate = extract_full_hold_pirate(mach, arrival_staging, full_hold_flight, actors, opening_handoff)
    full_hold_control = extract_full_hold_control(mach, arrival_staging, full_hold_pirate, actors)
    mining_objective = extract_mining_objective(mach, arrival_staging, first_flight, station_presentation, desktop_text, mining_briefing)
    full_hold_destruction = extract_full_hold_destruction(mach, arrival_staging, full_hold_control, actors)
    full_hold_story = extract_full_hold_story(mach, arrival_staging, full_hold_flight, mining_briefing, mining_objective)
    player_destruction = extract_player_destruction(mach, arrival_staging, full_hold_flight, actors)
    full_hold_return = extract_full_hold_return(mach, arrival_staging, station_return, full_hold_story)
    station_equipment = extract_station_equipment(mach, arrival_staging, full_hold_return)
    combat_training = extract_combat_training(mach, arrival_staging, station_equipment, actors)
    combat_training_control = extract_combat_training_control(mach, arrival_staging, combat_training, actors)
    combat_training_weapons = extract_combat_training_weapons(mach, arrival_staging, combat_training, combat_training_control, station_equipment, actors, weapons)
    return {'reader': READER, 'architecture': mach.architecture,
            'source_executable_sha256': mach.source_sha256,
            'source_executable_bytes': mach.source_bytes, 'registrations': rows,
            'materials': extract_materials(mach, checkpoint),
            'ship_models': ship_models,
            'hangars': hangars,
            'ship_placement': extract_ship_placement(mach, hangars, 64 if edition == 'ios-hd' else 61),
            'ship_lights': lights,
            'ship_lod': lod,
            'lod_refresh': extract_lod_refresh(mach, lod),
            'cruise': cruise,
            'manual_rotation': rotation,
            'pilot_response': pilot,
            'vehicle_response': vehicle,
            'frame_clock': extract_frame_clock(mach, pilot),
            'opening_loadout': opening,
            'opening_dialogue': dialogue,
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
            'mining_drill': mining_drill,
            'mining_targeting': mining_targeting,
            'mining_approach': mining_approach,
            'mining_session': extract_mining_session(mach, arrival_staging, mining_approach, mining_drill),
            'flight_notices': extract_flight_notices(mach, arrival_staging, first_flight),
            'mining_objective': mining_objective,
            'station_return': station_return,
            'full_hold_departure': full_hold_departure,
            'full_hold_flight': full_hold_flight,
            'full_hold_pirate': full_hold_pirate,
            'full_hold_story': full_hold_story,
            'player_destruction': player_destruction,
            'full_hold_particles': extract_full_hold_particles(mach, arrival_staging, full_hold_flight, player_destruction, particles),
            'game_over_presentation': extract_game_over_presentation(mach, arrival_staging, player_destruction),
            'full_hold_return': full_hold_return,
            'station_equipment': station_equipment,
            'combat_training': combat_training,
            'combat_training_control': combat_training_control,
            'combat_training_weapons': combat_training_weapons,
            'combat_training_destruction': extract_combat_training_destruction(mach, arrival_staging, combat_training, combat_training_control, combat_training_weapons, actors),
            'combat_training_visuals': extract_combat_training_visuals(mach, arrival_staging, combat_training_weapons, staging),
            'full_hold_appearance': extract_full_hold_appearance(mach, arrival_staging, full_hold_story, full_hold_destruction),
            'full_hold_control': full_hold_control,
            'full_hold_destruction': full_hold_destruction,
            'station_flight': extract_station_flight(mach, arrival_staging, first_flight),
            'station_autopilot': extract_station_autopilot(mach, arrival_staging, first_flight),
            'station_exterior': extract_station_exterior(mach, arrival_staging, first_flight),
            'mining_briefing': mining_briefing,
            'station_presentation': station_presentation,
            'desktop_text': desktop_text,
            'text_aliases': extract_text_aliases(mach),
            'font_bindings': fonts,
            'portrait_textures': extract_portrait_textures(mach),
            'speaker_bindings': extract_speaker_bindings(mach),
            'image_regions': extract_image_bindings(mach),
            'portrait_layers': extract_portrait_layers(mach),
            'opening_actors': actors,
            'opening_staging': staging,
            'opening_camera': camera,
            'opening_clock': clock,
            'opening_drift': drift,
            'flight_projection': projection,
            'opening_sky': sky,
            'damage_particles': particles,
            'scenery_population': population,
            'scenery_resources': scenery_resources,
            'scenery_effects': extract_scenery_effects(mach, scenery_resources),
            'environment_colors': colors,
            'surface_material': extract_surface_material(mach, colors),
            'weapon_parameters': weapons,
            'reflection_selection': extract_reflection_selection(mach, projection, sky),
            'camera_follow': extract_camera_follow(mach, camera)}
