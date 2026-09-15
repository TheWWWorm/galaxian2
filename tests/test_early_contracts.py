"""Contract terms require their own verified, relocated Mac source extents."""
import copy
from contextlib import contextmanager
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import early_contracts as reader


class EarlyContractTests(unittest.TestCase):
    @contextmanager
    def fixture(self, shift=0):
        mach, arrival, layouts = declaration_fixture({**reader.LAYOUTS, **reader.ACCEPTANCE_LAYOUTS}, shift)
        base = {key: layouts[key] for key in reader.LAYOUTS}
        acceptance = {key: layouts[key] for key in reader.ACCEPTANCE_LAYOUTS}
        with patch.object(reader, 'LAYOUTS', base), patch.object(reader, 'ACCEPTANCE_LAYOUTS', acceptance):
            yield mach, arrival, layouts

    def extract(self, mach, arrival, travel=None):
        if travel is None:
            travel = {'scope': 'mido_local_travel', 'return_visit': {'next_cursor': 13, 'next_kind': 150}}
        return reader.extract_early_contracts(mach, arrival, travel)

    def test_relocation_and_detached_data(self):
        for shift in [0, 0x800000]:
            with self.fixture(shift) as (mach, arrival, layouts):
                result = self.extract(mach, arrival)
                self.assertEqual(result['kind_choices'], [11, 0, 7, 4, 12])
                self.assertEqual(result['courier']['quantity_by_difficulty'], [14, 24])
                self.assertEqual(result['passenger']['quantity_by_difficulty'], [3, 5])
                self.assertEqual(result['acceptance']['fee_difficulty'], 1.5)
                for key, span in result['provenance'].items():
                    self.assertEqual(span['offset'], arrival['provenance']['actor']['offset'] + layouts[key][0])
                result['kind_choices'][0] = 150
                result['reward']['base'] = 0
                result['acceptance']['initial_credits'] = 10000
                self.assertEqual(self.extract(mach, arrival)['reward']['base'], 1500)
                self.assertEqual(self.extract(mach, arrival)['kind_choices'][0], 11)
                self.assertEqual(self.extract(mach, arrival)['acceptance']['initial_credits'], 0)

    def test_each_changed_or_truncated_span_rejects_terms(self):
        with self.fixture() as (mach, arrival, layouts):
            for key, (delta, _, _, _) in layouts.items():
                changed = copy.copy(mach)
                data = bytearray(mach.data)
                data[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta] ^= 255
                changed.data = bytes(data)
                result = self.extract(changed, arrival)
                if key in reader.LAYOUTS:
                    self.assertFalse(result, key)
                else:
                    self.assertNotIn('acceptance', result, key)
                    self.assertEqual(result['kind_choices'], reader.VALUES['kind_choices'])
                    self.assertEqual(set(result['provenance']), set(reader.LAYOUTS))
            changed = copy.deepcopy(mach)
            changed.sections[-1]['length'] -= 1
            self.assertNotIn('acceptance', self.extract(changed, arrival))

    def test_requires_mac_and_lounge_story_boundary(self):
        with self.fixture() as (mach, arrival, _):
            self.assertFalse(self.extract(mach, arrival, {}))
            self.assertFalse(self.extract(mach, arrival, {'scope': 'mido_local_travel'}))
            mach.architecture = 'armv7'
            self.assertFalse(self.extract(mach, arrival))
