"""Relocated population declarations, linked sampler and ARM symbol validation."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import scenery_population as reader
from test_font_selection import expand
from test_ship_models import branch
from test_materials import arm_wide


def fixture(mac,shift=0):
    base=0x100000+shift;offset=512;data=bytearray(9000);slice_offset=4096 if mac else 0
    sites={'count':1000,'station':2000,'station_id':2200,'seed':2400,'draw':2600,'bits':3000,'resize':3500,'modulo':6000}
    blocks={}
    def block(key,spec):
        at=sites[key];raw,fields=expand(spec)
        for name,(p,n) in fields.items():
            if name=='base':value=bytes([17])
            elif name=='bound':value=(37).to_bytes(n,'little')
            elif name in ['low','high']:value=arm_wide(0,0,name=='high')
            elif name=='random':value=bytes(n)
            else:
                dest=sites['bits'] if name in ['first','repeat'] else sites[name]
                if mac:value=struct.pack('<i',dest-at-p-n)
                elif name=='modulo':
                    # The immediate BLX to an aligned ARM stub uses an aligned PC.
                    delta=(base+dest)-((base+at+p+4)&~3)
                    s=(delta>>24)&1;i1=(delta>>23)&1;i2=(delta>>22)&1
                    value=struct.pack('<HH',0xf000|(s<<10)|((delta>>12)&0x3ff),0xc000|((1^i1^s)<<13)|((1^i2^s)<<11)|((delta>>1)&0x7fe))
                else:value=branch(base+at+p,base+dest)
            raw[p:p+n]=value
        data[offset+at:offset+at+len(raw)]=raw;blocks[key]=(at,raw,fields)
    block('count',reader.MAC_COUNT if mac else reader.ARM_COUNT)
    block('station','554889e5488b87180200005dc3' if mac else 'd0f888017047')
    block('station_id','554889e58b47105dc3' if mac else '80687047')
    for key in ['seed','draw','bits']:block(key,getattr(reader,('MAC_' if mac else 'ARM_')+key.upper()))
    text={'name':b'__text','segment':b'__TEXT','address':base,'offset':offset,'length':5000}
    if not mac:
        struct.pack_into('<7I',data,0,0xfeedface,12,9,2,3,296,0)
        struct.pack_into('<2I',data,28,1,192);struct.pack_into('<I',data,28+48,2)
        for i,(addr,length,where,flags,first,stride) in enumerate([(base,5000,offset,0,0,0),(base+6000,16,6512,8,0,16)]):
            at=28+56+68*i;struct.pack_into('<3I',data,at+32,addr,length,where);struct.pack_into('<3I',data,at+56,flags,first,stride)
        name=b'\0___modsi3\0'
        struct.pack_into('<6I',data,220,2,24,7100,1,7200,len(name))
        struct.pack_into('<2I',data,244,11,80);struct.pack_into('<2I',data,244+56,7000,1)
        struct.pack_into('<I',data,7000,0);struct.pack_into('<IB',data,7100,1,1);data[7200:7200+len(name)]=name
    m=SimpleNamespace(data=bytes(data),text=text,sections=[text],slice_offset=slice_offset,architecture='x86_64' if mac else 'armv7')
    return m,blocks


class SceneryPopulation(unittest.TestCase):
    def test_relocated_and_changed_counts(self):
        for mac in [True,False]:
            for shift in [0,0x400000]:
                m,_=fixture(mac,shift);result=reader.extract_scenery_population(m)
                self.assertEqual((result.get('count_base'),result.get('count_bound')),(17,37),(mac,shift,result))

    def test_each_proof_and_links(self):
        for mac in [True,False]:
            m,_=fixture(mac);result=reader.extract_scenery_population(m);self.assertTrue(result)
            for key,span in result['provenance'].items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[span['offset']-m.slice_offset]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_scenery_population(bad),(mac,key))
            for change in ['duplicate','bound_zero','second_bits','station','truncated']:
                bad,blocks=fixture(mac);raw=bytearray(bad.data)
                if change=='duplicate':
                    at,body,_=blocks['count'];raw[512+4000:512+4000+len(body)]=body
                elif change=='truncated':raw=raw[:512+3020]
                else:
                    key='draw' if change=='second_bits' else 'count';field='repeat' if change=='second_bits' else 'bound' if change=='bound_zero' else 'station'
                    at,body,fields=blocks[key];p,n=fields[field]
                    raw[512+at+p:512+at+p+n]=bytes(n)
                bad.data=bytes(raw)
                self.assertFalse(reader.extract_scenery_population(bad),(mac,change))

    def test_imported_modulo_is_required(self):
        for change in ['name','index','kind','stride','command','truncated']:
            m,_=fixture(False);raw=bytearray(m.data)
            if change=='name':raw[7204]=ord('x')
            elif change=='index':struct.pack_into('<I',raw,7000,1)
            elif change=='kind':raw[7104]=15
            elif change=='stride':struct.pack_into('<I',raw,28+56+68+64,0)
            elif change=='command':struct.pack_into('<I',raw,244+4,4)
            else:raw=raw[:7205]
            m.data=bytes(raw)
            self.assertFalse(reader.extract_scenery_population(m),change)
