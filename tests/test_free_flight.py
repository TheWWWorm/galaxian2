"""Verify ordinary entry declarations require every original source proof."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import free_flight as reader

class FreeFlightTests(unittest.TestCase):
    def test_proofs_and_relocation(self):
        for relocation in (0,0x800000):
            mach,arrival,layouts=declaration_fixture(reader.LAYOUTS,relocation)
            with patch.object(reader,'LAYOUTS',layouts):
                values,proof=reader.extract_free_flight(mach,arrival)
                self.assertEqual(values,reader.VALUES)
                self.assertEqual(set(proof),set(layouts))
                values['departure_flags'].clear()
                self.assertEqual(reader.extract_free_flight(mach,arrival)[0],reader.VALUES)
                for name,(delta,_,_,_) in layouts.items():
                    changed=copy.copy(mach);raw=bytearray(mach.data)
                    raw[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                    changed.data=bytes(raw)
                    self.assertEqual(reader.extract_free_flight(changed,arrival),({},{}),name)
                mach.architecture='armv7'
                self.assertEqual(reader.extract_free_flight(mach,arrival),({},{}))
