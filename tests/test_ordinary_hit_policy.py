"""Relocated hit-policy declarations and broken constructor/collision links."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import ordinary_hit_policy as reader
from gof2_content.weapon_parameters import MAC_LAUNCH_MODE,ARM_LAUNCH_MODE
from test_font_selection import expand
from test_ship_models import branch
from test_materials import arm_wide


def fixture(mac,shift=0):
    base=0x100000+shift;offset=256;slice_offset=4096
    data=bytearray(6256);text={'name':b'__text','segment':b'__TEXT','address':base,'offset':offset,'length':6000}
    positions={'classification':1000,'property_getter':2000,'additional_gate':3000,'normal_hit':4000,'other':4500}
    blocks={}
    def block(key,at,spec):
        raw,fields=expand(spec)
        for name,(p,n) in fields.items():
            if key=='classification' and name in ['first','count','single','address_low','address_high']:
                if mac:value=(-9).to_bytes(1,'little',signed=True) if name=='first' else bytes([3]) if name=='count' else struct.pack('<I',228) if name=='single' else bytes(n)
                else:value=bytes.fromhex({'first':'a4f10900','count':'0328','single':'e42c'}[name]) if name in ['first','count','single'] else arm_wide(1,1,name=='address_high')
            elif name=='getter' or name.startswith('call_') or name=='extra':
                to=positions['property_getter'] if name=='getter' else positions['normal_hit'] if name in ['call_b4','call_74'] else positions['other']
                value=struct.pack('<i',to-at-p-n) if mac else branch(base+at+p,base+to)
            elif name=='missing':value=bytes.fromhex('257899c5')
            elif key=='additional_gate':value=arm_wide(0x7825 if name=='low' else 0xc599,0,name=='high')
            elif key=='additional_store' and not mac:value=arm_wide(1,1,name=='high')
            else:value=bytes(n)
            assert len(value)==n
            raw[p:p+n]=value
        data[offset+at:offset+at+len(raw)]=raw;blocks[key]=(at,raw,fields)
    block('classification',1000,MAC_LAUNCH_MODE if mac else ARM_LAUNCH_MODE)
    block('additional_store',1000+len(blocks['classification'][1]),reader.MAC_STORE if mac else reader.ARM_STORE)
    block('property_getter',2000,reader.MAC_GETTER if mac else reader.ARM_GETTER)
    block('additional_gate',3000,reader.MAC_EXTRA if mac else reader.ARM_EXTRA)
    block('damage_route',3000+len(blocks['additional_gate'][1]),reader.MAC_ROUTE if mac else reader.ARM_ROUTE)
    block('normal_hit',4000,reader.MAC_NORMAL if mac else reader.ARM_NORMAL)
    def span(key):return {'offset':slice_offset+offset+blocks[key][0],'bytes':len(blocks[key][1])}
    weapon={'launch_modes':{'alternate_item_ids':[9,10,11,228],'provenance':{'classification':span('classification')}},'provenance':{'property_getter':span('property_getter')}}
    mach=SimpleNamespace(data=bytes(data),text=text,sections=[text],slice_offset=slice_offset,architecture='x86_64' if mac else 'armv7')
    return mach,weapon,blocks


class OrdinaryHitPolicy(unittest.TestCase):
    def test_relocation_and_policy(self):
        for mac in [True,False]:
            for shift in [0,0x400000]:
                m,w,_=fixture(mac,shift);r=reader.extract_ordinary_hit_policy(m,w)
                self.assertTrue(r,(mac,shift))
                self.assertEqual(r['additional_damage_property'],10)
                self.assertEqual(r['missing_additional_damage'],-979797979)
                self.assertEqual(r['nonplayer_damage_scale'],1.0)

    def test_each_extent_required(self):
        for mac in [True,False]:
            m,w,_=fixture(mac);r=reader.extract_ordinary_hit_policy(m,w)
            self.assertTrue(r)
            for key,span in r['provenance'].items():
                damaged=copy.copy(m);raw=bytearray(m.data);raw[span['offset']-m.slice_offset]^=255;damaged.data=bytes(raw)
                self.assertFalse(reader.extract_ordinary_hit_policy(damaged,w),(mac,key))

    def test_links_absence_sentinel_and_ambiguity(self):
        for mac in [True,False]:
            for bad in ['getter','normal','player_link','sentinel','duplicate','missing','truncated']:
                m,w,blocks=fixture(mac);raw=bytearray(m.data)
                if bad in ['getter','normal','player_link']:
                    key='classification' if bad=='getter' else 'damage_route'
                    field='getter' if bad=='getter' else ('call_b4' if mac else 'call_74') if bad=='normal' else ('call_5a' if mac else 'call_24')
                    at,_,fields=blocks[key];p,n=fields[field]
                    raw[256+at+p:256+at+p+n]=struct.pack('<i',4700-at-p-n) if mac else branch(m.text['address']+at+p,m.text['address']+4700)
                elif bad=='sentinel':
                    at,_,fields=blocks['additional_gate'];p,n=fields['missing' if mac else 'low'];raw[256+at+p:256+at+p+n]=struct.pack('<i',-100) if mac else arm_wide(123,0)
                elif bad=='duplicate':
                    block=blocks['additional_gate'][1];raw[5256:5256+len(block)]=block
                elif bad=='missing':w={}
                elif bad=='truncated':raw=raw[:256+4004]
                m.data=bytes(raw)
                self.assertFalse(reader.extract_ordinary_hit_policy(m,w),(mac,bad))

if __name__=='__main__':unittest.main()
