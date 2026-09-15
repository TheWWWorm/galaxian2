"""Freighter lifecycle recognition is optional, relocated and fail-closed."""
import copy
import unittest
from unittest.mock import patch
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from declaration_fixture import declaration_fixture
from gof2_content import freighter_destruction as reader


class FreighterDestructionTests(unittest.TestCase):
    def test_relocated_and_independent_declarations(self):
        for shift in [0,0x900000]:
            mach,arrival,layouts=declaration_fixture(reader.LAYOUTS,shift)
            with patch.object(reader,'LAYOUTS',layouts):
                result=reader.extract_freighter_destruction(mach,arrival,reader.COMBAT_VALUES)
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                for key,span in result['provenance'].items():
                    self.assertEqual(span,{'offset':arrival['provenance']['actor']['offset']+layouts[key][0],'bytes':layouts[key][1]})
                result['model_id']=-1
                self.assertEqual(reader.extract_freighter_destruction(mach,arrival,reader.COMBAT_VALUES)['model_id'],18300)

    def test_altered_or_truncated_source_is_unsupported(self):
        mach,arrival,layouts=declaration_fixture(reader.LAYOUTS)
        with patch.object(reader,'LAYOUTS',layouts):
            for key,(delta,_,_,_) in layouts.items():
                changed=copy.copy(mach);data=bytearray(mach.data)
                data[arrival['provenance']['actor']['offset']-mach.slice_offset+delta]^=255
                changed.data=bytes(data)
                self.assertFalse(reader.extract_freighter_destruction(changed,arrival,reader.COMBAT_VALUES),key)
            for i in range(len(mach.sections)):
                changed=copy.deepcopy(mach);changed.sections[i]['length']-=1
                self.assertFalse(reader.extract_freighter_destruction(changed,arrival,reader.COMBAT_VALUES),i)

    def test_requires_source_combat_context(self):
        mach,arrival,layouts=declaration_fixture(reader.LAYOUTS)
        with patch.object(reader,'LAYOUTS',layouts):
            for key in ['scope','freighter','campaign_cursor']:
                data=copy.deepcopy(reader.COMBAT_VALUES);data.pop(key)
                self.assertFalse(reader.extract_freighter_destruction(mach,arrival,data),key)
            changed=copy.copy(mach);changed.architecture='armv7'
            self.assertFalse(reader.extract_freighter_destruction(changed,arrival,reader.COMBAT_VALUES))
            self.assertFalse(reader.extract_freighter_destruction(mach,arrival,None))
