"""Source variant admission for the first recurring Void portal."""
import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import void_portal as reader


class VoidPortalTests(unittest.TestCase):
    def test_source_variants_and_corrupt_extents(self):
        for name in ('LAYOUTS', 'MAC_ALTERNATE'):
            for relocation in (0, 0x800000):
                mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                with self.subTest(variant=name, relocation=relocation), patch.object(reader, name, layouts):
                    values, proof = reader.extract_void_portal(mach, arrival)
                    self.assertEqual(values, reader.VALUES)
                    self.assertEqual(set(proof), set(layouts))
                    values['portal']['relocation']['random_bounds'].clear()
                    self.assertEqual(reader.extract_void_portal(mach, arrival)[0], reader.VALUES)
                    for key, (delta, count, _, _) in layouts.items():
                        for endpoint in (0, count - 1):
                            damaged = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta + endpoint] ^= 255
                            damaged.data = bytes(raw)
                            self.assertEqual(reader.extract_void_portal(damaged, arrival), ({}, {}), key)
                    mach.architecture = 'armv7'
                    self.assertEqual(reader.extract_void_portal(mach, arrival), ({}, {}))

    def test_ambiguous_source_and_missing_anchor(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts), patch.object(reader, 'MAC_ALTERNATE', layouts):
            self.assertEqual(reader.extract_void_portal(mach, arrival), ({}, {}))
        self.assertEqual(reader.extract_void_portal(mach, {}), ({}, {}))

    def test_native_values_and_proof_extents_match(self):
        native = (Path(__file__).resolve().parents[1] / 'game/src/content/void_portal_definitions.gd').read_text()
        for name, expected in [('VALUES', reader.VALUES), ('SPANS', {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                               ('MAC_SPANS', {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})]:
            matches = re.findall(r'^const ' + name + r' = (.+)$', native, re.MULTILINE)
            self.assertEqual(len(matches), 1, name)
            self.assertEqual(json.loads(matches[0]), expected, name)


if __name__ == '__main__':
    unittest.main()
