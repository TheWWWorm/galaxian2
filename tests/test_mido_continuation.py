"""The next local visit remains gated by its additional source declarations."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import mido_travel as reader

class MidoContinuationTests(unittest.TestCase):
    def extract(self,mach,arrival):
        return reader.extract_mido_travel(mach,arrival,{'scope':'first_station_entry'},{'scope':'combat_training_encounter_construction'})

    def test_relocated_source_and_detached_events(self):
        for shift in [0,0x800000]:
            mach,arrival,layouts=declaration_fixture({**reader.CONTINUATION_LAYOUTS,**reader.RETURN_LAYOUTS},shift)
            with patch.object(reader,'LAYOUTS',{}),patch.object(reader,'CONTINUATION_LAYOUTS',layouts),patch.object(reader,'RETURN_LAYOUTS',{}):
                result=self.extract(mach,arrival)
                self.assertEqual(result['continuation'],reader.CONTINUATION)
                self.assertEqual(len(result['continuation']['events']),13)
                self.assertEqual(result['return_visit'],reader.RETURN_VISIT)
                self.assertEqual(len(result['return_visit']['events']),8)
                self.assertEqual(result['return_visit']['events'][-1]['voice_event_id'],-1)
                self.assertEqual(result['return_visit']['contract_gate']['additional_completions'],4)
                for key,span in result['provenance'].items():
                    self.assertEqual(span['offset'],arrival['provenance']['actor']['offset']+layouts[key][0])
                result['continuation']['events'][0]['speaker_id']=-1
                self.assertEqual(self.extract(mach,arrival)['continuation']['events'][0]['speaker_id'],0)

    def test_changed_or_missing_proof_rejects_capability(self):
        mach,arrival,layouts=declaration_fixture({**reader.CONTINUATION_LAYOUTS,**reader.RETURN_LAYOUTS})
        with patch.object(reader,'LAYOUTS',{}),patch.object(reader,'CONTINUATION_LAYOUTS',layouts),patch.object(reader,'RETURN_LAYOUTS',{}):
            for key,(delta,_,_,_) in layouts.items():
                changed=copy.copy(mach);data=bytearray(mach.data)
                data[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                changed.data=bytes(data)
                self.assertFalse(self.extract(changed,arrival),key)
            changed=copy.deepcopy(mach);changed.sections[-1]['length']-=1
            self.assertFalse(self.extract(changed,arrival))
            changed=copy.copy(mach);changed.architecture='armv7'
            self.assertFalse(self.extract(changed,arrival))

    def test_requires_existing_station_and_training_source_context(self):
        mach,arrival,layouts=declaration_fixture({**reader.CONTINUATION_LAYOUTS,**reader.RETURN_LAYOUTS})
        with patch.object(reader,'LAYOUTS',{}),patch.object(reader,'CONTINUATION_LAYOUTS',layouts),patch.object(reader,'RETURN_LAYOUTS',{}):
            self.assertFalse(reader.extract_mido_travel(mach,arrival,{},{}))
