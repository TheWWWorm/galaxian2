"""Relocated manager clocks with changed constants and verified selector links."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import lod_refresh as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    base=0x100000+relocation; data=bytearray(4096); blocks={}
    locations={'initial':64,'batch':128,'tick':400}
    prefix='MAC_' if mac else 'ARM_'
    for key,at in locations.items():
        body,fields=expand(getattr(reader,prefix+key.upper()))
        for field,(off,size) in fields.items():
            site=base+at+off
            if field.startswith(('call','jump','ref')):
                dest=base+(128 if key=='tick' else 1000)
                raw=struct.pack('<i',dest-site-size) if mac else bytearray(branch(site,dest))
                if not mac and key=='tick': raw[3]&=~0x40
            elif mac: raw=struct.pack('<i',73 if key=='initial' else 201)
            elif key=='tick': raw=bytes.fromhex('b1f5fa7f') # cmp.w r1, #500
            else:
                meta=reader.ARM_FIELDS[prefix+key.upper()][field]
                raw=arm_wide(73,int(meta['register'][1:]),meta['kind']=='movt')
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body;blocks[key]=(at,body,fields)
    m=SimpleNamespace(architecture='x86_64' if mac else 'armv7',data=bytes(data),slice_offset=8192,
        text={'address':base,'offset':256,'length':2048})
    return m,{'provenance':{'cull':{'offset':8192+256+1100,'bytes':20}}},blocks


class LODRefresh(unittest.TestCase):
    def test_changed_constants_and_relocation(self):
        for mac in [True,False]:
            for shift in [0,0x90000]:
                m,lod,_=fixture(mac,shift);result=reader.extract_lod_refresh(m,lod)
                self.assertTrue(result,(mac,shift))
                self.assertEqual(result['initial_milliseconds'],73)
                self.assertEqual(result['refresh_at_milliseconds'],201 if mac else 501)
                self.assertEqual(result['reset_milliseconds'],0)
                self.assertFalse(result['forced_refresh_resets_clock'])
                self.assertEqual(result['provenance']['initial']['offset'],8512)

    def test_rejects_corruption_and_unlinked_context(self):
        for mac in [True,False]:
            for bad in ['initial','batch','tick','jump','selector','duplicate','missing','register']:
                with self.subTest(mac=mac,bad=bad):
                    m,lod,blocks=fixture(mac);data=bytearray(m.data)
                    if bad in blocks:
                        at,_,_=blocks[bad];data[256+at]^=1
                    elif bad=='jump':
                        at,_,fields=blocks['tick'];off,size=fields['jump_1e' if mac else 'jump_14']
                        raw=struct.pack('<i',1000-at-off-size) if mac else bytearray(branch(m.text['address']+at+off,m.text['address']+1000))
                        if not mac:raw[3]&=~0x40
                        data[256+at+off:256+at+off+size]=raw
                    elif bad=='selector':lod['provenance']['cull']['offset']+=512
                    elif bad=='duplicate':
                        _,body,_=blocks['initial'];data[1856:1856+len(body)]=body
                    elif bad=='missing':lod={}
                    elif bad=='register':
                        if mac:continue
                        at,_,fields=blocks['initial'];off,size=fields['word_6'];data[256+at+off:256+at+off+size]=arm_wide(73,1,False)
                    m.data=bytes(data)
                    self.assertEqual(reader.extract_lod_refresh(m,lod),{})
