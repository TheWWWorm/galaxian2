"""Mac handoff reader boundaries, relocated independently of the source fixture."""
import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import opening_handoff as reader


def fixture(rows,shift=0):
    constants=[k for k,v in rows.items() if v[0]=='__const']
    mach,origin,offset,low=literal_fixture('x86_64',{k:v[1:] for k,v in rows.items()},shift,constants)
    arrival={'campaign_cursor':1,'actor_kind':3,'provenance':{'actor':{'offset':origin,'bytes':315}}}
    actors={'npc_initialization':{'death_accounting':{'present':True},
             'hull':{'rank':0,'base_hull':20,'provenance':{'rank_calculation':{}}}},
            'player_initialization':{'flight_cache':{'present':True}}}
    return mach,arrival,actors,{'present':True},offset,low


class OpeningHandoffTests(unittest.TestCase):
    def test_relocation_and_detached_declarations(self):
        for layout in [reader.LAYOUTS,reader.MAC_ALTERNATE]:
            for shift in [0,0x2400000]:
                m,a,n,w,*_=fixture(layout,shift)
                result=reader.extract_opening_handoff(m,a,n,w)
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                for key,span in result['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],a['provenance']['actor']['offset']+layout[key][1])
                result['rank_thresholds'].clear()
                self.assertEqual(len(reader.extract_opening_handoff(m,a,n,w)['rank_thresholds']),21)

    def test_source_edges_and_missing_sections(self):
        for layout in [reader.LAYOUTS,reader.MAC_ALTERNATE]:
            m,a,n,w,offset,low=fixture(layout)
            for key,(_,delta,size,_) in layout.items():
                for edge in [0,size-1]:
                    bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low+edge]^=128;bad.data=bytes(raw)
                    self.assertEqual(reader.extract_opening_handoff(bad,a,n,w),{},(key,edge))
            m.sections=[s for s in m.sections if s['name']!=b'__const']
            self.assertEqual(reader.extract_opening_handoff(m,a,n,w),{})

    def test_unsupported_or_disconnected_context(self):
        for layout in [reader.LAYOUTS,reader.MAC_ALTERNATE]:
            for scenario in ['arm','unknown','cursor','kind','anchor','extent','rank','rank_proof','deaths','cache','world','truncated']:
                m,a,n,w,*_=fixture(layout)
                if scenario in ['arm','unknown']:m.architecture='armv7' if scenario=='arm' else 'unknown'
                elif scenario=='cursor':a['campaign_cursor']=2
                elif scenario=='kind':a['actor_kind']=8
                elif scenario=='anchor':a['provenance']['actor']['offset']+=1
                elif scenario=='extent':a['provenance']['actor']['bytes']-=1
                elif scenario=='rank':n['npc_initialization']['hull']['rank']=1
                elif scenario=='rank_proof':n['npc_initialization']['hull']['provenance'].clear()
                elif scenario=='deaths':n['npc_initialization']['death_accounting'].clear()
                elif scenario=='cache':n['player_initialization']['flight_cache'].clear()
                elif scenario=='world':w.clear()
                else:m.data=m.data[:128]
                self.assertEqual(reader.extract_opening_handoff(m,a,n,w),{},scenario)
