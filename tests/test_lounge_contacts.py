"""The optional contact reader fails closed without its own source evidence."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import lounge_contacts as reader


class LoungeContactTests(unittest.TestCase):
    def test_relocated_declarations_and_detached_results(self):
        for shift in [0, 0x800000]:
            mach, arrival, layouts = declaration_fixture(reader.LAYOUTS, shift)
            with patch.object(reader, 'LAYOUTS', layouts):
                values, proof = reader.extract_lounge_contacts(mach, arrival)
                self.assertEqual(values['destinations']['helper_excluded_station_ids'], [76, 79])
                self.assertEqual(values['names']['pool_choices_by_faction'][3], [[0, 5], [2, 6]])
                self.assertEqual(values['portraits']['counts'][6], [2, 3, 5, 0])
                self.assertEqual(values['hostile_replacement']['factions'], [2, 3, 0, 1])
                for key, span in proof.items():
                    self.assertEqual(span['offset'], arrival['provenance']['actor']['offset'] + layouts[key][0])
                values['names']['resources'].clear()
                values['mission_history']['reset_count'] = 0
                fresh, _ = reader.extract_lounge_contacts(mach, arrival)
                self.assertEqual(len(fresh['names']['resources']), 13)
                self.assertEqual(fresh['mission_history']['reset_count'], 14)

    def test_changed_and_truncated_spans_disable_only_this_capability(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts):
            for key, (delta, length, _, _) in layouts.items():
                changed = copy.copy(mach)
                at = arrival['provenance']['actor']['offset'] - mach.slice_offset + delta
                data = bytearray(mach.data)
                data[at + length - 1] ^= 255
                changed.data = bytes(data)
                self.assertEqual(reader.extract_lounge_contacts(changed, arrival), ({}, {}), key)
                changed = copy.deepcopy(mach)
                next(section for section in changed.sections if section['offset'] == at)['length'] -= 1
                self.assertEqual(reader.extract_lounge_contacts(changed, arrival), ({}, {}), key)

    def test_requires_mac_and_valid_source_anchor(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts):
            self.assertEqual(reader.extract_lounge_contacts(mach, {}), ({}, {}))
            mach.architecture = 'armv7'
            self.assertEqual(reader.extract_lounge_contacts(mach, arrival), ({}, {}))
