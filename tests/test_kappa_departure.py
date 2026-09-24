"""Both launch variants keep complete, relocation-safe source proof sets."""
from contextlib import ExitStack
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import kappa_departure as reader


class KappaDepartureTests(unittest.TestCase):
    def test_coherent_variants_and_mutations(self):
        for group, expected in [('LAYOUTS', reader.VALUES), ('MAC_ALTERNATE', reader.MAC_VALUES)]:
            for shift in [0, 0x800000]:
                with self.subTest(group=group, shift=shift), ExitStack() as stack:
                    mach, arrival, layouts = declaration_fixture(getattr(reader, group), shift)
                    stack.enter_context(patch.object(reader, group, layouts))
                    values, proof = reader.extract_kappa_departure(mach, arrival)
                    self.assertEqual(values, expected)
                    self.assertEqual(set(proof), set(layouts))
                    values['installed_item_ids'].clear()
                    self.assertEqual(reader.extract_kappa_departure(mach, arrival)[0], expected)
                    for name, (delta, size, _, _) in layouts.items():
                        for edge in [0, size - 1]:
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta + edge] ^= 255
                            changed.data = bytes(raw)
                            self.assertEqual(reader.extract_kappa_departure(changed, arrival), ({}, {}), (name, edge))
                    mach.architecture = 'armv7'
                    self.assertEqual(reader.extract_kappa_departure(mach, arrival), ({}, {}))
