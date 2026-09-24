import copy
import struct
import unittest
from declaration_fixture import literal_fixture
from gof2_content import damage_particle_owners as reader


def variants():
    return [('x86_64', reader.LAYOUTS['x86_64']),
            ('armv7', reader.LAYOUTS['armv7']),
            ('x86_64', reader.MAC_ALTERNATE)]


def fixture(arch,rows,shift=0):
    layout=copy.deepcopy(rows)
    layout['hull_fraction']=[rows['hull_fraction'][0],4,struct.pack('<f',0.33).hex()]
    mach,origin,offset,low=literal_fixture(arch,layout,shift,['hull_fraction'] if arch=='x86_64' else [])
    actors={'npc_initialization':{'provenance':{'factory_entry':{'offset':origin,'bytes':4}},
            'world_initialization':{'campaign_cursor':0},'hull':{'available':True},'flight':{'available':True},'destruction':{'available':True}},'actors':[{}, {}, {}]}
    return mach,actors,{'escape':{'available':True}},offset,low


class DamageParticleOwnerTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only(self):
        for arch,layout in variants():
            for shift in [0,0x700000]:
                m,a,s,*_=fixture(arch,layout,shift);data=reader.extract_damage_particle_owners(m,a,s)
                self.assertAlmostEqual(data['npc_hull_fraction'],0.33)
                self.assertEqual(data['npc_uses_detail_gate'],arch=='x86_64')
                self.assertEqual((data['npc_suppressed_mode'],data['active_mode'],data['player_max_campaign_cursor']),(9,1,1))
                self.assertIs(data['initially_damaged'],False)
                self.assertEqual(len(data['provenance']),16)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],a['npc_initialization']['provenance']['factory_entry']['offset']+layout[key][0])

    def test_every_instruction_context_and_truncation(self):
        for arch,layout in variants():
            m,a,s,offset,low=fixture(arch,layout)
            for key,(delta,_,_) in layout.items():
                if key=='hull_fraction':continue
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_damage_particle_owners(bad,a,s),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_damage_particle_owners(m,a,s))

    def test_fraction_is_read_and_invalid_numbers_rejected(self):
        for arch,layout in variants():
            m,a,s,offset,low=fixture(arch,layout)
            at=offset+layout['hull_fraction'][0]-low
            for value in [0.25,0,-1,1,float('inf'),float('nan')]:
                raw=bytearray(m.data);struct.pack_into('<f',raw,at,value);m.data=bytes(raw)
                data=reader.extract_damage_particle_owners(m,a,s)
                if value==0.25:self.assertEqual(data['npc_hull_fraction'],0.25)
                else:self.assertFalse(data)

    def test_context_and_section_boundaries(self):
        for arch,layout in variants():
            for key in ['world','hull','flight','destruction','cursor','population','origin','size','section','arch','escape']:
                m,a,s,*_=fixture(arch,layout);npc=a['npc_initialization']
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
