"""Static rescue environment recognition on relocated synthetic sections."""
import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import arrival_environment as reader


def variants():
    return list(reader.LAYOUTS.items()) + [('x86_64',reader.MAC_ALTERNATE)]


def fixture(arch,rows,shift=0):
    constants=[k for k,v in rows.items() if v[0]=='__const']
    mach,origin,offset,low=literal_fixture(arch,{k:v[1:] for k,v in rows.items()},shift,constants)
    sky = {'planet_resources': {'supported': True}, 'provenance': {'opening': {
        'offset': origin, 'bytes': 71 if arch == 'x86_64' else 62}}}
    actors = {'player_initialization': {'flight_cache': {'supported': True}}}
    arrival = {'campaign_cursor': 1}
    return mach, sky, actors, arrival, offset, low


class ArrivalEnvironmentTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for arch,layout in variants():
            for shift in [0, 0x1200000]:
                m, s, a, r, *_ = fixture(arch,layout,shift)
                data = reader.extract_arrival_environment(m, s, a, r)
                self.assertEqual({k: v for k, v in data.items() if k != 'provenance'}, reader.VALUES)
                for key, span in data['provenance'].items():
                    self.assertEqual(set(span), {'offset', 'bytes'})
                    self.assertEqual(span['offset'], s['provenance']['opening']['offset'] + layout[key][1])
                data['provenance'].clear()
                self.assertTrue(reader.extract_arrival_environment(m, s, a, r)['provenance'])

    def test_altered_spans_and_truncation(self):
        for arch,layout in variants():
            m, s, a, r, offset, low = fixture(arch,layout)
            for name, (_, delta, size, _) in layout.items():
                for index in [0, size-1]:
                    changed = copy.copy(m)
                    raw = bytearray(m.data)
                    raw[offset+delta-low+index] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_arrival_environment(changed, s, a, r), {}, (arch, name, index))
            m.data = m.data[:offset+16]
            self.assertEqual(reader.extract_arrival_environment(m, s, a, r), {})

    def test_context_and_bounds(self):
        for arch,layout in variants():
            for key in ['player', 'cache', 'cursor', 'planet', 'origin', 'size', 'section', 'arch']:
                m, s, a, r, *_ = fixture(arch,layout)
                if key == 'player': a.clear()
                elif key == 'cache': a['player_initialization']['flight_cache'] = {}
                elif key == 'cursor': r['campaign_cursor'] = 0
                elif key == 'planet': s['planet_resources'] = {}
                elif key == 'origin': s['provenance']['opening']['offset'] += 2
                elif key == 'size': s['provenance']['opening']['bytes'] += 1
                elif key == 'section': m.sections[0]['segment'] = b'__DATA'
                else: m.architecture = 'unsupported'
                self.assertEqual(reader.extract_arrival_environment(m, s, a, r), {}, (arch, key))
