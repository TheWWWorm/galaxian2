import copy
import unittest
from types import SimpleNamespace
from gof2_content import npc_hull as reader


def layouts():
    return [*reader.LAYOUTS.items(), ('x86_64', reader.MAC_ALTERNATE)]


def fixture(arch, shift=0, rows=None):
    rows=reader.LAYOUTS[arch] if rows is None else rows
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
    actors={'npc_initialization':{'provenance':{'factory_entry':{'offset':bias+offset-low,'bytes':4}},'world_initialization':{'campaign_cursor':0}},
            'actors':[{'hull_catalogue_id':v} for v in [2,23,2]]}
    actors['provenance']={key:{'offset':bias+offset-low+rows[key][0],'bytes':rows[key][1]} for key in ['hull_setter','cursor_getter']}
    return mach,actors,offset,low


class NpcHullTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only_output(self):
        for arch,rows in layouts():
            for shift in [0,0x700000]:
                m,a,*_=fixture(arch,shift,rows);data=reader.extract_npc_hull(m,a)
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],a['npc_initialization']['provenance']['factory_entry']['offset']+rows[key][0])

    def test_every_changed_span_and_truncation(self):
        for arch,rows in layouts():
            m,a,offset,low=fixture(arch,rows=rows)
            for key,(delta,_,_) in rows.items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_npc_hull(bad,a),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_npc_hull(m,a))

    def test_fresh_context_and_section_boundaries(self):
        for arch,rows in layouts():
            for key in ['world','cursor','population','hull','origin','size','section','arch','hull_setter','cursor_getter']:
                m,a,*_=fixture(arch,rows=rows);npc=a['npc_initialization']
                if key=='world':npc['world_initialization']={}
                elif key=='cursor':npc['world_initialization']['campaign_cursor']=1
                elif key=='population':a['actors'].pop()
                elif key=='hull':a['actors'][1]['hull_catalogue_id']=44
                elif key=='origin':npc['provenance']['factory_entry']['offset']+=2
                elif key=='size':npc['provenance']['factory_entry']['bytes']=8
                elif key=='section':m.sections[-1]['segment']=b'__DATA'
                elif key in ['hull_setter','cursor_getter']:a['provenance'][key]['offset']+=2
                else:m.architecture='unsupported'
                self.assertFalse(reader.extract_npc_hull(m,a),key)
