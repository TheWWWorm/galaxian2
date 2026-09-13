"""Relocation, source changes and dependency boundaries for Mac rescue entry."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import arrival_session as reader


def fixture(shift=0):
    low=min(v[0] for v in reader.LAYOUTS.values())-32
    high=max(v[0]+v[1] for v in reader.LAYOUTS.values())+32
    offset,bias=128,8192
    base=0x10000000+shift-low
    raw=bytearray(offset+high-low)
    for delta,size,pattern in reader.LAYOUTS.values():
        raw[offset+delta-low:offset+delta-low+size]=bytes.fromhex(pattern)
    text={'segment':b'__TEXT','name':b'__text','address':base+low,'offset':offset,'length':high-low}
    mach=SimpleNamespace(architecture='x86_64',slice_offset=bias,data=bytes(raw),text=text,sections=[text])
    arrival={'campaign_cursor':1,'actor_kind':3,'player_update_enabled':False,
             'provenance':{'actor':{'offset':bias+offset-low,'bytes':315}}}
    return mach,arrival,offset,low


class ArrivalSessionTests(unittest.TestCase):
    def test_relocation_and_detachment(self):
        for shift in [0,0x2400000]:
            m,a,*_=fixture(shift)
            result=reader.extract_arrival_session(m,a,{'present':1},{'present':1},{'present':1})
            self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
            for key,span in result['provenance'].items():
                self.assertEqual(set(span),{'offset','bytes'})
                self.assertEqual(span['offset'],a['provenance']['actor']['offset']+reader.LAYOUTS[key][0])
            result['actor_target_ids'].clear()
            self.assertEqual(reader.extract_arrival_session(m,a,{'present':1},{'present':1},{'present':1})['actor_target_ids'],['player'])

    def test_changed_clock_or_target_source_rejected(self):
        m,a,offset,low=fixture()
        for key,(delta,size,_) in reader.LAYOUTS.items():
            for edge in [0,size-1]:
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low+edge]^=128;bad.data=bytes(raw)
                self.assertEqual(reader.extract_arrival_session(bad,a,{'present':1},{'present':1},{'present':1}),{},(key,edge))

    def test_unavailable_dependencies_or_wrong_scene(self):
        for case in ['architecture','cursor','freeze','extent','motion','world','handoff','truncated']:
            m,a,*_=fixture();motion={'present':1};world={'present':1};handoff={'present':1}
            if case=='architecture':m.architecture='unsupported'
            elif case=='cursor':a['campaign_cursor']=2
            elif case=='freeze':a['player_update_enabled']=True
            elif case=='extent':a['provenance']['actor']['offset']+=1
            elif case=='motion':motion.clear()
            elif case=='world':world.clear()
            elif case=='handoff':handoff.clear()
            else:m.data=m.data[:128]
            self.assertEqual(reader.extract_arrival_session(m,a,motion,world,handoff),{},case)
