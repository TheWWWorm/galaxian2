"""Weapon sound tables retain source values and independent owner identities."""
import copy
import struct
import unittest
from declaration_fixture import literal_fixture
from gof2_content import weapon_audio as reader


def variants():
    return [('x86_64', reader.LAYOUTS['x86_64'], 1464783),
            ('armv7', reader.LAYOUTS['armv7'], 2351530),
            ('x86_64', reader.MAC_ALTERNATE, 1439847)]


def fixture(arch, layouts, table_delta, shift=0):
    rows=copy.deepcopy(layouts)
    ids=[-1 if index%5==0 else index for index in range(233)]
    rows['player_table']=[table_delta,932,struct.pack('<233i',*ids).hex()]
    constants=['player_table']
    if arch=='armv7':
        rows['npc_table']=[2352474,44,struct.pack('<11i',*reader.NPC_EVENTS).hex()]
        constants.append('npc_table')
    mach,origin,_,_=literal_fixture(arch,rows,shift,constants)
    def span(key):return {'offset':origin+layouts[key][0],'bytes':layouts[key][1]}
    construction={'price_low_index':15,'price_high_index':17,
                  'provenance':{'item_layout':span('price_layout'),'price':span('price_getter')}}
    actors={'npc_initialization':{'construction':construction,'world_initialization':{'world_type':3}}}
    staging={'player_flight':{'present':True},'provenance':{'initial':{'offset':origin}}}
    weapons={'provenance':{'interval_getter':span('interval_getter')}}
    return mach,weapons,actors,staging,ids,origin


class WeaponAudioTests(unittest.TestCase):
    def test_relocated_profiles_import_their_tables(self):
        for arch,layout,delta in variants():
            for shift in [0,0x700000]:
                args=fixture(arch,layout,delta,shift)
                value=reader.extract_weapon_audio(*args[:4])
                self.assertEqual(value['player_event_ids'],args[4])
                self.assertEqual(value['npc_event_ids'],reader.NPC_EVENTS)
                self.assertEqual({k:value[k] for k in reader.VALUES},reader.VALUES)
                for row in value['provenance'].values():self.assertEqual(set(row),{'offset','bytes'})
                changed=copy.copy(args[0]);data=bytearray(changed.data)
                struct.pack_into('<i',data,args[5]+delta-changed.slice_offset+8,19999)
                changed.data=bytes(data)
                self.assertEqual(reader.extract_weapon_audio(changed,*args[1:4])['player_event_ids'][2],19999)

    def test_every_damaged_proof_and_invalid_table(self):
        for arch,layout,delta in variants():
            mach,weapons,actors,staging,_,origin=fixture(arch,layout,delta)
            for key,(relative,size,_) in layout.items():
                for endpoint in [0,size-1]:
                    bad=copy.copy(mach);data=bytearray(mach.data)
                    data[origin+relative+endpoint-mach.slice_offset]^=255;bad.data=bytes(data)
                    self.assertFalse(reader.extract_weapon_audio(bad,weapons,actors,staging),(arch,key,endpoint))
            for invalid in [-2,20000]:
                bad=copy.copy(mach);data=bytearray(mach.data)
                struct.pack_into('<i',data,origin+delta-mach.slice_offset,invalid);bad.data=bytes(data)
                self.assertFalse(reader.extract_weapon_audio(bad,weapons,actors,staging))
            bad=copy.copy(mach);bad.data=mach.data[:origin+delta-mach.slice_offset+931]
            self.assertFalse(reader.extract_weapon_audio(bad,weapons,actors,staging))

    def test_independent_owners_and_section_boundaries(self):
        for arch,layout,delta in variants():
            args=fixture(arch,layout,delta)
            for field in ['item_layout','price','interval_getter','world','flight','origin','section']:
                mach,weapons,actors,staging=copy.deepcopy(args[:4])
                if field in ['item_layout','price']:
                    actors['npc_initialization']['construction']['provenance'][field]['offset']+=2
                elif field=='interval_getter':weapons['provenance'][field]['offset']+=2
                elif field=='world':actors['npc_initialization']['world_initialization']['world_type']=2
                elif field=='flight':staging['player_flight']={}
                elif field=='origin':staging['provenance']['initial']['offset']+=2
                else:mach.sections[-1]['segment']=b'__DATA'
                self.assertFalse(reader.extract_weapon_audio(mach,weapons,actors,staging),(arch,field))
