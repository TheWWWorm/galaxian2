"""Lounge presentation declarations require all verified import extents."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import lounge_presentation as reader

class LoungePresentationTests(unittest.TestCase):
    def test_relocation_and_changed_source(self):
        for shift in (0,0x800000):
            mach,arrival,layouts=declaration_fixture(reader.LAYOUTS,shift)
            with patch.object(reader,'LAYOUTS',layouts):
                values,proof=reader.extract_lounge_presentation(mach,arrival)
                self.assertEqual(values,reader.VALUES)
                self.assertEqual(set(proof),set(layouts))
                for name,(delta,_,_,_) in layouts.items():
                    changed=copy.copy(mach);raw=bytearray(mach.data)
                    raw[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                    changed.data=bytes(raw)
                    self.assertEqual(reader.extract_lounge_presentation(changed,arrival),({},{}),name)
                values['camera']['positions'][0][0]=0
                self.assertEqual(reader.extract_lounge_presentation(mach,arrival)[0],reader.VALUES)

    def test_unrecognized_architecture(self):
        mach,arrival,_=declaration_fixture(reader.LAYOUTS)
        mach.architecture='armv7'
        self.assertEqual(reader.extract_lounge_presentation(mach,arrival),({},{}))
