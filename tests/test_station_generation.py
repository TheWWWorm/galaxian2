"""Stock and hidden contact support requires every bounded source declaration."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import station_generation as reader


class StationGenerationTests(unittest.TestCase):
    def test_relocation_and_source_mutations(self):
        for shift in (0,0x800000):
            mach,arrival,layouts=declaration_fixture(reader.LAYOUTS,shift)
            with patch.object(reader,'LAYOUTS',layouts):
                values,proof=reader.extract_station_generation(mach,arrival)
                self.assertEqual(values,reader.VALUES)
                self.assertEqual(set(proof),set(layouts))
                for name,(delta,_,_,_) in layouts.items():
                    changed=copy.copy(mach)
                    raw=bytearray(mach.data)
                    raw[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                    changed.data=bytes(raw)
                    self.assertEqual(reader.extract_station_generation(changed,arrival),({},{}),name)
                values['initial_history'][0]=True
                self.assertEqual(reader.extract_station_generation(mach,arrival)[0],reader.VALUES)

    def test_other_architecture_remains_unavailable(self):
        mach,arrival,_=declaration_fixture(reader.LAYOUTS)
        mach.architecture='armv7'
        self.assertEqual(reader.extract_station_generation(mach,arrival),({},{}))
