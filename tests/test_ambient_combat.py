"""Combat declarations remain optional and reject altered source extents."""
import copy
import unittest
from unittest.mock import patch
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from declaration_fixture import declaration_fixture
from gof2_content import ambient_combat as reader


class AmbientCombatTests(unittest.TestCase):
    def test_relocated_source_and_independent_result(self):
        for shift in [0,0xB00000]:
            mach,arrival,layouts=declaration_fixture(reader.LAYOUTS,shift)
            with patch.object(reader,'LAYOUTS',layouts):
                result=reader.extract_ambient_combat(mach,arrival,reader.POPULATION_VALUES)
                self.assertEqual({key:value for key,value in result.items() if key!='provenance'},reader.VALUES)
                for key,span in result['provenance'].items():
                    self.assertEqual(span,{'offset':arrival['provenance']['actor']['offset']+layouts[key][0],'bytes':layouts[key][1]})
                result['freighter']['boxes'][0]['offset'][0]=9
                self.assertEqual(reader.extract_ambient_combat(mach,arrival,reader.POPULATION_VALUES)['freighter'],reader.VALUES['freighter'])

    def test_modified_or_truncated_source_is_unsupported(self):
        mach,arrival,layouts=declaration_fixture(reader.LAYOUTS)
        with patch.object(reader,'LAYOUTS',layouts):
            for key,(delta,_,_,_) in layouts.items():
                changed=copy.copy(mach);data=bytearray(mach.data)
                data[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                changed.data=bytes(data)
                self.assertFalse(reader.extract_ambient_combat(changed,arrival,reader.POPULATION_VALUES),key)
            for index in range(len(mach.sections)):
                changed=copy.deepcopy(mach);changed.sections[index]['length']-=1
                self.assertFalse(reader.extract_ambient_combat(changed,arrival,reader.POPULATION_VALUES),index)

    def test_population_and_architecture_are_required(self):
        mach,arrival,layouts=declaration_fixture(reader.LAYOUTS)
        with patch.object(reader,'LAYOUTS',layouts):
            for key in ['scope','freighter','contexts']:
                population=copy.deepcopy(reader.POPULATION_VALUES);population.pop(key)
                self.assertFalse(reader.extract_ambient_combat(mach,arrival,population),key)
            changed=copy.copy(mach);changed.architecture='armv7'
            self.assertFalse(reader.extract_ambient_combat(changed,arrival,reader.POPULATION_VALUES))
            shifted=copy.deepcopy(arrival);shifted['provenance']['actor']['offset']+=1
            self.assertFalse(reader.extract_ambient_combat(mach,shifted,reader.POPULATION_VALUES))
            self.assertFalse(reader.extract_ambient_combat(mach,arrival,None))
