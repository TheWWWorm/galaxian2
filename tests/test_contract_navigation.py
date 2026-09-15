"""Optional Mac navigation declarations preserve earlier travel profiles."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import mido_travel as reader


class ContractNavigationTests(unittest.TestCase):
    def extract(self, mach, arrival):
        return reader.extract_mido_travel(mach,arrival,
            {'scope':'first_station_entry'},
            {'scope':'combat_training_encounter_construction'})

    def test_navigation_is_detached_and_relocatable(self):
        original = {'anchor': [0,315,'__text','']}
        for shift in (0,0x800000):
            mach,arrival,layouts=declaration_fixture({**original,**reader.NAVIGATION_LAYOUTS},shift)
            base={'anchor':layouts.pop('anchor')}
            with patch.object(reader,'LAYOUTS',base),patch.object(reader,'CONTINUATION_LAYOUTS',{}),patch.object(reader,'RETURN_LAYOUTS',{}),patch.object(reader,'NAVIGATION_LAYOUTS',layouts):
                result=self.extract(mach,arrival)
                self.assertEqual(result['contract_navigation'],reader.CONTRACT_NAVIGATION)
                self.assertEqual(result['contract_navigation']['station_ids'],[75,76,77,78,79])
                self.assertEqual(result['contract_navigation']['npc_weapon_interval_ms'],574)
                for key,span in layouts.items():
                    self.assertEqual(result['provenance'][key]['offset'],arrival['provenance']['actor']['offset']+span[0])
                result['contract_navigation']['station_ids'].clear()
                self.assertEqual(len(self.extract(mach,arrival)['contract_navigation']['station_ids']),5)

    def test_changed_navigation_preserves_prior_journeys(self):
        mach,arrival,layouts=declaration_fixture({'anchor':[0,315,'__text',''],**reader.NAVIGATION_LAYOUTS})
        base={'anchor':layouts.pop('anchor')}
        with patch.object(reader,'LAYOUTS',base),patch.object(reader,'CONTINUATION_LAYOUTS',{}),patch.object(reader,'RETURN_LAYOUTS',{}),patch.object(reader,'NAVIGATION_LAYOUTS',layouts):
            for key,(delta,_,_,_) in layouts.items():
                changed=copy.copy(mach);data=bytearray(mach.data)
                data[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                changed.data=bytes(data)
                result=self.extract(changed,arrival)
                self.assertNotIn('contract_navigation',result,key)
                self.assertEqual(result['return_visit'],reader.RETURN_VISIT)
                self.assertEqual(result['continuation'],reader.CONTINUATION)
                self.assertEqual(set(result['provenance']),{'anchor'})

    def test_wrong_architecture_cannot_enable_navigation(self):
        mach,arrival,_=declaration_fixture(reader.NAVIGATION_LAYOUTS)
        mach.architecture='armv7'
        self.assertEqual(self.extract(mach,arrival),{})
