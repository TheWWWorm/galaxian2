"""Relocated rescue motion declarations, using synthetic text sections only."""
import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import arrival_actor_motion as reader


def variants():
    return list(reader.LAYOUTS.items()) + [('x86_64',reader.MAC_ALTERNATE)]


def fixture(arch,rows,shift=0):
    mach,origin,offset,low=literal_fixture(arch,rows,shift)
    arrival = {'campaign_cursor': 1, 'actor_kind': 3, 'actor_hull_id': 30,
               'provenance': {'actor': {'offset': origin,
                                       'bytes': 315 if arch == 'x86_64' else 310}}}
    actors = {'npc_initialization': {'flight': {'supported': True}}}
    return mach, arrival, actors, {'supported': True}, offset, low


class ArrivalActorMotionTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for arch,layout in variants():
            for shift in [0, 0x1200000]:
                m, a, n, e, *_ = fixture(arch,layout,shift)
                data = reader.extract_arrival_actor_motion(m, a, n, e)
                self.assertEqual({k: v for k, v in data.items() if k != 'provenance'}, reader.VALUES)
                for key, span in data['provenance'].items():
                    self.assertEqual(set(span), {'offset', 'bytes'})
                    self.assertEqual(span['offset'], a['provenance']['actor']['offset']+layout[key][0])
                data['provenance'].clear()
                self.assertTrue(reader.extract_arrival_actor_motion(m, a, n, e)['provenance'])

    def test_altered_spans_and_truncation(self):
        for arch,layout in variants():
            m, a, n, e, offset, low = fixture(arch,layout)
            for key, (delta, size, _) in layout.items():
                for index in [0, size-1]:
                    changed = copy.copy(m)
                    raw = bytearray(m.data)
                    raw[offset+delta-low+index] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_arrival_actor_motion(changed, a, n, e), {}, (arch, key, index))
            m.data = m.data[:offset+16]
            self.assertEqual(reader.extract_arrival_actor_motion(m, a, n, e), {})

    def test_context_and_section_bounds(self):
        for arch,layout in variants():
            for key in ['actors', 'flight', 'environment', 'cursor', 'kind', 'hull', 'origin', 'size', 'section', 'arch']:
                m, a, n, e, *_ = fixture(arch,layout)
                if key == 'actors': n.clear()
                elif key == 'flight': n['npc_initialization']['flight'] = {}
                elif key == 'environment': e.clear()
                elif key == 'cursor': a['campaign_cursor'] = 0
                elif key == 'kind': a['actor_kind'] = 8
                elif key == 'hull': a['actor_hull_id'] = 2
                elif key == 'origin': a['provenance']['actor']['offset'] += 2
                elif key == 'size': a['provenance']['actor']['bytes'] += 1
                elif key == 'section': m.sections[0]['segment'] = b'__DATA'
                else: m.architecture = 'unsupported'
                self.assertEqual(reader.extract_arrival_actor_motion(m, a, n, e), {}, (arch, key))
