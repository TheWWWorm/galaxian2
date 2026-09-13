"""Synthetic declaration relocation and rejected fresh-hostility source changes."""
import copy
import struct
import unittest
from gof2_content import npc_hostility as reader
from test_opening_npc_guidance import fixture as base_fixture
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac,shift=0):
    m,actors,_,_,offset=base_fixture(mac,shift);data=bytearray(m.data)
    origin=m.text['address'];bases={'stats':32000,'base':35000,'fresh':38000,'update':20000}
    positions={};fields_by_block={}
    def extent(at,n):return {'offset':m.slice_offset+offset+at,'bytes':n}
    def write(at,raw):data[offset+at:offset+at+len(raw)]=raw
    for key,(base,delta,size,pattern) in reader.LAYOUTS[m.architecture].items():
        at=bases[base]+delta;positions[key]=at
        raw,fields=expand(pattern);fields_by_block[key]=fields
        if key=='overrides':
            for i,(name,(field,code)) in enumerate(reader.GETTERS[m.architecture].items()):
                target=40000+i*100;p,n=fields[field];positions[name]=target
                raw[p:p+n]=struct.pack('<i',target-at-p-n) if mac else branch(origin+at+p,origin+target)
                write(target,bytes.fromhex(code))
            if mac:
                for field in ['ref_0','ref_13']:
                    p,n=fields[field];raw[p:p+n]=struct.pack('<i',44000-at-p-n)
            else:
                for field,code in [('ref_0','46f6fc60'),('ref_8','c0f22100')]:
                    p,n=fields[field];raw[p:p+n]=bytes.fromhex(code)
        elif key=='base_flags' and not mac:
            p,n=fields['ref_6'];raw[p:p+n]=bytes.fromhex('c0f22401')
        write(at,raw)
    initial=actors['npc_initialization']
    initial['provenance'].update({'stats_entry':extent(bases['stats'],20 if mac else 28),
        'point_geometry':extent(bases['base']+(0x21e if mac else 0x1a6),4 if mac else 26)})
    initial['primary_weapon']['provenance']['fresh_level']=extent(bases['fresh'],11 if mac else 42)
    initial['guidance']={'provenance':{'virtual_update':copy.deepcopy(initial['flight']['provenance']['virtual_update'])}}
    initial['holding']={'available':True};initial['activation']={'available':True}
    m.data=bytes(data)
    return m,actors,positions,fields_by_block,offset


class HostilityTests(unittest.TestCase):
    def test_both_relocated_declarations(self):
        for mac in [False,True]:
            for shift in [0,0x600000]:
                m,a,_,_,_=fixture(mac,shift);result=reader.extract_npc_hostility(m,a)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),8)

    def test_reject_changed_flags_branches_getters_and_anchors(self):
        for mac in [False,True]:
            m,a,positions,fields,offset=fixture(mac)
            for key,at in positions.items():
                changed=copy.copy(m);raw=bytearray(m.data);raw[offset+at]^=255;changed.data=bytes(raw)
                self.assertFalse(reader.extract_npc_hostility(changed,a),(mac,key))
            for key in ['flight','guidance','holding','activation','primary_weapon']:
                changed=copy.deepcopy(a);changed['npc_initialization'][key]={}
                self.assertFalse(reader.extract_npc_hostility(m,changed),(mac,key))
            for key in ['stats_entry','point_geometry']:
                changed=copy.deepcopy(a);changed['npc_initialization']['provenance'][key]['offset']+=2
                self.assertFalse(reader.extract_npc_hostility(m,changed),(mac,key))
            changed=copy.deepcopy(a);changed['actors'][1]['actor_kind']=9
            self.assertFalse(reader.extract_npc_hostility(m,changed))
            for field in (['ref_13','call_41','call_5e'] if mac else ['ref_8','call_48','call_64']):
                changed=copy.copy(m);raw=bytearray(m.data)
                raw[offset+positions['overrides']+fields['overrides'][field][0]]^=255;changed.data=bytes(raw)
                self.assertFalse(reader.extract_npc_hostility(changed,a),(mac,field))

    def test_reject_truncation_and_wrong_virtual_section(self):
        for mac in [False,True]:
            m,a,_,_,offset=fixture(mac)
            changed=copy.copy(m);changed.data=m.data[:offset+51002]
            self.assertFalse(reader.extract_npc_hostility(changed,a))
            changed=copy.deepcopy(m);changed.sections[-1]['segment']=b'__TEXT'
            self.assertFalse(reader.extract_npc_hostility(changed,a))
