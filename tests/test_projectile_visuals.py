import copy
import unittest
from types import SimpleNamespace
from gof2_content import projectile_visuals as reader


def fixture(arch, shift=0):
    rows=reader.LAYOUTS[arch]
    low=min(v[0] for v in rows.values())-32
    high=max(v[0]+v[1] for v in rows.values())+32
    offset=128;bias=4096;base=0x400000+shift-low
    data=bytearray(offset+high-low)
    groups={b'__text':[],b'__const':[]}
    for key,(relative,size,raw) in rows.items():
        data[offset+relative-low:offset+relative-low+size]=bytes.fromhex(raw)
        name=b'__const' if key in ['model_2','model_19'] or arch=='x86_64' and key.endswith('_constant') else b'__text'
        groups[name].append((relative,size))
    sections=[]
    for name,spans in groups.items():
        lo=min(v[0] for v in spans)-16;hi=max(v[0]+v[1] for v in spans)+16
        sections.append({'segment':b'__TEXT','name':name,'address':base+lo,'offset':offset+lo-low,'length':hi-lo})
    mach=SimpleNamespace(architecture=arch,slice_offset=bias,data=bytes(data),text=sections[0],sections=sections)
    staging={'provenance':{'initial':{'offset':bias+offset-low}},'player_flight':{'verified':True}}
    actors={'npc_initialization':{'primary_weapon':{'item_id':19}}}
    return mach,staging,actors,{'ship_id':10},offset,low


class ProjectileVisualTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only_output(self):
        for arch in reader.LAYOUTS:
            for shift in [0,0x700000]:
                args=fixture(arch,shift);data=reader.extract_projectile_visuals(*args[:4])
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],args[1]['provenance']['initial']['offset']+reader.LAYOUTS[arch][key][0])

    def test_every_changed_span_and_truncation(self):
        for arch in reader.LAYOUTS:
            m,s,a,o,offset,low=fixture(arch)
            for key,(delta,_,_) in reader.LAYOUTS[arch].items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_projectile_visuals(bad,s,a,o),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_projectile_visuals(m,s,a,o))

    def test_scope_and_section_boundaries(self):
        for arch in reader.LAYOUTS:
            for key in ['player','npc','ship','origin','section','arch']:
                m,s,a,o,*_=fixture(arch)
                if key=='player':s['player_flight']={}
                elif key=='npc':a['npc_initialization']['primary_weapon']['item_id']=18
                elif key=='ship':o['ship_id']=9
                elif key=='origin':s['provenance']['initial']['offset']+=2
                elif key=='section':m.sections[1]['segment']=b'__DATA'
                else:m.architecture='unsupported'
                self.assertFalse(reader.extract_projectile_visuals(m,s,a,o),key)
