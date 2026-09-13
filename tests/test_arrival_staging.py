"""Finite source-layout acceptance and rejection, without original fixtures."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import arrival_staging as reader


def fixture(arch, shift=0):
    rows=reader.LAYOUTS[arch]
    low=min(v[1] for v in rows.values())-32
    high=max(v[1]+v[2] for v in rows.values())+32
    offset=128; bias=4096; base=0x800000+shift-low
    data=bytearray(offset+high-low); groups={b'__text':[],b'__const':[]}
    for section,delta,size,raw in rows.values():
        data[offset+delta-low:offset+delta-low+size]=bytes.fromhex(raw)
        groups[section.encode()].append((delta,size))
    sections=[]
    for name,spans in groups.items():
        lo=min(v[0] for v in spans)-16; hi=max(v[0]+v[1] for v in spans)+16
        sections.append({'segment':b'__TEXT','name':name,'address':base+lo,'offset':offset+lo-low,'length':hi-lo})
    mach=SimpleNamespace(architecture=arch,slice_offset=bias,data=bytes(data),text=sections[0],sections=sections)
    staging={'player_motion':{'present':True},'provenance':{'initial':{'offset':bias+offset-low,'bytes':366 if arch=='x86_64' else 320}}}
    dialogue={'campaign_cursor':1,'events':[{}, {}, {}]}
    actors={'npc_initialization':{'present':True}}
    return mach,staging,dialogue,actors,offset,low


class ArrivalStagingTests(unittest.TestCase):
    def test_layouts_relocation_and_data_only_output(self):
        for arch in reader.LAYOUTS:
            for shift in [0,0x1200000]:
                m,s,d,a,*_=fixture(arch,shift); data=reader.extract_arrival_staging(m,s,d,a)
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],s['provenance']['initial']['offset']+reader.LAYOUTS[arch][key][1])
                data['actor_route_points'][0][2]=0
                self.assertEqual(reader.VALUES['actor_route_points'][0][2],-5000)

    def test_every_changed_span_and_truncated_section(self):
        for arch in reader.LAYOUTS:
            m,s,d,a,offset,low=fixture(arch)
            for key,(_,delta,size,_) in reader.LAYOUTS[arch].items():
                for index in [0,size-1]:
                    bad=copy.copy(m); raw=bytearray(m.data); raw[offset+delta-low+index]^=255; bad.data=bytes(raw)
                    self.assertEqual(reader.extract_arrival_staging(bad,s,d,a),{},(arch,key,index))
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_arrival_staging(m,s,d,a))

    def test_parent_capabilities_and_section_boundaries(self):
        for arch in reader.LAYOUTS:
            for key in ['motion','npc','cursor','events','origin','size','section','arch']:
                m,s,d,a,*_=fixture(arch)
                if key=='motion':s['player_motion']={}
                elif key=='npc':a['npc_initialization']={}
                elif key=='cursor':d['campaign_cursor']=0
                elif key=='events':d['events'].append({})
                elif key=='origin':s['provenance']['initial']['offset']+=2
                elif key=='size':s['provenance']['initial']['bytes']+=1
                elif key=='section':m.sections[0]['segment']=b'__DATA'
                else:m.architecture='unsupported'
                self.assertEqual(reader.extract_arrival_staging(m,s,d,a),{},(arch,key))
