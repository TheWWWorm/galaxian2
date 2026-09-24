"""Bounded importer parity and corruption checks for the Void probe visit."""

import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from declaration_fixture import declaration_fixture
from gof2_content import void_probe as reader


class VoidProbeTests(unittest.TestCase):
    def test_complete_variants_relocation_and_every_span_corruption(self):
        for name, expected in (("LAYOUTS", reader.VALUES),
                               ("MAC_ALTERNATE", reader.MAC_VALUES)):
            for relocation in (0, 0x800000):
                with self.subTest(source=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_void_probe(mach, arrival)
                        self.assertEqual(values, expected)
                        self.assertEqual(set(proof), set(layouts))
                        self.assertTrue(all(set(origin) == {"offset", "bytes"}
                                            for origin in proof.values()))
                        values["world29"]["radio_events"].clear()
                        self.assertEqual(reader.extract_void_probe(mach, arrival)[0], expected)
                        for key, (delta, _, _, _) in layouts.items():
                            with self.subTest(source=name, relocation=relocation, corrupt=key):
                                changed = copy.copy(mach)
                                raw = bytearray(mach.data)
                                at = arrival["provenance"]["actor"]["offset"] - mach.slice_offset + delta
                                raw[at] ^= 0xFF
                                changed.data = bytes(raw)
                                self.assertEqual(reader.extract_void_probe(changed, arrival), ({}, {}))
                        for invalid in ({}, {"provenance": {}},
                                        {"provenance": {"actor": {"bytes": 314}}}):
                            self.assertEqual(reader.extract_void_probe(mach, invalid), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_void_probe(missing, arrival), ({}, {}))
                        mach.architecture = "armv7"
                        self.assertEqual(reader.extract_void_probe(mach, arrival), ({}, {}))

    def test_ambiguous_variant_is_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, "LAYOUTS", layouts), patch.object(reader, "MAC_ALTERNATE", layouts):
            self.assertEqual(reader.extract_void_probe(mach, arrival), ({}, {}))

    def test_native_values_and_guard_extents_match_both_compiler_variants(self):
        source = (Path(__file__).resolve().parents[1] /
                  "game/src/content/void_probe_definitions.gd").read_text()
        for name, expected in (("VALUES", reader.VALUES),
                               ("MAC_VALUES", reader.MAC_VALUES),
                               ("SPANS", {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                               ("MAC_SPANS", {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})):
            found = re.findall(r"^const " + name + r" := (.+)$", source, re.MULTILINE)
            self.assertEqual(len(found), 1, name)
            self.assertEqual(json.loads(found[0]), expected, name)
        self.assertIn("Equal.equal_value(data, MAC_VALUES)", source)

    def test_probe_boundaries_and_shared_owner_references(self):
        essential = {"world_cast29", "world_radio29", "world_condition23",
                     "world_portal_exception", "world_factory30", "target_stage_entire",
                     "target_radio_order", "target_radio_scheduler", "target_radio_condition5",
                     "target_equipment", "target_probe_pose", "entry_factory29",
                     "target_primary_trigger", "target_damage_setter",
                     "target_direct_damage_gate", "target_scripted_coast_setter",
                     "final_flight_success", "brief_pair", "result_pair"}
        for layout in (reader.LAYOUTS, reader.MAC_ALTERNATE):
            self.assertTrue(essential.issubset(layout))
        for values, text_start in ((reader.VALUES, 1937), (reader.MAC_VALUES, 1923)):
            mission = values["mission29"]
            world = values["world29"]
            self.assertEqual((mission["campaign_cursor"], mission["kind"],
                              mission["station_id"], mission["reward"]), (29, 4, -1, 0))
            self.assertEqual((len(mission["briefing_events"]), len(mission["result_events"])),
                             (1, 1))
            self.assertEqual(world["void_environment_ref"], "post_sahi.void")
            self.assertEqual(world["cast_ref"], "post_sahi.void.population")
            self.assertEqual(world["recurring_portal_ref"], "void_portal")
            self.assertNotIn("environment", world)
            self.assertNotIn("portal_geometry", world)
            self.assertEqual([row["text_id"] for row in world["radio_events"]],
                             list(range(text_start, text_start + 6)))
            self.assertEqual([(row["condition_kind"], row["condition_value"])
                              for row in world["radio_events"]],
                             [(23, 0), (6, 0), (6, 1), (6, 2), (5, 120000), (6, 4)])
            self.assertEqual(world["target_lock"]["scanner_duration_property"], 29)
            self.assertEqual(world["target_lock"]["default_duration_ms"], 8000)
            self.assertEqual(world["target_lock"]["elapsed_boundary"], "strictly_greater")
            self.assertEqual(world["probe"]["model_id"], 14290)
            self.assertEqual(world["probe"]["camera_eye_forward_right_up_scales"],
                             [25000, 1000, 1000])
            self.assertEqual(world["probe"]["spawn_on"],
                             {"event_index": 0, "state": "condition_satisfied"})
            self.assertEqual(world["probe"]["despawn_on"],
                             {"event_index": 1, "state": "playback_finished"})
            self.assertFalse(world["probe"]["stage_owned_probe_motion"])
            self.assertEqual(world["radio"]["elapsed_source"], "stage_elapsed_ms")
            self.assertTrue(world["radio"]["stage_elapsed_increment_before_radio"])
            self.assertTrue(world["radio"]["radio_update_before_stage_update"])
            self.assertTrue(world["radio"]["row2_playback_finish_clears_active_before_reset"])
            self.assertEqual(world["radio"]["active_row_minimum_elapsed_ms"], 2000)
            self.assertEqual(world["stage_presentation"]["phase1_trigger"],
                             {"event_index": 0, "state": "condition_satisfied"})
            self.assertEqual(world["stage_presentation"]["phase2_trigger"],
                             {"event_index": 1, "state": "playback_finished"})
            self.assertEqual(world["completion"]["phase2_trigger"],
                             {"event_index": 1, "state": "playback_finished"})
            self.assertTrue(world["stage_presentation"]["input_blocked_in_phase1"])
            self.assertFalse(world["stage_presentation"]["damage_enabled_in_phase1"])
            self.assertFalse(world["stage_presentation"]["hud_visible_in_phase1"])
            self.assertTrue(world["stage_presentation"]["damage_enabled_in_phase2"])
            self.assertFalse(world["stage_presentation"]["primary_trigger_enabled_in_phase1"])
            self.assertEqual(world["completion"]["survival_duration_ms"], 180000)
            self.assertEqual(world["completion"]["elapsed_boundary"], "strictly_greater")
            self.assertFalse(world["completion"]["requires_kill_quota"])
            self.assertTrue(world["portal"]["contact_rejected_while_story29_selected"])
            self.assertEqual(world["final_next"]["advances_to_cursor"], 30)
            self.assertEqual(values["mission30_declaration"]["station_id"], 91)
            for unproven in ("player_byte_0x104", "player_byte_0x3c9", "camera_interpolation"):
                self.assertNotIn(unproven, world)


if __name__ == "__main__":
    unittest.main()
