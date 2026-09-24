"""Synthetic source extents only; no original executable or artwork fixtures."""
import copy,unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from declaration_fixture import declaration_fixture
from unittest.mock import patch
from gof2_content import engine_particles as reader


def fixture(shift=0):
    mach,arrival,layouts=declaration_fixture(reader.LAYOUTS,shift,'sha256:')
    damage={'scope':'damage_particle_sprite_presets','emitter_defaults':{}}
    return mach,arrival,damage,layouts


def opening_fixture(shift=0):
    combined={**reader.LAYOUTS,**reader.MAC_OPENING_SPANS}
    mach,arrival,layouts=declaration_fixture(combined,shift,'sha256:')
    damage={'scope':'damage_particle_sprite_presets','emitter_defaults':{}}
    base={key:layouts[key] for key in reader.LAYOUTS}
    opening={key:layouts[key] for key in reader.MAC_OPENING_SPANS}
    return mach,arrival,damage,base,opening


class EngineParticleTests(unittest.TestCase):
    def test_opening_hull_requires_complete_additional_source_proof(self):
        for shift in (0,0x700000):
            mach,arrival,damage,base,opening=opening_fixture(shift)
            with patch.multiple(reader,LAYOUTS=base,MAC_OPENING_SPANS=opening):
                result=reader.extract_engine_particles(mach,arrival,damage)
                self.assertEqual(result.get('opening_ship'),reader.OPENING_SHIP)
                self.assertEqual(set(result['provenance']),set(base)|set(opening))
                for key,(delta,size,_,_) in opening.items():
                    self.assertEqual(result['provenance'][key],{'offset':arrival['provenance']['actor']['offset']+delta,'bytes':size})
                    for endpoint in (0,size-1):
                        changed=copy.copy(mach);data=bytearray(mach.data)
                        data[arrival['provenance']['actor']['offset']-mach.slice_offset+delta+endpoint]^=255
                        changed.data=bytes(data)
                        unsupported=reader.extract_engine_particles(changed,arrival,damage)
                        self.assertNotIn('opening_ship',unsupported,(key,endpoint))
                result['opening_ship']['uv_rect'][0]=0
                self.assertEqual(reader.extract_engine_particles(mach,arrival,damage)['opening_ship'],reader.OPENING_SHIP)

    def test_relocated_source_and_detached_data_only_result(self):
        for shift in [0,0x700000]:
            mach,arrival,damage,layouts=fixture(shift)
            with patch.object(reader,'LAYOUTS',layouts):
                result=reader.extract_engine_particles(mach,arrival,damage)
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                for key,span in result['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span,{'offset':arrival['provenance']['actor']['offset']+layouts[key][0],'bytes':layouts[key][1]})
                result['preset']['uv_rect'][0]=0
                self.assertNotEqual(result['preset'],reader.extract_engine_particles(mach,arrival,damage)['preset'])

    def test_every_required_span_and_section_extent(self):
        mach,arrival,damage,layouts=fixture()
        with patch.object(reader,'LAYOUTS',layouts):
            for key,(delta,_,_,_) in layouts.items():
                changed=copy.copy(mach);data=bytearray(mach.data)
                at=arrival['provenance']['actor']['offset']-mach.slice_offset+delta
                data[at]^=255;changed.data=bytes(data)
                self.assertFalse(reader.extract_engine_particles(changed,arrival,damage),key)
            for index in range(len(mach.sections)):
                changed=copy.deepcopy(mach);changed.sections[index]['length']-=1
                self.assertFalse(reader.extract_engine_particles(changed,arrival,damage),index)

    def test_missing_context_and_unknown_architecture(self):
        mach,arrival,damage,layouts=fixture()
        with patch.object(reader,'LAYOUTS',layouts):
            for key in ['anchor','anchor_size','scope','defaults','architecture']:
                m=copy.copy(mach);a=copy.deepcopy(arrival);d=copy.deepcopy(damage)
                if key=='anchor':a['provenance']['actor']['offset']+=1
                elif key=='anchor_size':a['provenance']['actor']['bytes']=314
                elif key=='scope':d['scope']='unknown'
                elif key=='defaults':d.pop('emitter_defaults')
                else:m.architecture='unknown'
                self.assertFalse(reader.extract_engine_particles(m,a,d),key)
