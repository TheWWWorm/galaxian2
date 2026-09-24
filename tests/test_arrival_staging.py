"""Finite source-layout acceptance and rejection, without original fixtures."""
import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import arrival_staging as reader


def variants():
    return [('x86_64',reader.LAYOUTS['x86_64']),
            ('armv7',reader.LAYOUTS['armv7']),
            ('x86_64',reader.MAC_ALTERNATE)]


def fixture(arch,rows,shift=0):
    constants=[k for k,v in rows.items() if v[0]=='__const']
    mach,origin,offset,low=literal_fixture(arch,{k:v[1:] for k,v in rows.items()},shift,constants)
    staging={'player_motion':{'present':True},'provenance':{'initial':{'offset':origin,'bytes':366 if arch=='x86_64' else 320}}}
    dialogue={'campaign_cursor':1,'events':[{}, {}, {}]}
    actors={'npc_initialization':{'present':True}}
    return mach,staging,dialogue,actors,offset,low


class ArrivalStagingTests(unittest.TestCase):
    def test_layouts_relocation_and_data_only_output(self):
        for arch,layout in variants():
            for shift in [0,0x1200000]:
                m,s,d,a,*_=fixture(arch,layout,shift); data=reader.extract_arrival_staging(m,s,d,a)
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],s['provenance']['initial']['offset']+layout[key][1])
                data['actor_route_points'][0][2]=0
                self.assertEqual(reader.VALUES['actor_route_points'][0][2],-5000)

    def test_every_changed_span_and_truncated_section(self):
        for arch,layout in variants():
            m,s,d,a,offset,low=fixture(arch,layout)
            for key,(_,delta,size,_) in layout.items():
                for index in [0,size-1]:
                    bad=copy.copy(m); raw=bytearray(m.data); raw[offset+delta-low+index]^=255; bad.data=bytes(raw)
                    self.assertEqual(reader.extract_arrival_staging(bad,s,d,a),{},(arch,key,index))
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_arrival_staging(m,s,d,a))

    def test_parent_capabilities_and_section_boundaries(self):
        for arch,layout in variants():
            for key in ['motion','npc','cursor','events','origin','size','section','arch']:
                m,s,d,a,*_=fixture(arch,layout)
                if key=='motion':s['player_motion']={}
                elif key=='npc':a['npc_initialization']={}
                elif key=='cursor':d['campaign_cursor']=0
                elif key=='events':d['events'].append({})
                elif key=='origin':s['provenance']['initial']['offset']+=2
                elif key=='size':s['provenance']['initial']['bytes']+=1
                elif key=='section':m.sections[0]['segment']=b'__DATA'
                else:m.architecture='unsupported'
                self.assertEqual(reader.extract_arrival_staging(m,s,d,a),{},(arch,key))
