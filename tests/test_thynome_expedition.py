"""Thynome and Dima declarations stay source-specific and import-only."""
import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import thynome_expedition as reader


class ThynomeExpeditionTests(unittest.TestCase):
    def test_complete_variants_relocation_and_corruption(self):
        for name, expected in [('LAYOUTS', reader.VALUES),
                               ('MAC_ALTERNATE', reader.MAC_VALUES)]:
            for relocation in (0, 0x800000):
                with self.subTest(source=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_thynome_expedition(mach, arrival)
                        self.assertEqual(values, expected)
                        self.assertEqual(set(proof), set(layouts))
                        values['world28']['cast']['groups'].clear()
                        self.assertEqual(reader.extract_thynome_expedition(mach, arrival)[0], expected)
                        for key, (delta, _, _, _) in layouts.items():
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_thynome_expedition(changed, arrival),
                                             ({}, {}), key)
                        for invalid in [{}, {'provenance': {}},
                                        {'provenance': {'actor': {'bytes': 314}}}]:
                            self.assertEqual(reader.extract_thynome_expedition(mach, invalid), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_thynome_expedition(missing, arrival), ({}, {}))
                        mach.architecture = 'armv7'
                        self.assertEqual(reader.extract_thynome_expedition(mach, arrival), ({}, {}))

    def test_ambiguous_variant_is_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts), patch.object(reader, 'MAC_ALTERNATE', layouts):
            self.assertEqual(reader.extract_thynome_expedition(mach, arrival), ({}, {}))

    def test_native_values_and_guard_extents(self):
        source = (Path(__file__).resolve().parents[1] /
                  'game/src/content/thynome_expedition_definitions.gd').read_text()
        for name, expected in [('VALUES', reader.VALUES), ('MAC_VALUES', reader.MAC_VALUES),
                               ('SPANS', {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                               ('MAC_SPANS', {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})]:
            found = re.findall(r'^const ' + name + r':=(.+)$', source, re.MULTILINE)
            self.assertEqual(len(found), 1, name)
            self.assertEqual(json.loads(found[0]), expected, name)

    def test_result_reference_cast_and_contact_boundary(self):
        semantic_guards = {'dima_constructor_cargo', 'dima_actor_update_cruise_gate',
                           'dima_world_kind4_skips_ambient', 'dima_target_count_loop',
                           'dima_target_special_list', 'dima_target_generic_list',
                           'dima_kind9_opposition', 'dima_hull_maximum_getter',
                           'dima_hull_both_pools_setter',
                           'dima_hull_percentage_recalculation'}
        for layouts in (reader.LAYOUTS, reader.MAC_ALTERNATE):
            self.assertTrue(semantic_guards.issubset(layouts))
        for values in (reader.VALUES, reader.MAC_VALUES):
            ack = values['station_ack']
            self.assertEqual(ack['result_events_ref'], 'post_sahi.missions.27.result_events')
            self.assertNotIn('result_events', ack)
            self.assertEqual(ack['result_event_count'], 11)
            self.assertEqual(ack['advance_on_final_next_to_cursor'], 28)
            self.assertEqual(ack['stays_landed_station_id'], 10)
            self.assertFalse(ack['cargo_or_equipment_change'])
            mission = values['mission28']
            self.assertEqual((mission['kind'], mission['station_id'], mission['system_id']),
                             (4, 91, 18))
            self.assertEqual((mission['briefing_events'], mission['result_events']), ([], []))
            world = values['world28']
            self.assertEqual(sum(group['count'] for group in world['cast']['groups']), 8)
            fighters, freighters = world['cast']['groups']
            self.assertEqual((fighters['actor_kind'], freighters['actor_kind']), (9, 0))
            self.assertEqual(freighters['hull_scaling'],
                             {'source_pool': 'factory_maximum', 'divisor': 4,
                              'rounding': 'truncate_toward_zero',
                              'sets_pools': ['maximum', 'current']})
            self.assertFalse(freighters['cruise_enabled'])
            self.assertTrue(freighters['generated_cargo_cleared_after_factory'])
            for raw_field in ('source_byte_0x18c', 'optional_attachment_offset_removed', 'active'):
                self.assertNotIn(raw_field, freighters)
            self.assertEqual(world['cast']['player_target_id'], -1)
            self.assertEqual(world['cast']['target_memberships'],
                             [[5, 6, 7, -1]] * 5 + [[-1, 0, 1, 2, 3, 4]] * 3)
            self.assertEqual(world['contact']['advances_to_cursor'], 29)
            self.assertEqual(world['contact']['selected_station_id_after'], -1)
            self.assertEqual(world['contact']['selected_location_ref'], 'persistent_portal_object')
            self.assertTrue(world['contact']['recent_location_cache_unchanged'])
            self.assertEqual(world['contact']['recorded_return_station_id'], 91)
        self.assertEqual([row['text_id'] for row in reader.VALUES['world28']['radio_events']],
                         [1933, 1934, 1935])
        self.assertEqual([row['text_id'] for row in reader.MAC_VALUES['world28']['radio_events']],
                         [1919, 1920, 1921])


if __name__ == '__main__':
    unittest.main()
