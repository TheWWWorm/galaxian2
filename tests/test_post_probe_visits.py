"""Variant, ownership and corruption boundaries for the later station data."""
import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from declaration_fixture import declaration_fixture
from gof2_content import post_probe_visits as reader


class PostProbeVisitTests(unittest.TestCase):
    def test_complete_variants_and_corruption(self):
        for name, expected in (("LAYOUTS", reader.VALUES),
                               ("MAC_ALTERNATE", reader.MAC_VALUES)):
            for relocation in (0, 0x800000):
                with self.subTest(variant=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_post_probe_visits(mach, arrival)
                        self.assertEqual(values, expected)
                        self.assertEqual(set(proof), set(layouts))
                        values["missions"]["31"]["result_events"].clear()
                        self.assertEqual(reader.extract_post_probe_visits(mach, arrival)[0], expected)
                        for key, (delta, _, _, _) in layouts.items():
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival["provenance"]["actor"]["offset"] - mach.slice_offset + delta] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_post_probe_visits(changed, arrival), ({}, {}), key)
                        for invalid in ({}, {"provenance": {}},
                                        {"provenance": {"actor": {"bytes": 314}}}):
                            self.assertEqual(reader.extract_post_probe_visits(mach, invalid), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_post_probe_visits(missing, arrival), ({}, {}))
                        mach.architecture = "armv7"
                        self.assertEqual(reader.extract_post_probe_visits(mach, arrival), ({}, {}))

    def test_ambiguous_variant_is_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, "LAYOUTS", layouts), patch.object(reader, "MAC_ALTERNATE", layouts):
            self.assertEqual(reader.extract_post_probe_visits(mach, arrival), ({}, {}))

    def test_native_values_and_guards(self):
        source = (Path(__file__).resolve().parents[1] /
                  "game/src/content/post_probe_visit_definitions.gd").read_text()
        for name, expected in (("VALUES", reader.VALUES), ("MAC_VALUES", reader.MAC_VALUES),
                               ("SPANS", {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                               ("MAC_SPANS", {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})):
            matches = re.findall(r"^const " + name + r":=(.+)$", source, re.MULTILINE)
            self.assertEqual(len(matches), 1)
            self.assertEqual(json.loads(matches[0]), expected)

    def test_rewards_and_crystal_requirement_are_distinct(self):
        for values, first in ((reader.VALUES, 1949), (reader.MAC_VALUES, 1935)):
            alioth, thynome = (values["missions"][str(cursor)] for cursor in (31, 32))
            self.assertEqual(alioth["briefing_events"], [])
            self.assertEqual([(row["speaker_id"], row["text_id"], row["voice_event_id"])
                              for row in alioth["result_events"]],
                             [(speaker, first + i, 334 + i) for i, speaker in enumerate([1, 0] * 5)])
            self.assertEqual((alioth["reward"], alioth["completion"]["reward_credits"]), (30000, 30000))
            self.assertEqual(thynome["briefing_events"], [{"speaker_id": 0, "text_id": first + 10,
                                                         "voice_event_id": 181}])
            self.assertEqual([row["voice_event_id"] for row in thynome["result_events"]],
                             [344, 345, 347, 348, 349, 350, 351, 352, 353, 354, 346])
            for mission, target, next_cursor in ((alioth, 98, 32), (thynome, 10, 33)):
                rule = mission["completion"]
                self.assertTrue(rule["requires_landed_target"] and rule["completed_on_result_open"])
                self.assertEqual(rule["advance_on_final_next_to_cursor"], next_cursor)
                self.assertEqual(rule["stays_landed_station_id"], target)
                self.assertFalse(rule["cargo_or_equipment_change"] or rule["extra_system_access_granted"])
            self.assertEqual(thynome["completion"]["reward_credits"], 0)
            following = values["next_mission"]
            self.assertEqual((following["kind"], following["station_id"], following["reward"]), (8, 10, 0))
            self.assertEqual((following["required_item_id"], following["required_quantity"]), (164, 50))
            self.assertFalse(following["grants_required_cargo"])


if __name__ == "__main__":
    unittest.main()
