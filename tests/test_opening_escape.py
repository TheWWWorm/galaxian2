import copy
import unittest
from types import SimpleNamespace
from gof2_content import opening_escape as reader


def fixture(arch, shift=0):
    rows=reader.LAYOUTS[arch]
    low=min(v[0] for v in rows.values())-32
    high=max(v[0]+v[1] for v in rows.values())+32
    offset=128;bias=4096;base=0x400000+shift-low
    data=bytearray(offset+high-low);groups={b'__text':[],b'__const':[]}
    for key,(delta,size,raw) in rows.items():
        data[offset+delta-low:offset+delta-low+size]=bytes.fromhex(raw)
        groups[b'__const' if key.endswith('_constant') else b'__text'].append((delta,size))
    sections=[]
    for name,spans in groups.items():
        if not spans:continue
        lo=min(v[0] for v in spans)-16;hi=max(v[0]+v[1] for v in spans)+16
        sections.append({'segment':b'__TEXT','name':name,'address':base+lo,'offset':offset+lo-low,'length':hi-lo})
    mach=SimpleNamespace(architecture=arch,slice_offset=bias,data=bytes(data),text=sections[0],sections=sections)
    staging={'player_flight':{'present':True},'player_motion':{'present':True},'provenance':{'initial':{'offset':bias+offset-low,'bytes':366 if arch=='x86_64' else 320}}}
    actors={}
    return mach,staging,actors,offset,low


class OpeningEscapeTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only_output(self):
        for arch in reader.LAYOUTS:
            for shift in [0,0x700000]:
                m,s,a,*_=fixture(arch,shift);data=reader.extract_opening_escape(m,s)
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],s['provenance']['initial']['offset']+reader.LAYOUTS[arch][key][0])

    def test_every_changed_span_and_truncation(self):
        for arch in reader.LAYOUTS:
            m,s,a,offset,low=fixture(arch)
            for key,(delta,_,_) in reader.LAYOUTS[arch].items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_opening_escape(bad,s),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_opening_escape(m,s))

    def test_parent_capabilities_and_section_boundaries(self):
        for arch in reader.LAYOUTS:
            for key in ['player_flight','player_motion','origin','size','section','arch']:
                m,s,a,*_=fixture(arch)
                if key in ['player_flight','player_motion']:s[key]={}
                elif key=='origin':s['provenance']['initial']['offset']+=2
                elif key=='size':s['provenance']['initial']['bytes']+=1
                elif key=='section':m.sections[0]['segment']=b'__DATA'
                else:m.architecture='unsupported'
                self.assertFalse(reader.extract_opening_escape(m,s),key)
