"""Néhma34 import boundary, source guards and native declaration parity."""

import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from declaration_fixture import declaration_fixture
from gof2_content import nehma_visit as reader


class NehmaVisitTests(unittest.TestCase):
    def test_both_variants_relocate_detach_and_require_every_window(self):
        for name, expected, crystals in (
                ("LAYOUTS", reader.VALUES, reader.VOID_APP),
                ("MAC_ALTERNATE", reader.MAC_VALUES, reader.VOID_OLD)):
            for relocation in (0, 0x800000):
                with self.subTest(variant=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_nehma_visit(mach, arrival, crystals)
                        self.assertEqual(values, expected)
                        self.assertEqual(set(proof), set(layouts))
                        values["mission34"]["result_events"].clear()
                        self.assertEqual(reader.extract_nehma_visit(mach, arrival, crystals)[0], expected)
                        for key, (delta, _, _, _) in layouts.items():
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            at = arrival["provenance"]["actor"]["offset"] - mach.slice_offset + delta
                            raw[at] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_nehma_visit(changed, arrival, crystals),
                                             ({}, {}), key)
                        self.assertEqual(reader.extract_nehma_visit(
                            mach, {"provenance": {}}, crystals), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_nehma_visit(missing, arrival, crystals), ({}, {}))
                        mach.architecture = "armv7"
                        self.assertEqual(reader.extract_nehma_visit(mach, arrival, crystals), ({}, {}))

    def test_edition_identity_and_ambiguous_source_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, "LAYOUTS", layouts):
            self.assertEqual(reader.extract_nehma_visit(mach, arrival, reader.VOID_OLD), ({}, {}))
            changed = copy.deepcopy(reader.VOID_APP)
            changed["next_mission"]["station_id"] = 29
            self.assertEqual(reader.extract_nehma_visit(mach, arrival, changed), ({}, {}))
        with patch.object(reader, "LAYOUTS", layouts), patch.object(reader, "MAC_ALTERNATE", layouts):
            self.assertEqual(reader.extract_nehma_visit(mach, arrival, reader.VOID_APP), ({}, {}))

    def test_native_constants_and_guard_layout_match_reader(self):
        source = (Path(__file__).resolve().parents[1] /
                  "game/src/content/nehma_visit_definitions.gd").read_text()
        for name, expected in (("VALUES", reader.VALUES),
                               ("MAC_VALUES", reader.MAC_VALUES),
                               ("SPANS", {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                               ("MAC_SPANS", {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})):
            matches = re.findall(r"^const " + name + r":=(.+)$", source, re.MULTILINE)
            self.assertEqual(len(matches), 1, name)
            self.assertEqual(json.loads(matches[0]), expected, name)

    def test_landed_modal_order_and_next_career_boundary(self):
        voice_order = (364, 365, 371, 372, 373, 374, 375, 376, 377, 378,
                       366, 367, 368, 369, 370)
        for values, first_text in ((reader.VALUES, 1980), (reader.MAC_VALUES, 1966)):
            mission = values["mission34"]
            self.assertEqual((mission["campaign_cursor"], mission["kind"],
                              mission["station_id"], mission["system_id"],
                              mission["reward"], mission["bonus"]), (34, 11, 30, 2, 0, 0))
            self.assertEqual(mission["briefing_events"], [])
            self.assertEqual([(event["speaker_id"], event["text_id"], event["voice_event_id"])
                              for event in mission["result_events"]],
                             [(1 if i % 2 == 0 else 0, first_text + i, voice_order[i])
                              for i in range(15)])
            completion = mission["completion"]
            self.assertEqual((completion["result_mode"], completion["intermediate_next_keeps_cursor"],
                              completion["final_next_advances_to_cursor"],
                              completion["stays_landed_station_id"],
                              completion["reward_credits"]), (1, 34, 35, 30, 0))
            self.assertTrue(completion["requires_landed_target"])
            self.assertFalse(completion["cargo_or_equipment_change"] or
                             completion["extra_blueprint_change"] or
                             completion["extra_system_access_granted"])
            self.assertEqual(values["world"], {"authored_cast": [], "authored_radio_events": [],
                                               "selected_kind11_actor_count": 0})
            self.assertEqual(values["next_mission"],
                             {"campaign_cursor": 35, "kind": 11,
                              "station_id": 29, "system_id": 5,
                              "story": True, "reward": 0, "bonus": 0,
                              "briefing_events": []})


if __name__ == "__main__":
    unittest.main()
