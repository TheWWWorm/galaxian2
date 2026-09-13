"""Bounded FMOD Designer 0x45 event metadata reader, independent of FMOD.

The RIFF/LGCY layout follows vgmstream's fsb_fev.h format research (ISC;
see THIRD_PARTY_NOTICES). All output is authored data, never executable code.
"""
import math
import struct

from .formats import ContentError

MAX_BYTES = 8 * 1024 * 1024
MAX_RECORDS = 20000


class Cursor:
    def __init__(self, data, start=0, end=None):
        self.data, self.pos = data, start
        self.end = len(data) if end is None else end

    def take(self, length):
        if not 0 <= length <= self.end - self.pos:
            raise ContentError('Truncated FEV record')
        value = self.data[self.pos:self.pos + length]
        self.pos += length
        return value

    def values(self, layout):
        result = struct.unpack('<' + layout, self.take(struct.calcsize('<' + layout)))
        if any(isinstance(v, float) and not math.isfinite(v) for v in result):
            raise ContentError('Non-finite FEV parameter')
        return result

    def u32(self):
        return self.values('I')[0]

    def count(self, maximum=MAX_RECORDS):
        result = self.u32()
        if result > maximum:
            raise ContentError('FEV record count exceeds its budget')
        return result

    def string(self):
        size = self.count(4096)
        if not size:
            return ''
        value = self.take(size)
        if value[-1] != 0 or b'\0' in value[:-1]:
            raise ContentError('Invalid FEV string terminator')
        try:
            return value[:-1].decode('utf-8')
        except UnicodeDecodeError as e:
            raise ContentError('Invalid FEV UTF-8 string') from e

    def properties(self):
        result = []
        for _ in range(self.count(64)):
            name, kind = self.string(), self.u32()
            if kind not in (0, 1, 2):
                raise ContentError('Unsupported FEV user property')
            value = self.string() if kind == 2 else self.values('i' if kind == 0 else 'f')[0]
            result.append({'name': name, 'type': kind, 'value': value})
        return result

    def done(self):
        if self.pos != self.end:
            raise ContentError('Unexpected trailing FEV data')


def chunks(cursor):
    result = {}
    while cursor.pos < cursor.end:
        tag = cursor.take(4)
        size, offset = cursor.u32(), cursor.pos
        if tag in result:
            raise ContentError('Repeated FEV chunk')
        result[tag] = (offset, size)
        cursor.take(size)
        if size & 1:
            cursor.take(1)
    return result


