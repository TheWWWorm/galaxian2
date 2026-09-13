"""Relocated Mac rescue world declarations and rejection at each source boundary.

Further iOS validation is deferred by the project's current development priority.
"""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import arrival_world_initialization as reader


def fixture(shift=0):
    rows=reader.LAYOUTS['x86_64']
    low=min(v[1] for v in rows.values())-32
    high=max(v[1]+v[2] for v in rows.values())+32
    offset,bias=128,4096
    base=0x800000+shift-low
    raw=bytearray(offset+high-low)
    sections=[]
    for key,(section,delta,size,pattern) in rows.items():
        raw[offset+delta-low:offset+delta-low+size]=bytes.fromhex(pattern)
        sections.append({'segment':b'__TEXT','name':section.encode(),'address':base+delta,
                         'offset':offset+delta-low,'length':size})
    text={'address':base+low,'offset':offset,'length':high-low}
    mach=SimpleNamespace(architecture='x86_64',slice_offset=bias,data=bytes(raw),text=text,sections=sections)
    arrival={'campaign_cursor':1,'actor_kind':3,'actor_hull_id':30,
             'provenance':{'actor':{'offset':bias+offset-low,'bytes':315}}}
    actors={'npc_initialization':{'world_initialization':{'weapon_item_sequence':[0,19],'weapon_effect_capacity':4}},
            'player_initialization':{'flight_cache':{'quest_kind':11}}}
    return mach,arrival,actors,{'supported':True},{'supported':True},offset,low


class ArrivalWorldInitializationTests(unittest.TestCase):
    def test_relocation_and_declarative_output(self):
        for shift in [0,0x1200000]:
            m,a,n,c,e,*_=fixture(shift)
            data=reader.extract_arrival_world_initialization(m,a,n,c,e)
            self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
            for key,span in data['provenance'].items():
                self.assertEqual(set(span),{'offset','bytes'})
                self.assertEqual(span['offset'],a['provenance']['actor']['offset']+reader.LAYOUTS['x86_64'][key][1])
            data['weapon_item_sequence'].clear()
            self.assertEqual(reader.extract_arrival_world_initialization(m,a,n,c,e)['weapon_item_sequence'],[0,25])

    def test_altered_source_and_missing_sections(self):
        m,a,n,c,e,offset,low=fixture()
        for key,(_,delta,size,_) in reader.LAYOUTS['x86_64'].items():
            for edge in [0,size-1]:
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low+edge]^=128;bad.data=bytes(raw)
                self.assertEqual(reader.extract_arrival_world_initialization(bad,a,n,c,e),{},(key,edge))
        m.sections=[s for s in m.sections if s['name']!=b'__const']
        self.assertEqual(reader.extract_arrival_world_initialization(m,a,n,c,e),{})

    def test_context_and_truncation(self):
        for name in ['cursor','hull','kind','origin','size','shared','quest','capacity','construction','environment','truncated','architecture']:
            m,a,n,c,e,*_=fixture()
            if name in ['cursor','hull','kind']:a[{'cursor':'campaign_cursor','hull':'actor_hull_id','kind':'actor_kind'}[name]]=-1
            elif name=='origin':a['provenance']['actor']['offset']+=2
            elif name=='size':a['provenance']['actor']['bytes']+=1
            elif name=='shared':n['npc_initialization'].clear()
            elif name=='quest':n['player_initialization']['flight_cache']['quest_kind']=183
            elif name=='capacity':n['npc_initialization']['world_initialization']['weapon_effect_capacity']=5
            elif name=='construction':c.clear()
            elif name=='environment':e.clear()
            elif name=='truncated':m.data=m.data[:128]
            else:m.architecture='unsupported'
            self.assertEqual(reader.extract_arrival_world_initialization(m,a,n,c,e),{},name)
