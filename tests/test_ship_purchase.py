"""Guard ordinary ship exchange declarations without original game fixtures."""

import copy
import json
from pathlib import Path
import re
import unittest
from unittest.mock import patch

from declaration_fixture import declaration_fixture
from gof2_content import ship_purchase as reader
from gof2_content.ordinary_shopping import VALUES as SHOPPING


NATIVE = Path(__file__).resolve().parents[1] / 'game/src/content/ship_purchase_definitions.gd'


class ShipPurchaseDeclarations(unittest.TestCase):
    def test_both_complete_layouts_relocate_and_return_detached_values(self):
        for selected, other in ((reader.LAYOUTS, reader.MAC_ALTERNATE),
                                (reader.MAC_ALTERNATE, reader.LAYOUTS)):
            for relocation in (0, 0x800000):
                mach, arrival, synthetic = declaration_fixture(selected, relocation)
                with patch.multiple(reader, LAYOUTS=synthetic, MAC_ALTERNATE=other):
                    result = reader.extract_ship_purchase(mach, arrival, SHOPPING)
                    self.assertEqual({k: v for k, v in result.items() if k != 'provenance'}, reader.VALUES)
                    self.assertEqual(set(result['provenance']), set(selected))
                    for key, row in synthetic.items():
                        self.assertEqual(result['provenance'][key], {
                            'offset': arrival['provenance']['actor']['offset'] + row[0],
                            'bytes': row[1],
                        })
                    result['transfer']['purchased_ship_tags_source'] = 'old_current_instance'
                    result['entry']['fresh_catalogue_generated_offer_tags'].append(0)
                    result['provenance'].clear()
                    again = reader.extract_ship_purchase(mach, arrival, SHOPPING)
                    self.assertEqual(again['transfer']['purchased_ship_tags_source'], 'offered_instance')
                    self.assertEqual(again['entry']['fresh_catalogue_generated_offer_tags'], [])
                    self.assertEqual(set(again['provenance']), set(selected))

    def test_quote_entry_and_generated_offer_tag_scopes(self):
        entry = reader.VALUES['entry']
        self.assertEqual(entry['fresh_career_current_ship_id'], 10)
        self.assertEqual(entry['fresh_career_quote_divisor'], 1.25)
        self.assertEqual(entry['fresh_career_quote_arithmetic'], 'float32_division_then_truncate_i32')
        self.assertEqual(entry['hangar_refresh_pricing_owner'], 'ordinary_base_station_stock.ships')
        self.assertTrue(entry['hangar_refresh_requires_current_station'])
        self.assertTrue(entry['hangar_refresh_requires_positive_existing_quote'])
        self.assertEqual(entry['fresh_catalogue_generated_offer_tags'], [])
        self.assertEqual(reader.VALUES['transfer']['former_ship_tags_source'], 'old_current_instance')

    def test_each_corrupt_or_missing_source_span_refuses_whole_capability(self):
        for selected, other in ((reader.LAYOUTS, reader.MAC_ALTERNATE),
                                (reader.MAC_ALTERNATE, reader.LAYOUTS)):
            mach, arrival, synthetic = declaration_fixture(selected)
            with patch.multiple(reader, LAYOUTS=synthetic, MAC_ALTERNATE=other):
                for key, (delta, size, _, _) in synthetic.items():
                    for endpoint in (0, size - 1):
                        changed = copy.copy(mach)
                        raw = bytearray(mach.data)
                        raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta + endpoint] ^= 0xff
                        changed.data = bytes(raw)
                        self.assertEqual(reader.extract_ship_purchase(changed, arrival, SHOPPING), {},
                                         (key, endpoint))
                for mutation in ('architecture', 'anchor', 'anchor_size', 'missing_shopping', 'changed_shopping'):
                    changed = copy.copy(mach)
                    anchored = copy.deepcopy(arrival)
                    shopping = copy.deepcopy(SHOPPING)
                    if mutation == 'architecture':
                        changed.architecture = 'armv7'
                    elif mutation == 'anchor':
                        anchored['provenance']['actor']['offset'] += 1
                    elif mutation == 'anchor_size':
                        anchored['provenance']['actor']['bytes'] = 314
                    elif mutation == 'missing_shopping':
                        shopping = {}
                    else:
                        shopping['transfer']['overfilled_departure_text_id'] += 1
                    self.assertEqual(reader.extract_ship_purchase(changed, anchored, shopping), {}, mutation)

    def test_mixed_and_ambiguous_layouts_refuse(self):
        mach, arrival, synthetic = declaration_fixture(reader.LAYOUTS)
        first, second = copy.deepcopy(synthetic), copy.deepcopy(synthetic)
        keys = list(synthetic)
        first[keys[0]][3] = '0' * 64
        second[keys[-1]][3] = '0' * 64
        with patch.multiple(reader, LAYOUTS=first, MAC_ALTERNATE=second):
            self.assertFalse(reader.extract_ship_purchase(mach, arrival, SHOPPING))
        with patch.multiple(reader, LAYOUTS=synthetic, MAC_ALTERNATE=synthetic):
            self.assertFalse(reader.extract_ship_purchase(mach, arrival, SHOPPING))

    def test_native_constants_and_proof_layouts_match_reader(self):
        source = NATIVE.read_text()
        for name, expected in (
            ('VALUES', reader.VALUES),
            ('SPANS', {key: row[:2] for key, row in reader.LAYOUTS.items()}),
            ('MAC_SPANS', {key: row[:2] for key, row in reader.MAC_ALTERNATE.items()}),
        ):
            match = re.search(r'^const ' + name + r' := (.+)$', source, re.MULTILINE)
            self.assertIsNotNone(match, name)
            self.assertEqual(json.loads(match.group(1)), expected)


if __name__ == '__main__':
    unittest.main()