def read(data):
    """Normalize the supported RIFF FEV layout, with no resource-name guesses."""
    if not 32 <= len(data) <= MAX_BYTES:
        raise ContentError('Empty or oversized FEV event file')
    data = bytes(data)
    cursor = Cursor(data)
    if cursor.take(4) != b'RIFF' or cursor.u32() != len(data) - 8 or cursor.take(4) != b'FEV ':
        raise ContentError('Unsupported FEV envelope')
    top = chunks(cursor)
    if set(top) != {b'FMT ', b'LIST'}:
        raise ContentError('Unsupported FEV project chunks')

    def part(table, tag):
        if tag not in table:
            raise ContentError('Missing FEV ' + tag.decode('ascii') + ' chunk')
        offset, size = table[tag]
        return Cursor(data, offset, offset + size)

    version = part(top, b'FMT ')
    if version.u32() != 0x450000:
        raise ContentError('Unsupported FEV version; only Designer 0x45 is verified')
    version.done()
    project = part(top, b'LIST')
    if project.take(4) != b'PROJ':
        raise ContentError('Unsupported FEV list type')
    table = chunks(project)
    if set(table) != {b'OBCT', b'PROP', b'LGCY', b'EPRP', b'STRR', b'LANG'}:
        raise ContentError('Unsupported FEV project record set')
    names = part(table, b'STRR')
    count = names.count()
    offsets = names.values('I' * count)
    raw = names.take(names.end - names.pos)
    strings = []
    for offset in offsets:
        if not 0 <= offset < len(raw):
            raise ContentError('FEV string offset outside its table')
        end = raw.find(b'\0', offset, min(offset + 4096, len(raw)))
        if end < 0:
            raise ContentError('Unterminated FEV indexed string')
        try:
            strings.append(raw[offset:end].decode('utf-8'))
        except UnicodeDecodeError as e:
            raise ContentError('Invalid indexed FEV UTF-8') from e
    points = part(table, b'EPRP')
    point_table = [list(points.values('ffI')) for _ in range(points.count())]
    points.done()
    language = part(table, b'LANG')
    languages = [language.string() for _ in range(language.count(32))]
    default_language = language.u32()
    language.done()
    if not languages or default_language >= len(languages):
        raise ContentError('Invalid FEV default language')
    r = part(table, b'LGCY')

    def indexed():
        index = r.u32()
        if index >= len(strings):
            raise ContentError('Invalid FEV string index')
        return strings[index]

    def category(depth=0):
        if depth > 16:
            raise ContentError('FEV category nesting exceeds its budget')
        name = r.string()
        volume, pitch, maximum, flags = r.values('ffII')
        return {'name': name, 'volume': volume, 'pitch': pitch,
                'max_playbacks': maximum, 'flags': flags,
                'children': [category(depth + 1) for _ in range(r.count(64))]}

    def sound():
        start = r.pos
        keys = ['sound_def', 'x', 'width', 'flags2', 'flags', 'loop_count',
                'auto_pitch', 'auto_pitch_reference', 'auto_pitch_zero', 'fine_tune',
                'volume', 'fade_in', 'fade_out', 'fade_in_type', 'fade_out_type']
        return {'source_offset': start, **dict(zip(keys, r.values('HffIIiIffffffII')))}

    def envelope():
        start = r.pos
        name, parent = r.values('HH')
        dsp = r.string()
        parameter, flags, flags2 = r.values('III')
        indices = r.values('I' * r.count(256))
        if any(i >= len(point_table) for i in indices):
            raise ContentError('Invalid FEV envelope point index')
        parameter_index, trailing = r.values('II')
        return {'source_offset': start, 'name_index': name, 'parent_index': parent,
                'dsp': dsp, 'dsp_parameter': parameter, 'flags': flags, 'flags2': flags2,
                'points': [point_table[i] for i in indices],
                'parameter_index': parameter_index, 'trailing': trailing}

    events = []
    groups = []

    def event(path):
        if len(events) >= MAX_RECORDS:
            raise ContentError('Too many FEV events')
        start, kind, name = r.pos, r.u32(), indexed()
        guid = r.take(16).hex()
        keys = ['volume', 'pitch', 'pitch_random', 'volume_random', 'priority', 'max_playbacks',
                'steal_priority', 'mode', 'min_distance', 'max_distance', 'distance_filter',
                'distance_filter_frequency', 'flags']
        properties = dict(zip(keys, r.values('ffffIIIIffffI')))
        properties['speaker_levels'] = list(r.values('8f'))
        keys = ['cone_inside', 'cone_outside', 'cone_outside_volume', 'max_playbacks_behavior',
                'doppler', 'reverb_dry_db', 'reverb_wet_db', 'speaker_spread',
                'fade_in_ms', 'fade_out_ms', 'spawn_intensity', 'spawn_random', 'pan_level',
                'position_random_min', 'position_random_max']
        properties.update(zip(keys, r.values('fffIffffIIfffff')))
        result = {'id': len(events), 'name': name, 'path': path + '/' + name, 'guid': guid,
                  'source_offset': start, 'type': kind, 'properties': properties}
        if kind & 0x18 == 8:
            layers = []
            for _ in range(r.count(64)):
                flags, priority, parameter, sound_count, envelope_count = r.values('5H')
                if sound_count > 256 or envelope_count > 64:
                    raise ContentError('FEV layer exceeds its budget')
                layers.append({'flags': flags, 'priority': priority, 'parameter': parameter,
                               'sounds': [sound() for _ in range(sound_count)],
                               'envelopes': [envelope() for _ in range(envelope_count)]})
            parameters = []
            for _ in range(r.count(64)):
                parameter_name = indexed()
                velocity, low, high, flags, seek, envelopes = r.values('fffIfI')
                parameters.append({'name': parameter_name, 'velocity': velocity, 'min': low,
                                   'max': high, 'flags': flags, 'seek_speed': seek, 'envelopes': envelopes,
                                   'sustain_points': list(r.values('I' * r.count(256)))})
            result.update(layers=layers, parameters=parameters, user_properties=r.properties())
        elif kind & 0x18 == 16:
            result['simple_flags'] = r.u32()
            result['sound'] = sound()
        else:
            raise ContentError('Unsupported FEV event type')
        result['categories'] = [r.string() for _ in range(r.count(16))]
        result['source_bytes'] = r.pos - start
        events.append(result)

    def group(parent, depth=0):
        if depth > 16 or len(groups) >= MAX_RECORDS:
            raise ContentError('FEV group nesting exceeds its budget')
        path = parent + '/' + indexed()
        groups.append({'path': path, 'properties': r.properties()})
        child_count, event_count = r.count(256), r.count()
        for _ in range(child_count):
            group(path, depth + 1)
        for _ in range(event_count):
            event(path)

    r.take(8)  # Platform-specific pool sizing, not playback semantics.
    project_name = r.string()
    bank_count, language_count = r.count(256), r.count(32)
    if language_count != len(languages):
        raise ContentError('FEV language tables disagree')
    banks = []
    for _ in range(bank_count):
        flags, streams = r.values('II')
        variants = [{'hash_prefix': r.take(8).hex(), 'suffix': indexed()} for _ in languages]
        name = r.string()
        if not name or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_' for c in name):
            raise ContentError('Unsupported FEV bank name')
        for variant in variants:
            if any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_' for c in variant['suffix']):
                raise ContentError('Unsupported FEV language suffix')
            variant['resource'] = 'resources/' + name + variant['suffix'] + '.fsb'
        banks.append({'name': name, 'flags': flags, 'max_streams': streams, 'variants': variants})
    categories = category()
    for _ in range(r.count(256)):
        group('')
    settings = []
    for _ in range(r.count(256)):
        keys = ['playlist_flags', 'spawn_min_ms', 'spawn_max_ms', 'maximum_polyphony', 'volume',
                'volume_random_method', 'volume_min', 'volume_max', 'volume_random', 'pitch',
                'pitch_random_method', 'pitch_min', 'pitch_max', 'pitch_random', 'pitch_recalc',
                'position_random_min', 'position_random_max', 'trigger_delay_min',
                'trigger_delay_max', 'spawn_count']
        settings.append(dict(zip(keys, r.values('IIIIfIffffIfffIffHHH'))))
    definitions = []
    for _ in range(r.count()):
        start, name, setting = r.pos, indexed(), r.u32()
        if setting >= len(settings):
            raise ContentError('Invalid FEV sound settings reference')
        entries = []
        for _ in range(r.count(256)):
            kind, weight = r.values('II')
            entry = {'type': kind, 'weight': weight}
            if kind == 0:
                entry['source_path'] = r.string()
                bank, index, length = r.values('III')
                if bank >= len(banks) or index > MAX_RECORDS:
                    raise ContentError('Invalid FEV sound bank reference')
                entry.update(bank=bank, index=index, length_ms=length)
            elif kind == 1:
                entry['oscillator'], entry['frequency'] = r.values('If')
            elif kind not in (2, 3):
                raise ContentError('Unsupported FEV sound entry')
            entries.append(entry)
        definitions.append({'name': name, 'settings': setting, 'entries': entries,
                            'source_offset': start, 'source_bytes': r.pos - start})
    reverbs = []
    for _ in range(r.count(64)):
        # Preserve named presets as unsupported metadata until the native DSP is verified.
        name = r.string()
        reverbs.append({'name': name, 'source_offset': r.pos, 'source_bytes': 132})
        r.take(132)
    if r.take(8) != b'\x08\0\0\0comp':
        raise ContentError('A nonempty FMOD music composition is not supported')
    r.done()
    for row in events:
        sounds = [row['sound']] if 'sound' in row else [s for layer in row['layers'] for s in layer['sounds']]
        if any(s['sound_def'] >= len(definitions) for s in sounds):
            raise ContentError('Invalid FEV sound definition reference')
        for layer in row.get('layers', []):
            if layer['parameter'] != 65535 and layer['parameter'] >= len(row['parameters']):
                raise ContentError('Invalid FEV layer parameter')
    return {'schema': 2, 'format': 'fmod-designer-0x45', 'project': project_name,
            'languages': languages, 'default_language': default_language, 'banks': banks,
            'categories': categories, 'groups': groups, 'events': events,
            'sound_settings': settings, 'sound_definitions': definitions,
            'unsupported_reverb_presets': reverbs}
