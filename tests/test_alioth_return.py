"""Alioth attack declarations reject altered source spans and other editions."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import alioth_return as reader


class AliothReturnTests(unittest.TestCase):
    def test_relocation_and_source_mutations(self):
        for shift in (0,0x800000):
            mach,arrival,layouts=declaration_fixture(reader.LAYOUTS,shift)
            with patch.object(reader,'LAYOUTS',layouts):
                values,proof=reader.extract_alioth_return(mach,arrival)
                self.assertEqual(values,reader.VALUES)
                self.assertEqual(set(proof),set(layouts))
                for name,(delta,_,_,_) in layouts.items():
                    changed=copy.copy(mach)
                    raw=bytearray(mach.data)
                    raw[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                    changed.data=bytes(raw)
                    self.assertEqual(reader.extract_alioth_return(changed,arrival),({},{}),name)
                values['events'][0]['text_id']=0
                self.assertEqual(reader.extract_alioth_return(mach,arrival)[0],reader.VALUES)

    def test_other_architecture_remains_unavailable(self):
        mach,arrival,_=declaration_fixture(reader.LAYOUTS)
        mach.architecture='armv7'
        self.assertEqual(reader.extract_alioth_return(mach,arrival),({},{}))
