"""Relocated rescue construction declarations, using synthetic text sections only."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import arrival_actor_construction as reader


def fixture(arch, shift=0):
    rows = reader.LAYOUTS[arch]
    low = min(v[0] for v in rows.values()) - 32
    high = max(v[0]+v[1] for v in rows.values()) + 32
    offset, bias = 128, 4096
    base = 0x800000 + shift - low
    raw = bytearray(offset+high-low)
    for delta, size, pattern in rows.values():
        raw[offset+delta-low:offset+delta-low+size] = bytes.fromhex(pattern)
    section = {'segment': b'__TEXT', 'name': b'__text', 'address': base+low,
               'offset': offset, 'length': high-low}
    mach = SimpleNamespace(architecture=arch, slice_offset=bias, data=bytes(raw),
                           text=section, sections=[section])
    arrival = {'campaign_cursor': 1, 'actor_kind': 3, 'actor_hull_id': 30,
               'provenance': {'actor': {'offset': bias+offset-low,
                                       'bytes': 315 if arch == 'x86_64' else 310}}}
    actors = {'npc_initialization': {'construction': {'supported': True}, 'routes': {'supported': True}}}
    return mach, arrival, actors, {'supported': True}, offset, low


class ArrivalActorConstructionTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for arch in reader.LAYOUTS:
            for shift in [0, 0x1200000]:
                m, a, n, e, *_ = fixture(arch, shift)
                data = reader.extract_arrival_actor_construction(m, a, n, e)
                self.assertEqual({k: v for k, v in data.items() if k != 'provenance'}, reader.VALUES)
                for key, span in data['provenance'].items():
                    self.assertEqual(set(span), {'offset', 'bytes'})
                    self.assertEqual(span['offset'], a['provenance']['actor']['offset']+reader.LAYOUTS[arch][key][0])
                data['provenance'].clear()
                self.assertTrue(reader.extract_arrival_actor_construction(m, a, n, e)['provenance'])

    def test_altered_spans_and_truncation(self):
        for arch in reader.LAYOUTS:
            m, a, n, e, offset, low = fixture(arch)
            for key, (delta, size, _) in reader.LAYOUTS[arch].items():
                for index in [0, size-1]:
                    changed = copy.copy(m)
                    raw = bytearray(m.data)
                    raw[offset+delta-low+index] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_arrival_actor_construction(changed, a, n, e), {}, (arch, key, index))
            m.data = m.data[:offset+16]
            self.assertEqual(reader.extract_arrival_actor_construction(m, a, n, e), {})

    def test_context_and_section_bounds(self):
        for arch in reader.LAYOUTS:
            for key in ['actors', 'construction', 'routes', 'environment', 'cursor', 'kind', 'hull', 'origin', 'size', 'section', 'arch']:
                m, a, n, e, *_ = fixture(arch)
                if key == 'actors': n.clear()
                elif key in ['construction', 'routes']: n['npc_initialization'][key] = {}
                elif key == 'environment': e.clear()
                elif key == 'cursor': a['campaign_cursor'] = 0
                elif key == 'kind': a['actor_kind'] = 8
                elif key == 'hull': a['actor_hull_id'] = 2
                elif key == 'origin': a['provenance']['actor']['offset'] += 2
                elif key == 'size': a['provenance']['actor']['bytes'] += 1
                elif key == 'section': m.sections[0]['segment'] = b'__DATA'
                else: m.architecture = 'unsupported'
                self.assertEqual(reader.extract_arrival_actor_construction(m, a, n, e), {}, (arch, key))
