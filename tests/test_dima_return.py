"""Guarded Dima30 declarations are import-only and source-specific."""

import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from declaration_fixture import declaration_fixture
from gof2_content import dima_return as reader


class DimaReturnTests(unittest.TestCase):
    def test_complete_variants_relocation_and_corruption(self):
        for name, expected in (("LAYOUTS", reader.VALUES),
                               ("MAC_ALTERNATE", reader.MAC_VALUES)):
            for relocation in (0, 0x800000):
                with self.subTest(source=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_dima_return(mach, arrival)
                        self.assertEqual(values, expected)
                        self.assertEqual(set(proof), set(layouts))
                        values["result30"]["result_events"].clear()
                        self.assertEqual(reader.extract_dima_return(mach, arrival)[0], expected)
                        for key, (delta, _, _, _) in layouts.items():
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival["provenance"]["actor"]["offset"] - mach.slice_offset + delta] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_dima_return(changed, arrival), ({}, {}), key)
                        for invalid in ({}, {"provenance": {}},
                                        {"provenance": {"actor": {"bytes": 314}}}):
                            self.assertEqual(reader.extract_dima_return(mach, invalid), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_dima_return(missing, arrival), ({}, {}))
                        mach.architecture = "armv7"
                        self.assertEqual(reader.extract_dima_return(mach, arrival), ({}, {}))

    def test_ambiguous_variant_is_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, "LAYOUTS", layouts), patch.object(reader, "MAC_ALTERNATE", layouts):
            self.assertEqual(reader.extract_dima_return(mach, arrival), ({}, {}))

    def test_native_values_and_guard_extents(self):
        source = (Path(__file__).resolve().parents[1] /
                  "game/src/content/dima_return_definitions.gd").read_text()
        for name, expected in (("VALUES", reader.VALUES), ("MAC_VALUES", reader.MAC_VALUES),
                               ("SPANS", {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                               ("MAC_SPANS", {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})):
            found = re.findall(r"^const " + name + r":=(.+)$", source, re.MULTILINE)
            self.assertEqual(len(found), 1, name)
            self.assertEqual(json.loads(found[0]), expected, name)

    def test_visit_result_and_next_factory_boundary(self):
        guards = {"kind156_cast_dispatch", "kind156_cast_table_entry",
                  "portal_return_story_selection_call", "story_target_selection",
                  "story_selected_pointer_write",
                  "radio30_dispatch_entry", "radio30_no_rows",
                  "stage_cursor_range_dispatch", "probe_stage29_only",
                  "kind156_visit_table_entry", "kind156_visit_predicate",
                  "flight_result_gate", "flight_result_open",
                  "result30_count", "result30_pairs", "result30_voices",
                  "final_next_special_cases", "final_next_retire", "factory31"}
        for layout in (reader.LAYOUTS, reader.MAC_ALTERNATE):
            self.assertEqual(len(layout), 25)
            self.assertTrue(guards.issubset(layout))
        for values, first_text in ((reader.VALUES, 1944), (reader.MAC_VALUES, 1930)):
            self.assertEqual(values["mission30_ref"], "void_probe.mission30_declaration")
            world = values["world30"]
            self.assertTrue(world["selected_story_on_target_return"])
            self.assertEqual(world["story_cast_dispatch"], "common_world_default")
            self.assertEqual((world["authored_story_cast"], world["authored_story_radio_events"]), ([], []))
            self.assertFalse(world["mission_specific_stage"])
            self.assertEqual(world["completion"],
                             {"predicate": "selected_kind156_visit", "requires_in_flight": True,
                              "target_station_ref": "void_probe.mission30_declaration.station_id",
                              "world_elapsed_strictly_greater_than_ms": 10000,
                              "hud_elapsed_at_least_ms": 5001,
                              "controller_hold_clear": True, "result_opens_in": "flight"})
            result = values["result30"]
            self.assertEqual(result["briefing_events"], [])
            self.assertEqual([(row["speaker_id"], row["text_id"], row["voice_event_id"])
                              for row in result["result_events"]],
                             [(speaker, first_text + i, 329 + i)
                              for i, speaker in enumerate((0, 6, 0, 6, 0))])
            self.assertTrue(result["completed_on_result_open"])
            self.assertEqual(result["final_next"]["advances_to_cursor"], 31)
            self.assertEqual(result["final_next"]["selected_story_mission_after"],
                             "kind_minus_one_sentinel")
            self.assertFalse(result["final_next"]["cargo_or_equipment_change"])
            self.assertFalse(result["final_next"]["location_change"])
            self.assertEqual(result["final_next"]["remains_in_flight_at_station_id"], 91)
            self.assertEqual(values["next_mission_factory"],
                             {"campaign_cursor": 31, "kind": 11, "station_id": 98,
                              "system_id": 19, "story": True, "reward_credits": 30000,
                              "bonus_credits": 0})


if __name__ == "__main__":
    unittest.main()
