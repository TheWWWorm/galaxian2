"""Synthetic, relocated player recharge declarations without proprietary fixtures."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import player_recharge as reader
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac,shift=0):
    origin=0x200000+shift;offset=256;bias=4096
    arch='x86_64' if mac else 'armv7';data=bytearray(61500)
    ctor=10000-(0x92e if mac else 0x51a)
    positions={'pulse':10000,'recharge':30000,'application_order':40000,'world_pass':44000,
        'assignment':45000,'equipment_zero':45200,'getter':47000,'hull_getter':47100,
        'adder':47200,'clock_zero':ctor+(0x302 if mac else 0x152),
        'blocked_zero':ctor+(0x298 if mac else 0x12a)}
    if not mac:positions.update(zero_vector=ctor+0x1c,zero_integer=ctor+0x2c,divisor_load=ctor+0x35e)
    fields={}
    def write(at,raw):data[offset+at:offset+at+len(raw)]=raw
    def extent(at,size):return {'offset':bias+offset+at,'bytes':size}
    targets={'pulse':{'call_c':50200,('call_4' if mac else 'call_6'):50400,'call_18':50400,('call_20' if mac else 'call_1e'):47000},
        'recharge':{'call_a':50400,('call_12' if mac else 'call_10'):47000,'call_1e':47100,('call_59' if mac else 'call_6a'):47200},
        'assignment':{('call_11' if mac else 'call_8'):50000},
        'application_order':{('call_5b' if mac else 'call_50'):30000-(0x234a if mac else 0x1d00),('call_7e' if mac else 'call_74'):44000}}
    divisor=60000 if mac else ((positions['divisor_load']+4)&~3)+0x2d8
    for key,(size,pattern) in reader.LAYOUTS[arch].items():
        at=positions[key];raw,masks=expand(pattern);fields[key]=masks
        for field,destination in targets.get(key,{}).items():
            p,n=masks[field];raw[p:p+n]=struct.pack('<i',destination-at-p-n) if mac else branch(origin+at+p,origin+destination)
        if key=='pulse' and mac:
            p,n=masks['ref_2c'];raw[p:p+n]=struct.pack('<i',divisor-at-p-n)
        if key=='divisor_load':raw[:]=bytes.fromhex('9fedb6aa')
        write(at,raw)
    write(divisor,struct.pack('<f',100.0));positions['divisor']=divisor
    text={'segment':b'__TEXT','name':b'__text','address':origin,'offset':offset,'length':59000}
    const={'segment':b'__TEXT','name':b'__const','address':origin+60000,'offset':offset+60000,'length':1000}
    m=SimpleNamespace(architecture=arch,data=bytes(data),slice_offset=bias,text=text,sections=[text,const])
    player={'provenance':{'shield_getter':extent(50200,9 if mac else 4),
        'shield_assignment':extent(45000-(26 if mac else 14),26 if mac else 14),
        'reset':extent(45200+(8 if mac else 0),8 if mac else 12)}}
    vehicle={'equipment_rule':'last_matching','provenance':{'property_getter':extent(50000,4)}}
    clock={'provenance':{'frame':extent(40000-(0x547 if mac else 0x2cc),31 if mac else 34)}}
    return m,{'player_initialization':player},vehicle,clock,positions,fields,offset


class RechargeTests(unittest.TestCase):
    def test_independent_relocated_layouts(self):
        for mac in [False,True]:
            for shift in [0,0x900000]:
                m,a,v,c,_,_,_=fixture(mac,shift);result=reader.extract_player_recharge(m,a,v,c)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:x for k,x in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),12 if mac else 15)

    def test_reject_changed_blocks_and_cross_links(self):
        for mac in [False,True]:
            m,a,v,c,positions,fields,offset=fixture(mac)
            for key,at in positions.items():
                changed=copy.copy(m);raw=bytearray(m.data);raw[offset+at]^=255;changed.data=bytes(raw)
                self.assertFalse(reader.extract_player_recharge(changed,a,v,c),(mac,key))
            for block,field in [('pulse','call_c'),('assignment','call_11' if mac else 'call_8'),('recharge','call_12' if mac else 'call_10'),('application_order','call_5b' if mac else 'call_50'),('application_order','call_7e' if mac else 'call_74')]:
                changed=copy.copy(m);raw=bytearray(m.data);raw[offset+positions[block]+fields[block][field][0]]^=2;changed.data=bytes(raw)
                self.assertFalse(reader.extract_player_recharge(changed,a,v,c),(mac,block,field))
            changed=copy.deepcopy(c);changed['provenance']['frame']['offset']+=2
            self.assertFalse(reader.extract_player_recharge(m,a,v,changed))

    def test_reject_ambiguity_and_truncation(self):
        for mac in [False,True]:
            m,a,v,c,positions,_,offset=fixture(mac)
            raw=bytearray(m.data);size=reader.LAYOUTS[m.architecture]['pulse'][0]
            raw[offset+20000:offset+20000+size]=raw[offset+positions['pulse']:offset+positions['pulse']+size]
            changed=copy.copy(m);changed.data=bytes(raw)
            self.assertFalse(reader.extract_player_recharge(changed,a,v,c))
            changed=copy.copy(m);changed.data=m.data[:offset+47210]
            self.assertFalse(reader.extract_player_recharge(changed,a,v,c))
            self.assertFalse(reader.extract_player_recharge(m,{},v,c))
