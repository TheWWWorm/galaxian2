"""Ordinary Void access source, variant, and declaration boundaries."""

import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from declaration_fixture import declaration_fixture
from gof2_content import void_access as reader


class VoidAccessTests(unittest.TestCase):
    def test_both_variants_detach_values_and_reject_every_changed_span(self):
        for name, visits in (("LAYOUTS", reader.POST_PROBE_APP),
                             ("MAC_ALTERNATE", reader.POST_PROBE_OLD)):
            for relocation in (0, 0x800000):
                with self.subTest(variant=name, relocation=relocation):
                    mach, arrival, layout = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layout):
                        values, proof = reader.extract_void_access(mach, arrival, visits)
                        self.assertEqual(values, reader.VALUES)
                        self.assertEqual(set(proof), set(layout))
                        values["source"]["reroll"]["excluded_system_ids"].clear()
                        self.assertEqual(reader.extract_void_access(mach, arrival, visits)[0], reader.VALUES)
                        for key, (delta, _, _, _) in layout.items():
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            at = arrival["provenance"]["actor"]["offset"] - mach.slice_offset + delta
                            raw[at] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_void_access(changed, arrival, visits), ({}, {}), key)
                        for invalid in ({}, {"provenance": {}},
                                        {"provenance": {"actor": {"bytes": 314}}}):
                            self.assertEqual(reader.extract_void_access(mach, invalid, visits), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_void_access(missing, arrival, visits), ({}, {}))
                        mach.architecture = "armv7"
                        self.assertEqual(reader.extract_void_access(mach, arrival, visits), ({}, {}))

    def test_ambiguous_or_mismatched_shared_variant_is_rejected(self):
        mach, arrival, layout = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, "LAYOUTS", layout), patch.object(reader, "MAC_ALTERNATE", layout):
            self.assertEqual(reader.extract_void_access(mach, arrival, reader.POST_PROBE_APP), ({}, {}))
        with patch.object(reader, "LAYOUTS", layout):
            self.assertEqual(reader.extract_void_access(mach, arrival, reader.POST_PROBE_OLD), ({}, {}))
            changed = copy.deepcopy(reader.POST_PROBE_APP)
            changed["missions"]["32"]["briefing_events"][0]["text_id"] += 1
            self.assertEqual(reader.extract_void_access(mach, arrival, changed), ({}, {}))

    def test_native_payload_and_source_extents_match_reader(self):
        source = (Path(__file__).resolve().parents[1] /
                  "game/src/content/void_access_definitions.gd").read_text()
        for name, expected in (("VALUES", reader.VALUES),
                               ("SPANS", {key: row[:2] for key, row in reader.LAYOUTS.items()}),
                               ("MAC_SPANS", {key: row[:2] for key, row in reader.MAC_ALTERNATE.items()})):
            matches = re.findall(r"^const " + name + r":=(.+)$", source, re.MULTILINE)
            self.assertEqual(len(matches), 1, name)
            self.assertEqual(json.loads(matches[0]), expected, name)
        self.assertNotIn("const MAC_VALUES:=", source)
        self.assertIn("Equal.equal_value(visits,PostProbe.VALUES)", source)
        self.assertIn("Equal.equal_value(visits,PostProbe.MAC_VALUES)", source)
        self.assertIn("Layouts.matches(proof,int(origin.offset),executable_bytes,[layout])", source)

    def test_warning_reroll_and_contact_stay_separate_from_story_result(self):
        data = reader.VALUES
        self.assertNotIn("briefing32", data)
        marker = data["map_warning"]
        self.assertEqual((marker["first_cursor"], marker["model_id"],
                          marker["target_hint_first_cursor"]), (32, 16994, 33))
        self.assertTrue(marker["station_choice_uses_career_location_selection"])
        source = data["source"]
        self.assertEqual((source["initial_system_id"], source["initial_station_id"]), (18, 91))
        reroll = source["reroll"]
        self.assertEqual((reroll["first_cursor"], reroll["last_cursor"],
                          reroll["threshold"], reroll["counter_after_reroll"]), (32, 44, 11, 0))
        self.assertEqual(reroll["counter_unit"], "qualifying_career_location_selection_call")
        self.assertTrue(reroll["skip_chosen_story_target_station"])
        self.assertTrue(reroll["skip_chosen_current_source_station"])
        self.assertEqual((reroll["system_draw_exclusive_bound"],
                          reroll["requires_career_system_access_bit"],
                          reroll["excluded_system_ids"]), (22, 0, [10, 15]))
        self.assertTrue(reroll["has_selected_story_target_equal_previous_source_guard"])
        self.assertFalse(reroll["selected_story_target_equals_old_source_retry_reachable_at_cursor32_33"])
        self.assertEqual((source["selection_at_or_after_cursor_disables_source"], source["disabled_system_id"],
                          source["disabled_station_id"]), (45, -10, -10))
        portal = data["ordinary_portal"]
        self.assertEqual((portal["active_while_cursor_below"], portal["environment_slot"],
                          portal["model_id"]), (43, 3, 16994))
        self.assertEqual((portal["selected_mission_kind_at_source_flight"],
                          portal["story_list_mission_kind"], portal["contact_keeps_story_cursor"]),
                         (-1, 8, 33))
        self.assertEqual((portal["selected_void_system_id"], portal["selected_void_station_id"],
                          portal["retained_void_system_id"], portal["retained_void_station_id"]),
                         (-1, -1, -1, -1))
        self.assertEqual(portal["recorded_return_station"], "actual_source_station")
        self.assertTrue(portal["copies_live_player_pools"] and portal["retains_ammunition"])
        self.assertFalse(portal["grants_cargo_or_reward_on_entry"])


if __name__ == "__main__":
    unittest.main()
