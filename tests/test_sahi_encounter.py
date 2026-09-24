"""Sahi cast and radio keep source-specific values and complete proof extents."""
import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import sahi_encounter as reader


class SahiEncounterTests(unittest.TestCase):
    def test_complete_source_variants_relocation_and_corruption(self):
        for name, expected in [('LAYOUTS', reader.VALUES), ('MAC_ALTERNATE', reader.MAC_VALUES)]:
            for relocation in (0, 0x800000):
                with self.subTest(source=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_sahi_encounter(mach, arrival)
                        self.assertEqual(values, expected)
                        self.assertEqual(set(proof), set(layouts))
                        values['population']['actors'][0]['hull_catalogue_id'] = -1
                        values['radio_events'][3]['values'].clear()
                        self.assertEqual(reader.extract_sahi_encounter(mach, arrival)[0], expected)
                        for key, (delta, _, _, _) in layouts.items():
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_sahi_encounter(changed, arrival), ({}, {}), key)
                        for invalid in [{}, {'provenance': {}}, {'provenance': {'actor': {'bytes': 314}}}]:
                            self.assertEqual(reader.extract_sahi_encounter(mach, invalid), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_sahi_encounter(missing, arrival), ({}, {}))
                        mach.architecture = 'armv7'
                        self.assertEqual(reader.extract_sahi_encounter(mach, arrival), ({}, {}))

    def test_ambiguous_source_variant_is_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts), patch.object(reader, 'MAC_ALTERNATE', layouts):
            self.assertEqual(reader.extract_sahi_encounter(mach, arrival), ({}, {}))

    def test_native_declarations_keep_matching_source_values_and_extents(self):
        source = (Path(__file__).resolve().parents[1] / 'game/src/content/sahi_encounter_definitions.gd').read_text()
        for name, value in [('VALUES', reader.VALUES), ('MAC_VALUES', reader.MAC_VALUES),
                            ('SPANS', {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                            ('MAC_SPANS', {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})]:
            found = re.findall(r'^const ' + name + r' = (.+)$', source, re.MULTILINE)
            self.assertEqual(len(found), 1, name)
            self.assertEqual(json.loads(found[0]), value, name)

    def test_radio_resource_and_actor_relationships(self):
        legacy = copy.deepcopy(reader.VALUES)
        current = copy.deepcopy(reader.MAC_VALUES)
        for row in current['radio_events']:
            row['text_id'] -= 14
        self.assertEqual(current, legacy)
        for values in (reader.VALUES, reader.MAC_VALUES):
            population = values['population']
            self.assertEqual(population['construction_order'], [row['actor_id'] for row in population['actors']])
            self.assertEqual(population['actor_count'], len(population['actors']))
            self.assertEqual(population['actor_route_ids'], [row['actor_id'] for row in population['actors'] if row['subtype'] == 0])
            for row in population['actors']:
                self.assertLess(row['waypoint_index'], len(population['waypoints']))
                self.assertNotIn(row['actor_id'], values['weapons']['npc_target_memberships'][row['actor_id']])
            for index, event in enumerate(values['radio_events']):
                if event['condition'] == 6:
                    self.assertLess(event['values'][0], index)
            self.assertEqual(values['radio_events'][3]['condition'], 22)
            self.assertEqual(values['radio_conditions']['22'], 'collected_cargo_quantity_at_least')
            for unsupported in ['completion', 'failure', 'next_cursor', 'next_mission', 'reward']:
                self.assertNotIn(unsupported, values)


if __name__ == '__main__':
    unittest.main()
