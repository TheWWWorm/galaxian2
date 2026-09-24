"""Void crystal import boundaries and native declaration parity."""

import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from declaration_fixture import declaration_fixture
from gof2_content import void_crystals as reader


def shared_declarations():
    population = {"count_base": 80, "count_bound": 80,
                  "provenance": {str(i): {} for i in range(6)}}
    resources = {"ore_item_ids": list(range(154, 164)), "fallback_item_id": 164,
                 "location_weight": 100, "model_ids": [16900, 16921, 16904, 18836],
                 "override_cursor": 90,
                 "provenance": {str(i): {} for i in range(12)}}
    return population, resources


class VoidCrystalTests(unittest.TestCase):
    def test_dual_variant_relocation_detachment_and_every_guard(self):
        for name, expected, visits in (
                ("LAYOUTS", reader.VALUES, reader.POST_PROBE_APP),
                ("MAC_ALTERNATE", reader.MAC_VALUES, reader.POST_PROBE_OLD)):
            for relocation in (0, 0x800000):
                with self.subTest(variant=name, relocation=relocation):
                    mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                    population, resources = shared_declarations()
                    with patch.object(reader, name, layouts):
                        values, proof = reader.extract_void_crystals(
                            mach, arrival, visits, population, resources)
                        self.assertEqual(values, expected)
                        self.assertEqual(set(proof), set(layouts))
                        values["mission33"]["result_events"].clear()
                        self.assertEqual(reader.extract_void_crystals(
                            mach, arrival, visits, population, resources)[0], expected)
                        for key, (delta, _, _, _) in layouts.items():
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            at = arrival["provenance"]["actor"]["offset"] - mach.slice_offset + delta
                            raw[at] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_void_crystals(
                                changed, arrival, visits, population, resources), ({}, {}), key)
                        for invalid in ({}, {"provenance": {}},
                                        {"provenance": {"actor": {"bytes": 314}}}):
                            self.assertEqual(reader.extract_void_crystals(
                                mach, invalid, visits, population, resources), ({}, {}))
                        missing = copy.copy(mach)
                        missing.sections = []
                        self.assertEqual(reader.extract_void_crystals(
                            missing, arrival, visits, population, resources), ({}, {}))
                        mach.architecture = "armv7"
                        self.assertEqual(reader.extract_void_crystals(
                            mach, arrival, visits, population, resources), ({}, {}))

    def test_ambiguous_variant_and_changed_shared_declarations_rejected(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        population, resources = shared_declarations()
        with patch.object(reader, "LAYOUTS", layouts), patch.object(reader, "MAC_ALTERNATE", layouts):
            self.assertEqual(reader.extract_void_crystals(
                mach, arrival, reader.POST_PROBE_APP, population, resources), ({}, {}))
        with patch.object(reader, "LAYOUTS", layouts):
            wrong_visits = copy.deepcopy(reader.POST_PROBE_APP)
            wrong_visits["next_mission"]["required_quantity"] = 49
            self.assertEqual(reader.extract_void_crystals(
                mach, arrival, wrong_visits, population, resources), ({}, {}))
            for field, changed_value in (("count_bound", 81), ("provenance", {})):
                changed = copy.deepcopy(population)
                changed[field] = changed_value
                self.assertEqual(reader.extract_void_crystals(
                    mach, arrival, reader.POST_PROBE_APP, changed, resources), ({}, {}))
            for field, changed_value in (("fallback_item_id", 163),
                                         ("model_ids", [16900, 16920, 16904, 18836]),
                                         ("provenance", {})):
                changed = copy.deepcopy(resources)
                changed[field] = changed_value
                self.assertEqual(reader.extract_void_crystals(
                    mach, arrival, reader.POST_PROBE_APP, population, changed), ({}, {}))

    def test_native_constants_and_guard_extents_match(self):
        source = (Path(__file__).resolve().parents[1] /
                  "game/src/content/void_crystal_definitions.gd").read_text()
        for name, expected in (("VALUES", reader.VALUES),
                               ("MAC_VALUES", reader.MAC_VALUES),
                               ("SPANS", {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                               ("MAC_SPANS", {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})):
            matches = re.findall(r"^const " + name + r":=(.+)$", source, re.MULTILINE)
            self.assertEqual(len(matches), 1, name)
            self.assertEqual(json.loads(matches[0]), expected, name)

    def test_result_count_hazard_draw_order_and_final_transaction(self):
        for values, text_first in ((reader.VALUES, 1971),
                                   (reader.MAC_VALUES, 1957)):
            mission = values["mission33"]
            self.assertEqual((mission["campaign_cursor"], mission["kind"],
                              mission["station_id"], mission["required_item_id"],
                              mission["required_quantity"]), (33, 8, 10, 164, 50))
            self.assertEqual(mission["briefing_events"], [])
            self.assertEqual([(event["speaker_id"], event["text_id"], event["voice_event_id"])
                              for event in mission["result_events"]],
                             [(speaker, text_first + i, 355 + i)
                              for i, speaker in enumerate((20, 0, 0, 6, 0, 6, 0, 6, 0))])
            self.assertEqual(values["field"]["center"], [-30000, 0, 30000])
            self.assertEqual((values["field"]["count_base"],
                              values["field"]["count_bound"],
                              values["field"]["ore_item_id"],
                              values["field"]["model_id"]), (80, 80, 164, 16921))
            actors = values["void_population"]
            self.assertEqual((actors["initial_count"], actors["first_draw_bound"],
                              actors["second_draw_only_if_base_plus_first_at_least"],
                              actors["second_draw_bound"], actors["count_if_second_drawn"]),
                             (2, 2, 2.0, 2, "truncate_base_plus_second"))
            self.assertEqual((actors["actor_kind"], actors["actor_subtype"], actors["hull_id"]),
                             (9, 0, 8))
            self.assertEqual(actors["position_bounds"], [120000, 80000, 120000])
            self.assertEqual(actors["position_offsets"], [-60000, -40000, -60000])
            self.assertEqual(actors["shared_activation_setter_argument"], 1)
            result = mission["completion"]
            self.assertEqual((result["cargo_predicate"], result["intermediate_next_keeps_cursor"],
                              result["final_next_advances_to_cursor"]), ("at_least", 33, 34))
            final = values["final_next"]
            self.assertEqual((final["debit_item_id"], final["debit_quantity"],
                              final["reward_credits"]), (164, 50, 0))
            self.assertTrue(final["preserves_surplus_cargo"])
            blueprint = final["blueprint"]
            self.assertEqual((blueprint["item_id"], blueprint["recipe_item_id"],
                              blueprint["recipe_precredit_quantity"]), (85, 164, 50))
            self.assertTrue(blueprint["only_if_existing_item_entry"])
            self.assertFalse(blueprint["grants_player_cargo"] or blueprint["installs_drive"])
            self.assertEqual(values["next_mission"],
                             {"campaign_cursor": 34, "kind": 11, "station_id": 30,
                              "system_id": 2, "story": True, "reward": 0, "bonus": 0})


if __name__ == "__main__":
    unittest.main()
