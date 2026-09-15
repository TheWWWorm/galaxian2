"""Source proof rejection and preservation of earlier optional travel readers."""
import copy
from contextlib import ExitStack
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import free_navigation as reader, mido_travel


class FreeNavigationTests(unittest.TestCase):
    def test_proofs_and_relocation(self):
        for shift in (0, 0x800000):
            mach, arrival, layouts = declaration_fixture(reader.LAYOUTS, shift)
            with patch.object(reader, 'LAYOUTS', layouts):
                values, proof = reader.extract_free_navigation(mach, arrival)
                self.assertEqual(values, reader.VALUES)
                self.assertEqual(set(proof), set(layouts))
                for name, (delta, _, _, _) in layouts.items():
                    changed = copy.copy(mach)
                    raw = bytearray(mach.data)
                    raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_free_navigation(changed, arrival), ({}, {}), name)
                values['gate_station_field'] = -1
                self.assertEqual(reader.extract_free_navigation(mach, arrival)[0], reader.VALUES)
                mach.architecture = 'armv7'
                self.assertEqual(reader.extract_free_navigation(mach, arrival), ({}, {}))

    def test_missing_extension_keeps_only_earned_predecessors(self):
        extensions = [
            ('contract_completion', 'extract_lounge_story'),
            ('convoy_capture', 'extract_convoy_capture'),
            ('convoy_ship', 'extract_convoy_ship'),
            ('convoy_lifecycle', 'extract_convoy_lifecycle'),
            ('convoy_effects', 'extract_convoy_effects'),
            ('alioth_arrival', 'extract_alioth_arrival'),
            ('convoy_transit', 'extract_convoy_transit'),
            ('alioth_attack', 'extract_alioth_attack'),
            ('alioth_lifecycle', 'extract_alioth_lifecycle'),
            ('alioth_flight', 'extract_alioth_flight'),
            ('alioth_return', 'extract_alioth_return'),
            ('free_navigation', 'extract_free_navigation'),
            ('free_population', 'extract_free_population'),
            ('free_traffic', 'extract_free_traffic'),
            ('free_lifecycle', 'extract_free_lifecycle'),
            ('free_flight', 'extract_free_flight'),
            ('free_arrival', 'extract_free_arrival'),
        ]
        for missing in range(len(extensions) + 1):
            with self.subTest(missing=missing), ExitStack() as stack:
                stack.enter_context(patch.object(mido_travel, 'hashed_declarations', return_value={'base': {}}))
                probes = []
                for index, (key, function) in enumerate(extensions):
                    result = ({}, {}) if index == missing else ({'scope': key}, {key: {'offset': index}})
                    probes.append(stack.enter_context(patch.object(mido_travel, function, return_value=result)))
                actual = mido_travel.extract_mido_travel(None, {}, {'scope': 'first_station_entry'}, {'scope': 'combat_training_encounter_construction'})
                for index, (key, _) in enumerate(extensions):
                    self.assertEqual(key in actual, index < missing)
                    self.assertEqual(key in actual['provenance'], index < missing)
                    self.assertEqual(probes[index].call_count, int(index <= missing))
                for key, value in mido_travel.VALUES.items():
                    self.assertEqual(actual[key], value)
