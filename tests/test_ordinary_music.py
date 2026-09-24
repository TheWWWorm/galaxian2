"""Optional ordinary music reader rejects shifted, mixed and damaged source spans."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from gof2_content import ordinary_music
from declaration_fixture import declaration_fixture


def audio_fixture():
    events = [{} for _ in range(2293)]
    for event_id in ordinary_music.selected_event_ids():
        events[event_id] = {'id': event_id, 'categories': ['music'], 'simple_flags': 1,
                            'properties': {'fade_out_ms': 800, 'max_playbacks': 1},
                            'sound': {'flags': 0}}
    return {'events': events}


def source_fixture(rows, shift=0):
    fixture_rows = {key: [row[1], row[2], row[0], row[3]] for key, row in rows.items()}
    mach, arrival, layout = declaration_fixture(fixture_rows, shift, hash_prefix='sha256:')
    origin = arrival['provenance']['actor']['offset']
    table = layout['faction_table']
    raw = bytearray(mach.data)
    at = origin - mach.slice_offset + table[0]
    raw[at:at+16] = struct.pack('<4i', *ordinary_music.VALUES['faction_event_ids'])
    mach.data = bytes(raw)
    table[3] = 'sha256:' + hashlib.sha256(raw[at:at+16]).hexdigest()
    layout = {key: [row[2], row[0], row[1], row[3]] for key, row in layout.items()}
    fast_forward = {'radar': {'provenance': {'radar_music_publication_gate':
                                           {'offset': origin, 'bytes': 22}}}}
    return mach, fast_forward, layout


class OrdinaryMusicReaderTests(unittest.TestCase):
    def test_complete_layouts_relocate_and_detach(self):
        for name in ('LEGACY', 'APPSTORE'):
            for shift in (0, 0x800000):
                mach, fast_forward, rows = source_fixture(getattr(ordinary_music, name), shift)
                with patch.object(ordinary_music, name, rows):
                    found = ordinary_music.extract_ordinary_music(mach, fast_forward, audio_fixture())
                    self.assertEqual({k: v for k, v in found.items() if k != 'provenance'}, ordinary_music.VALUES)
                    self.assertEqual(ordinary_music.extract_ordinary_music(mach, fast_forward), found)
                    self.assertEqual(set(found['provenance']), set(rows))
                    found['battle_event_ids'].clear()
                    self.assertEqual(ordinary_music.extract_ordinary_music(mach, fast_forward, audio_fixture())['battle_event_ids'], [140, 141, 142])
                    for key, (_, delta, size, _) in rows.items():
                        for endpoint in (0, size-1):
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[fast_forward['radar']['provenance']['radar_music_publication_gate']['offset'] - mach.slice_offset + delta + endpoint] ^= 1
                            changed.data = bytes(raw)
                            self.assertEqual(ordinary_music.extract_ordinary_music(changed, fast_forward, audio_fixture()), {}, (name, key, endpoint))

    def test_source_identity_and_event_loop_are_required(self):
        mach, fast_forward, rows = source_fixture(ordinary_music.APPSTORE)
        with patch.object(ordinary_music, 'APPSTORE', rows):
            self.assertTrue(ordinary_music.extract_ordinary_music(mach, fast_forward, audio_fixture()))
            altered = copy.deepcopy(audio_fixture())
            altered['events'][134]['sound']['flags'] = 1
            self.assertEqual(ordinary_music.extract_ordinary_music(mach, fast_forward, altered), {})
            altered['events'][134]['sound']['flags'] = 0
            altered['events'][152]['properties']['fade_out_ms'] = 1000
            self.assertEqual(ordinary_music.extract_ordinary_music(mach, fast_forward, altered), {})
            self.assertEqual(ordinary_music.extract_ordinary_music(mach, fast_forward, []), {})
            bad = copy.deepcopy(fast_forward)
            bad['radar']['provenance']['radar_music_publication_gate']['offset'] += 1
            self.assertEqual(ordinary_music.extract_ordinary_music(mach, bad, audio_fixture()), {})
            mach.architecture = 'armv7'
            self.assertEqual(ordinary_music.extract_ordinary_music(mach, fast_forward, audio_fixture()), {})


if __name__ == '__main__':
    unittest.main()
