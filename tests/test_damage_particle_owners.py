import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import damage_particle_owners as reader


def fixture(arch,shift=0):
    rows=reader.LAYOUTS[arch]
    low=min(v[0] for v in rows.values())-32
    high=max(v[0]+v[1] for v in rows.values())+32
    offset=128;bias=4096;base=0x400000+shift-low
    data=bytearray(offset+high-low);groups={b'__text':[],b'__const':[]}
    for key,(delta,size,raw) in rows.items():
        value=struct.pack('<f',0.33) if key=='hull_fraction' else bytes.fromhex(raw)
        data[offset+delta-low:offset+delta-low+size]=value
        groups[b'__const' if arch=='x86_64' and key=='hull_fraction' else b'__text'].append((delta,size))
    sections=[]
    for name,spans in groups.items():
        if not spans:continue
        lo=min(v[0] for v in spans)-16;hi=max(v[0]+v[1] for v in spans)+16
        sections.append({'segment':b'__TEXT','name':name,'address':base+lo,'offset':offset+lo-low,'length':hi-lo})
    mach=SimpleNamespace(architecture=arch,slice_offset=bias,data=bytes(data),text=sections[0],sections=sections)
    actors={'npc_initialization':{'provenance':{'factory_entry':{'offset':bias+offset-low,'bytes':4}},
            'world_initialization':{'campaign_cursor':0},'hull':{'available':True},'flight':{'available':True},'destruction':{'available':True}},'actors':[{}, {}, {}]}
    return mach,actors,{'escape':{'available':True}},offset,low


class DamageParticleOwnerTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only(self):
        for arch in reader.LAYOUTS:
            for shift in [0,0x700000]:
                m,a,s,*_=fixture(arch,shift);data=reader.extract_damage_particle_owners(m,a,s)
                self.assertAlmostEqual(data['npc_hull_fraction'],0.33)
                self.assertEqual(data['npc_uses_detail_gate'],arch=='x86_64')
                self.assertEqual((data['npc_suppressed_mode'],data['active_mode'],data['player_max_campaign_cursor']),(9,1,1))
                self.assertIs(data['initially_damaged'],False)
                self.assertEqual(len(data['provenance']),16)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],a['npc_initialization']['provenance']['factory_entry']['offset']+reader.LAYOUTS[arch][key][0])

    def test_every_instruction_context_and_truncation(self):
        for arch in reader.LAYOUTS:
            m,a,s,offset,low=fixture(arch)
            for key,(delta,_,_) in reader.LAYOUTS[arch].items():
                if key=='hull_fraction':continue
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_damage_particle_owners(bad,a,s),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_damage_particle_owners(m,a,s))

    def test_fraction_is_read_and_invalid_numbers_rejected(self):
        for arch in reader.LAYOUTS:
            m,a,s,offset,low=fixture(arch)
            at=offset+reader.LAYOUTS[arch]['hull_fraction'][0]-low
            for value in [0.25,0,-1,1,float('inf'),float('nan')]:
                raw=bytearray(m.data);struct.pack_into('<f',raw,at,value);m.data=bytes(raw)
                data=reader.extract_damage_particle_owners(m,a,s)
                if value==0.25:self.assertEqual(data['npc_hull_fraction'],0.25)
                else:self.assertFalse(data)

    def test_context_and_section_boundaries(self):
        for arch in reader.LAYOUTS:
            for key in ['world','hull','flight','destruction','cursor','population','origin','size','section','arch','escape']:
                m,a,s,*_=fixture(arch);npc=a['npc_initialization']
                if key=='world':npc['world_initialization']={}
                elif key in ['hull','flight','destruction']:npc[key]={}
                elif key=='cursor':npc['world_initialization']['campaign_cursor']=1
                elif key=='population':a['actors'].pop()
                elif key=='origin':npc['provenance']['factory_entry']['offset']+=2
                elif key=='size':npc['provenance']['factory_entry']['bytes']=8
                elif key=='section':m.sections[-1]['segment']=b'__DATA'
                elif key=='escape':s['escape']={}
                else:m.architecture='unsupported'
                self.assertFalse(reader.extract_damage_particle_owners(m,a,s),key)
