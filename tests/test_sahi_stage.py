"""Sahi stage declarations retain complete source proof and detached values."""
import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import sahi_encounter, sahi_stage as reader


class SahiStageTests(unittest.TestCase):
    def test_source_variants_relocation_and_each_corrupt_span(self):
        for name in ('LAYOUTS', 'MAC_ALTERNATE'):
            for relocation in (0, 0x800000):
                with self.subTest(source=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_sahi_stage(mach, arrival)
                        self.assertEqual(values, reader.VALUES)
                        self.assertEqual(set(proof), set(layouts))
                        values['view']['camera_eye_offset'].clear()
                        values['transition']['next_cursor'] = 99
                        self.assertEqual(reader.extract_sahi_stage(mach, arrival)[0], reader.VALUES)
                        for key, (delta, _, _, _) in layouts.items():
                            damaged = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta] ^= 255
                            damaged.data = bytes(raw)
                            self.assertEqual(reader.extract_sahi_stage(damaged, arrival), ({}, {}), key)
                        for invalid in [{}, {'provenance': {}}, {'provenance': {'actor': {'bytes': 314}}}]:
                            self.assertEqual(reader.extract_sahi_stage(mach, invalid), ({}, {}))
                        missing = copy.copy(mach);missing.sections = []
                        self.assertEqual(reader.extract_sahi_stage(missing, arrival), ({}, {}))
                        mach.architecture = 'armv7'
                        self.assertEqual(reader.extract_sahi_stage(mach, arrival), ({}, {}))

    def test_ambiguous_source_is_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts), patch.object(reader, 'MAC_ALTERNATE', layouts):
            self.assertEqual(reader.extract_sahi_stage(mach, arrival), ({}, {}))

    def test_native_values_and_proof_extents_match_the_reader(self):
        native = (Path(__file__).resolve().parents[1] / 'game/src/content/sahi_stage_definitions.gd').read_text()
        for name, value in [('VALUES', reader.VALUES), ('SPANS', {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                            ('MAC_SPANS', {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})]:
            found = re.findall(r'^const ' + name + r' = (.+)$', native, re.MULTILINE)
            self.assertEqual(len(found), 1, name)
            self.assertEqual(json.loads(found[0]), value, name)

    def test_stage_dependencies_and_declared_transition_boundary(self):
        data = reader.VALUES
        self.assertEqual(data['sequence']['condition_kind'], 31)
        self.assertFalse(data['sequence']['generic_condition_succeeds'])
        for encounter in (sahi_encounter.VALUES, sahi_encounter.MAC_VALUES):
            sequence = data['sequence']
            cargo_line = encounter['radio_events'][sequence['view_event_started']]
            portal_line = encounter['radio_events'][sequence['open_event_started']]
            self.assertEqual((cargo_line['condition'], cargo_line['values']), (22, [3]))
            self.assertEqual((portal_line['condition'], portal_line['values']), (6, [sequence['view_event_started']]))
            self.assertFalse(encounter['portal']['visible'])
            self.assertEqual(encounter['portal']['environment_slot'], data['portal']['environment_slot'])
        self.assertGreater(data['portal']['forward_offset'], data['contact']['pull_radius'])
        self.assertEqual(data['transition']['next_cursor'], data['next_factory']['campaign_cursor'])
        self.assertEqual((data['next_factory']['mission_kind'], data['next_factory']['target_station_id']), (156, -1))
        self.assertTrue(data['next_factory']['protect_first_matching_row'])
        self.assertFalse(data['next_factory']['grants_cargo'])
        for field in ('reward', 'result_dialogue', 'next_encounter', 'station_acknowledgement'):
            self.assertNotIn(field, data)
        self.assertNotIn('elapsed_completion_ms', data['spin'])


if __name__ == '__main__':
    unittest.main()
