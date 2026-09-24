"""Tractor declarations require one complete reviewed Mac source layout."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture, verify_hashed_declarations
from gof2_content import tractor_recovery as reader


class TractorRecoveryTests(unittest.TestCase):
    def test_proofs_and_relocation(self):
        verify_hashed_declarations(self, reader, reader.extract_tractor_recovery, 'transfer')

    def test_complete_alternate(self):
        for relocation in (0, 0x800000):
            mach, arrival, alternate = declaration_fixture(reader.MAC_ALTERNATE, relocation)
            with patch.object(reader, 'MAC_ALTERNATE', alternate):
                values, proof = reader.extract_tractor_recovery(mach, arrival)
                self.assertEqual(values, reader.VALUES)
                self.assertEqual(set(proof), set(alternate))
                for name, (delta, _, _, _) in alternate.items():
                    changed = copy.copy(mach)
                    raw = bytearray(mach.data)
                    raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta] ^= 255
                    changed.data = bytes(raw)
                    self.assertEqual(reader.extract_tractor_recovery(changed, arrival), ({}, {}), name)

    def test_ambiguous_layout_refused(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts), patch.object(reader, 'MAC_ALTERNATE', layouts):
            self.assertEqual(reader.extract_tractor_recovery(mach, arrival), ({}, {}))
