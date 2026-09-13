"""Static rescue environment recognition on relocated synthetic sections."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import arrival_environment as reader


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
    sky = {'planet_resources': {'supported': True}, 'provenance': {'opening': {
        'offset': bias+offset-low, 'bytes': 71 if arch == 'x86_64' else 62}}}
    actors = {'player_initialization': {'flight_cache': {'supported': True}}}
    arrival = {'campaign_cursor': 1}
    return mach, sky, actors, arrival, offset, low


class ArrivalEnvironmentTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for arch in reader.LAYOUTS:
            for shift in [0, 0x1200000]:
                m, s, a, r, *_ = fixture(arch, shift)
                data = reader.extract_arrival_environment(m, s, a, r)
                self.assertEqual({k: v for k, v in data.items() if k != 'provenance'}, reader.VALUES)
                for key, span in data['provenance'].items():
                    self.assertEqual(set(span), {'offset', 'bytes'})
                    self.assertEqual(span['offset'], s['provenance']['opening']['offset'] + reader.LAYOUTS[arch][key][1])
                data['provenance'].clear()
                self.assertTrue(reader.extract_arrival_environment(m, s, a, r)['provenance'])

    def test_altered_spans_and_truncation(self):
        for arch in reader.LAYOUTS:
            m, s, a, r, offset, low = fixture(arch)
            for name, (_, delta, size, _) in reader.LAYOUTS[arch].items():
                for index in [0, size-1]:
                    changed = copy.copy(m)
                    raw = bytearray(m.data)
                    raw[offset+delta-low+index] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_arrival_environment(changed, s, a, r), {}, (arch, name, index))
            m.data = m.data[:offset+16]
            self.assertEqual(reader.extract_arrival_environment(m, s, a, r), {})

    def test_context_and_bounds(self):
        for arch in reader.LAYOUTS:
            for key in ['player', 'cache', 'cursor', 'planet', 'origin', 'size', 'section', 'arch']:
                m, s, a, r, *_ = fixture(arch)
                if key == 'player': a.clear()
                elif key == 'cache': a['player_initialization']['flight_cache'] = {}
                elif key == 'cursor': r['campaign_cursor'] = 0
                elif key == 'planet': s['planet_resources'] = {}
                elif key == 'origin': s['provenance']['opening']['offset'] += 2
                elif key == 'size': s['provenance']['opening']['bytes'] += 1
                elif key == 'section': m.sections[0]['segment'] = b'__DATA'
                else: m.architecture = 'unsupported'
                self.assertEqual(reader.extract_arrival_environment(m, s, a, r), {}, (arch, key))
