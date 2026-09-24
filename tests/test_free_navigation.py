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
            ('gate_environment', 'extract_gate_environment'),
            ('local_arrival_environment', 'extract_local_arrival_environment'),
            ('gate_transit', 'extract_gate_transit'),
            ('ordinary_worlds', 'extract_ordinary_worlds'),
            ('gate_arrival', 'extract_gate_arrival'),
            ('ordinary_shopping', 'extract_ordinary_shopping'),
            ('ordinary_fitting', 'extract_ordinary_fitting'),
            ('ordinary_contracts', 'extract_ordinary_contracts'),
            ('suttnar_visit', 'extract_suttnar_visit'),
            ('kappa_preparation', 'extract_kappa_preparation'),
            ('emp_bombs', 'extract_emp_bombs'),
            ('kappa_rescue', 'extract_kappa_rescue'),
            ('kappa_fighters', 'extract_kappa_fighters'),
            ('kappa_lifecycle', 'extract_kappa_lifecycle'),
            ('secondary_ownership', 'extract_secondary_ownership'),
            ('kappa_return', 'extract_kappa_return'),
            ('kappa_outcome', 'extract_kappa_outcome'),
            ('kappa_departure', 'extract_kappa_departure'),
            ('sahi_visit', 'extract_sahi_visit'),
            ('sahi_encounter', 'extract_sahi_encounter'),
            ('sahi_stage', 'extract_sahi_stage'),
            ('tractor_recovery', 'extract_tractor_recovery'),
        ]
        for variant in (0, 1):
            for missing in range(len(extensions) + 1):
                with self.subTest(variant=variant, missing=missing), ExitStack() as stack:
                    stack.enter_context(patch.object(mido_travel, 'hashed_variants', return_value=(variant, {'base': {}})))
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
                    expected = mido_travel.MAC_VALUES if variant else mido_travel.VALUES
                    for key, value in expected.items():
                        self.assertEqual(actual[key], value)
