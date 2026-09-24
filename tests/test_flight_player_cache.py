"""Static declaration recognition with relocated synthetic layouts only."""
import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import flight_player_cache as reader


def variants():
    return [('x86_64',reader.LAYOUTS['x86_64']),
            ('armv7',reader.LAYOUTS['armv7']),
            ('x86_64',reader.MAC_ALTERNATE)]


def fixture(arch,rows,shift=0):
    constants=[k for k,v in rows.items() if v[0]=='__const']
    mach,origin,offset,low=literal_fixture(arch,{k:v[1:] for k,v in rows.items()},shift,constants)
    opening={'station_id':78,'provenance':{'declaration':{'offset':origin,'bytes':376 if arch=='x86_64' else 284}}}
    actors={'player_initialization':{'repair':{'supported':True}}}
    arrival={'campaign_cursor':1}
    return mach,opening,actors,arrival,offset,low


class FlightPlayerCacheTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for arch,layout in variants():
            for shift in [0, 0x1200000]:
                m, o, a, r, *_ = fixture(arch,layout,shift)
                data = reader.extract_flight_player_cache(m, o, a, r)
                self.assertEqual({k: v for k, v in data.items() if k != 'provenance'}, reader.VALUES)
                for key, span in data['provenance'].items():
                    self.assertEqual(set(span), {'offset', 'bytes'})
                    self.assertEqual(span['offset'], o['provenance']['declaration']['offset'] + layout[key][1])
                data['provenance'].clear()
                self.assertTrue(reader.extract_flight_player_cache(m, o, a, r)['provenance'])

    def test_altered_spans_and_truncation(self):
        for arch,layout in variants():
            m, o, a, r, offset, low = fixture(arch,layout)
            for name, (_, delta, size, _) in layout.items():
                for index in [0, size-1]:
                    changed = copy.copy(m)
                    raw = bytearray(m.data)
                    raw[offset+delta-low+index] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_flight_player_cache(changed, o, a, r), {}, (arch, name, index))
            m.data = m.data[:offset+16]
            self.assertEqual(reader.extract_flight_player_cache(m, o, a, r), {})

    def test_context_and_bounds(self):
        for arch,layout in variants():
            for key in ['player', 'repair', 'cursor', 'origin', 'size', 'section', 'arch', 'hazard_low', 'hazard_high']:
                m, o, a, r, *_ = fixture(arch,layout)
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
