"""Synthetic source boundaries; no original executable or earned profile fixtures."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import deep_science_stock as reader


class DeepScienceStockTests(unittest.TestCase):
    def test_both_layouts_relocate_and_return_detached_declarations(self):
        for name, base in (('LAYOUTS', reader.BASE_VALUES), ('MAC_ALTERNATE', reader.MAC_BASE_VALUES)):
            for shift in (0, 0x700000):
                mach, arrival, proofs = declaration_fixture(getattr(reader, name), shift)
                with patch.object(reader, name, proofs):
                    result = reader.extract_deep_science_stock(mach, arrival, base)
                    self.assertEqual({k: v for k, v in result.items() if k != 'provenance'}, reader.VALUES)
                    for key, span in result['provenance'].items():
                        self.assertEqual(span, {'offset': arrival['provenance']['actor']['offset'] + proofs[key][0], 'bytes': proofs[key][1]})
                    result['all_base_gold_ship_id'] = 1
                    result['provenance'].clear()
                    again = reader.extract_deep_science_stock(mach, arrival, base)
                    self.assertEqual(again['all_base_gold_ship_id'], 8)
                    self.assertEqual(set(again['provenance']), set(proofs))

    def test_every_source_extent_endpoint_and_section_is_required(self):
        for name, base in (('LAYOUTS', reader.BASE_VALUES), ('MAC_ALTERNATE', reader.MAC_BASE_VALUES)):
            mach, arrival, proofs = declaration_fixture(getattr(reader, name))
            with patch.object(reader, name, proofs):
                for key, (delta, size, _, _) in proofs.items():
                    for endpoint in (0, size - 1):
                        changed = copy.copy(mach)
                        raw = bytearray(mach.data)
                        raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta + endpoint] ^= 255
                        changed.data = bytes(raw)
                        self.assertFalse(reader.extract_deep_science_stock(changed, arrival, base), (name, key, endpoint))
                for index in range(len(mach.sections)):
                    changed = copy.deepcopy(mach)
                    changed.sections[index]['length'] -= 1
                    self.assertFalse(reader.extract_deep_science_stock(changed, arrival, base), (name, index))

    def test_missing_anchor_architecture_and_mixed_base_declarations_refuse(self):
        for name, base, other in (('LAYOUTS', reader.BASE_VALUES, reader.MAC_BASE_VALUES),
                                  ('MAC_ALTERNATE', reader.MAC_BASE_VALUES, reader.BASE_VALUES)):
            mach, arrival, proofs = declaration_fixture(getattr(reader, name))
            with patch.object(reader, name, proofs):
                self.assertFalse(reader.extract_deep_science_stock(mach, arrival, other))
                for mutation in ('architecture', 'anchor', 'anchor_size', 'missing_base', 'changed_base'):
                    m, a, b = copy.copy(mach), copy.deepcopy(arrival), copy.deepcopy(base)
                    if mutation == 'architecture':
                        m.architecture = 'armv7'
                    elif mutation == 'anchor':
                        a['provenance']['actor']['offset'] += 1
                    elif mutation == 'anchor_size':
                        a['provenance']['actor']['bytes'] = 314
                    elif mutation == 'missing_base':
                        b = {}
                    else:
                        b['ships']['count_draw_bound'] += 1
                    self.assertFalse(reader.extract_deep_science_stock(m, a, b), mutation)

    def test_partial_and_ambiguous_layouts_are_not_combined(self):
        mach, arrival, proofs = declaration_fixture(reader.LAYOUTS)
        first, second = copy.deepcopy(proofs), copy.deepcopy(proofs)
        keys = list(proofs)
        first[keys[0]][3] = '0' * 64
        second[keys[-1]][3] = '0' * 64
        with patch.multiple(reader, LAYOUTS=first, MAC_ALTERNATE=second):
            self.assertFalse(reader.extract_deep_science_stock(mach, arrival, reader.BASE_VALUES))
        with patch.multiple(reader, LAYOUTS=proofs, MAC_ALTERNATE=proofs):
            self.assertFalse(reader.extract_deep_science_stock(mach, arrival, reader.BASE_VALUES))
