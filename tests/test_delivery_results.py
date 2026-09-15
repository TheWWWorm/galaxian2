"""A damaged optional settlement reader must preserve verified lounge content."""
import copy
from contextlib import ExitStack, contextmanager
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import early_contracts, lounge_contacts, delivery_results


class DeliveryResultTests(unittest.TestCase):
    @contextmanager
    def fixture(self, shift=0):
        declarations = [(early_contracts, 'LAYOUTS'), (early_contracts, 'ACCEPTANCE_LAYOUTS'),
                        (lounge_contacts, 'LAYOUTS'), (delivery_results, 'LAYOUTS')]
        combined = {k:v for module, name in declarations for k,v in getattr(module, name).items()}
        # Real extents share instruction bytes. Give the independent synthetic
        # byte patterns disjoint locations so one fixture cannot overwrite another.
        at = -0x80000
        for key, (_, size, section, digest) in list(combined.items()):
            combined[key] = [at, size, section, digest]
            at += size+16
        mach, arrival, layouts = declaration_fixture(combined, shift)
        with ExitStack() as stack:
            for module, name in declarations:
                stack.enter_context(patch.object(module, name, {k:layouts[k] for k in getattr(module, name)}))
            yield mach, arrival, layouts

    def extract(self, mach, arrival):
        return early_contracts.extract_early_contracts(mach, arrival, {
            'scope':'mido_local_travel', 'return_visit':{'next_cursor':13, 'next_kind':150}})

    def test_relocated_complete_reader_and_detached_values(self):
        for shift in [0, 0x900000]:
            with self.fixture(shift) as (mach, arrival, layouts):
                result = self.extract(mach, arrival)
                self.assertIn('generation', result)
                self.assertEqual(result['delivery_results']['completion_rank_weight'], 2)
                for key, span in result['provenance'].items():
                    self.assertEqual(span['offset'], arrival['provenance']['actor']['offset']+layouts[key][0])
                result['delivery_results']['reputation']['success_change'] = 100
                self.assertEqual(self.extract(mach, arrival)['delivery_results']['reputation']['success_change'], 5)

    def test_missing_damaged_or_truncated_result_extents_preserve_earlier_content(self):
        with self.fixture() as (mach, arrival, layouts):
            expected = self.extract(mach, arrival)
            expected.pop('delivery_results')
            for key in delivery_results.LAYOUTS:
                expected['provenance'].pop(key)
            for key in delivery_results.LAYOUTS:
                delta, length, _, _ = layouts[key]
                at = arrival['provenance']['actor']['offset']-mach.slice_offset+delta
                changed = copy.copy(mach)
                data = bytearray(mach.data)
                data[at+length-1] ^= 255
                changed.data = bytes(data)
                self.assertEqual(self.extract(changed, arrival), expected, key)
                changed = copy.deepcopy(mach)
                next(s for s in changed.sections if s['offset']==at)['length'] -= 1
                self.assertEqual(self.extract(changed, arrival), expected, key)

    def test_wrong_profile_or_anchor_cannot_enable_results(self):
        with self.fixture() as (mach, arrival, _):
            self.assertEqual(delivery_results.extract_delivery_results(mach, {}), ({}, {}))
            mach.architecture = 'armv7'
            self.assertEqual(delivery_results.extract_delivery_results(mach, arrival), ({}, {}))
