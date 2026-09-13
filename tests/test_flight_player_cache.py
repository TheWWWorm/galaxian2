"""Static declaration recognition with relocated synthetic layouts only."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import flight_player_cache as reader


def fixture(arch, shift=0):
    rows = reader.LAYOUTS[arch]
    low = min(v[1] for v in rows.values()) - 32
    high = max(v[1] + v[2] for v in rows.values()) + 32
    offset, bias = 128, 4096
    base = 0x800000 + shift - low
    raw = bytearray(offset + high - low)
    groups = {b'__text': [], b'__const': []}
    for section, delta, size, pattern in rows.values():
        raw[offset+delta-low:offset+delta-low+size] = bytes.fromhex(pattern)
        groups[section.encode()].append((delta, size))
    sections = []
    for name, spans in groups.items():
        if not spans:
            continue
        lo = min(v[0] for v in spans)-16
        hi = max(v[0]+v[1] for v in spans)+16
        sections.append({'segment': b'__TEXT', 'name': name, 'address': base+lo,
                         'offset': offset+lo-low, 'length': hi-lo})
    mach = SimpleNamespace(architecture=arch, slice_offset=bias, data=bytes(raw),
                           text=sections[0], sections=sections)
    opening = {'station_id': 78, 'provenance': {'declaration': {
        'offset': bias+offset-low, 'bytes': 376 if arch == 'x86_64' else 284}}}
    actors = {'player_initialization': {'repair': {'supported': True}}}
    arrival = {'campaign_cursor': 1}
    return mach, opening, actors, arrival, offset, low


class FlightPlayerCacheTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for arch in reader.LAYOUTS:
            for shift in [0, 0x1200000]:
                m, o, a, r, *_ = fixture(arch, shift)
                data = reader.extract_flight_player_cache(m, o, a, r)
                self.assertEqual({k: v for k, v in data.items() if k != 'provenance'}, reader.VALUES)
                for key, span in data['provenance'].items():
                    self.assertEqual(set(span), {'offset', 'bytes'})
                    self.assertEqual(span['offset'], o['provenance']['declaration']['offset'] + reader.LAYOUTS[arch][key][1])
                data['provenance'].clear()
                self.assertTrue(reader.extract_flight_player_cache(m, o, a, r)['provenance'])

    def test_altered_spans_and_truncation(self):
        for arch in reader.LAYOUTS:
            m, o, a, r, offset, low = fixture(arch)
            for name, (_, delta, size, _) in reader.LAYOUTS[arch].items():
                for index in [0, size-1]:
                    changed = copy.copy(m)
                    raw = bytearray(m.data)
                    raw[offset+delta-low+index] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_flight_player_cache(changed, o, a, r), {}, (arch, name, index))
            m.data = m.data[:offset+16]
            self.assertEqual(reader.extract_flight_player_cache(m, o, a, r), {})

    def test_context_and_bounds(self):
        for arch in reader.LAYOUTS:
            for key in ['player', 'repair', 'cursor', 'origin', 'size', 'section', 'arch', 'hazard_low', 'hazard_high']:
                m, o, a, r, *_ = fixture(arch)
                if key == 'player': a.clear()
                elif key == 'repair': a['player_initialization']['repair'] = {}
                elif key == 'cursor': r['campaign_cursor'] = 95
                elif key == 'origin': o['provenance']['declaration']['offset'] += 2
                elif key == 'size': o['provenance']['declaration']['bytes'] += 1
                elif key == 'section': m.sections[0]['segment'] = b'__DATA'
                elif key == 'arch': m.architecture = 'unsupported'
                elif key == 'hazard_low': o['station_id'] = 109
                else: o['station_id'] = 113
                self.assertEqual(reader.extract_flight_player_cache(m, o, a, r), {}, (arch, key))
