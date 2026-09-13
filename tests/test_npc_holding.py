"""Holding-mode recognition, linked predicates and relocation without originals."""
import copy
import struct
import unittest
from gof2_content import npc_holding as reader
from test_opening_npc_guidance import fixture as base_fixture
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac,shift=0):
    m,actors,_,_,offset=base_fixture(mac,shift);data=bytearray(m.data)
    origin=m.text['address'];positions={};bases={'constructor':4000,'update':20000,'world':30000,'activation':36000}
    def extent(at,n):return {'offset':m.slice_offset+offset+at,'bytes':n}
    def write(at,raw):data[offset+at:offset+at+len(raw)]=raw
    def linked(at,pattern,field,destination):
        raw,fields=expand(pattern);p,n=fields[field]
        raw[p:p+n]=struct.pack('<i',destination-at-p-n) if mac else branch(origin+at+p,origin+destination)
        write(at,raw)
    for key,(base,delta,_,pattern) in reader.LAYOUTS[m.architecture].items():
        at=bases[base]+delta;positions[key]=at
        if key=='range':linked(at,pattern,'getter',35500)
        else:write(at,expand(pattern)[0])
    pattern=('554889e553504889fbc783bc00000005000000488b7b0831f6e8 {setter:4}' if mac else
             '90b504460520c4f884000021606801af {setter:4} 012084f8ad0090bd')
    linked(3500,pattern,'setter',35000);positions['deactivation']=3500
    opening_size=413 if mac else 356
    positions['player_suppression']=43000+opening_size-(19 if mac else 22)
    write(positions['player_suppression'],bytes.fromhex('498b8768010000488b00c6406201' if mac else '1498012100684466d5f8f000006880f85e10'))
    actors['provenance']={'declaration':extent(43000,opening_size)}
    initial=actors['npc_initialization'];initial.update({'guidance':{'available':True},'activation':{'provenance':{'activation':extent(36000,33 if mac else 20)}},'initial_active':False})
    initial['provenance'].update({'opening_deactivation':extent(3500,30 if mac else 28),'activity_setter':extent(35000,13 if mac else 6)})
    projection={'provenance':{'predicate':extent(35500,26 if mac else 10)}}
    m.data=bytes(data)
    return m,actors,projection,positions,offset


class HoldingTests(unittest.TestCase):
    def test_both_relocated_layouts(self):
        for mac in [False,True]:
            for shift in [0,0x600000]:
                m,a,p,_,_=fixture(mac,shift);result=reader.extract_npc_holding(m,a,p)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),8)

    def test_corruption_and_missing_dependencies(self):
        for mac in [False,True]:
            m,a,p,positions,offset=fixture(mac)
            for key,at in positions.items():
                altered=copy.copy(m);data=bytearray(m.data);data[offset+at]^=255;altered.data=bytes(data)
                self.assertFalse(reader.extract_npc_holding(altered,a,p),(mac,key))
            for key in ['flight','guidance','activation']:
                changed=copy.deepcopy(a);changed['npc_initialization'][key]={}
                self.assertFalse(reader.extract_npc_holding(m,changed,p),(mac,key))
            for key in ['actor_kind','hull_catalogue_id']:
                changed=copy.deepcopy(a);changed['actors'][1][key]=99
                self.assertFalse(reader.extract_npc_holding(m,changed,p))
            changed=copy.deepcopy(p);changed['provenance']['predicate']['offset']+=4
            self.assertFalse(reader.extract_npc_holding(m,a,changed))
            changed=copy.deepcopy(a);changed['npc_initialization']['provenance']['activity_setter']['offset']+=4
            self.assertFalse(reader.extract_npc_holding(m,changed,p))

    def test_unique_section_bounded_evidence(self):
        for mac in [False,True]:
            m,a,p,positions,offset=fixture(mac)
            changed=copy.copy(m);data=bytearray(m.data);n=reader.LAYOUTS[m.architecture]['world_order'][2]
            at=positions['world_order'];data[offset+31000:offset+31000+n]=data[offset+at:offset+at+n];changed.data=bytes(data)
            self.assertFalse(reader.extract_npc_holding(changed,a,p))
            changed=copy.deepcopy(m);changed.sections[-1]['segment']=b'__TEXT'
            self.assertFalse(reader.extract_npc_holding(changed,a,p))
            changed=copy.copy(m);changed.data=m.data[:offset+51002]
            self.assertFalse(reader.extract_npc_holding(changed,a,p))
            changed=copy.copy(m);changed.architecture='unknown'
            self.assertFalse(reader.extract_npc_holding(changed,a,p))


if __name__=='__main__':unittest.main()
