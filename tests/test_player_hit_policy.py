"""Synthetic source data and relocation checks for player damage scaling."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content.player_hit_policy import extract_player_hit_policy
from gof2_content.ordinary_hit_policy import MAC_ROUTE, ARM_ROUTE
from test_font_selection import expand


def fixture(mac, shift=0):
    origin=0x300000+shift;offset=256;bias=4096;at=1000 if mac else 1002
    raw,fields=expand(MAC_ROUTE if mac else ARM_ROUTE);data=bytearray(5256)
    if mac:
        for index,field in enumerate(['constant_32','constant_86','constant_8e']):
            p,n=fields[field];raw[p:p+n]=struct.pack('<i',4000+index*4-at-p-n)
        data[offset+4000:offset+4012]=struct.pack('<3f',0.2,3.0,0.25)
    else:
        data[offset+at-0x344:offset+at-0x344+12]=bytes.fromhex('80ef188f85ef10af9fede7ca')
    data[offset+at:offset+at+len(raw)]=raw
    text={'name':b'__text','segment':b'__TEXT','address':origin,'offset':offset,'length':3500}
    const={'name':b'__const','segment':b'__TEXT','address':origin+4000,'offset':offset+4000,'length':1000}
    m=SimpleNamespace(data=bytes(data),architecture='x86_64' if mac else 'armv7',slice_offset=bias,text=text,sections=[text,const])
    weapon={'ordinary_hit_policy':{'provenance':{'damage_route':{'offset':bias+offset+at,'bytes':len(raw)}}}}
    return m,weapon,at,fields


class PlayerHitPolicyTests(unittest.TestCase):
    def test_relocated_source_scalars(self):
        for mac in [False,True]:
            for shift in [0,0xa00000]:
                m,w,_,_=fixture(mac,shift);result=extract_player_hit_policy(m,w)
                self.assertTrue(result,(mac,shift))
                self.assertEqual(result['nonhostile_scale'],struct.unpack('<f',struct.pack('<f',0.2))[0])
                self.assertEqual(result['special_flight_multipliers'],[3,0.25])
                self.assertTrue(result['nonhostile_precedes_special'])
                self.assertEqual(len(result['provenance']),4 if mac else 2)

    def test_reject_broken_branches_scalars_and_live_registers(self):
        for mac in [False,True]:
            m,w,at,fields=fixture(mac)
            locations=[at+8,4000,4004,4008] if mac else [at+8,at+98,at-0x344,at-0x340,at-0x33c]
            if mac:locations.extend(at+fields[key][0] for key in ['constant_32','constant_86','constant_8e'])
            for site in locations:
                changed=copy.copy(m);data=bytearray(m.data);data[256+site]^=1;changed.data=bytes(data)
                self.assertEqual(extract_player_hit_policy(changed,w),{},(mac,site))
            changed=copy.copy(m);changed.data=m.data[:256+at+50]
            self.assertEqual(extract_player_hit_policy(changed,w),{})
            moved=copy.deepcopy(w);moved['ordinary_hit_policy']['provenance']['damage_route']['offset']+=2
            self.assertEqual(extract_player_hit_policy(m,moved),{})
            self.assertEqual(extract_player_hit_policy(m,{}),{})
