"""Synthetic relocated LOD tables, independently changed distances and detail data."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import ship_lod as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    count=61 if mac else 64; base=0x100000+relocation; data=bytearray(13000); blocks={}
    text={'segment':b'__TEXT','name':b'__text','address':base,'offset':256,'length':8000}
    const={'segment':b'__TEXT','name':b'__const','address':base+9000,'offset':9000,'length':4000}
    m=SimpleNamespace(architecture='x86_64' if mac else 'armv7',text=text,sections=[text,const],slice_offset=0)
    locations={'body':64,'fill':264,'step':464,'child':664,'child_copy':864,'limit':1064,'square':3200,'cull':3500,'select':3640}
    if mac: locations['detail']=3544
    prefix='MAC_' if mac else 'ARM_'
    for key,at in locations.items():
        body,fields=expand(getattr(reader,prefix+key.upper()))
        for field,(off,size) in fields.items():
            site=base+at+off
            if field.startswith('call'):
                target=base+({'step':3000,'limit':3300}.get(key,7000))
                raw=struct.pack('<i',target-site-size) if mac else branch(((site+4)&~3)-4 if key=='select' else site,target)
                if not mac and key=='select': raw=raw[:3]+bytes([raw[3]&~0x10])
            elif field.startswith('ref'):
                target=base+({'body':9000,'fill':9000,'child':10000,'child_copy':10000}.get(key,11000))
                if key=='detail': target=base+{'ref_0':11000,'ref_15':11008,'ref_1f':11004,'ref_30':11012}[field]
                raw=struct.pack('<i',target-site-size)
            elif mac: raw=struct.pack('<i',{'fill':321,'step':700,'limit':50000}[key])
            else:
                meta=reader.ARM_FIELDS[prefix+key.upper()][field]; high=meta['kind']=='movt';value=1
                if key=='body' and field in ['word_0','word_8']: value=(base+9000)-(base+at+16+4);value=value>>16 if high else value&65535
                elif key=='child' and field in ['word_0','word_6']: value=(base+10000)-(base+at+12+4);value=value>>16 if high else value&65535
                elif (key,field) in [('body','word_c'),('child','word_e')]: value=65535
                elif (key,field)==('fill','word_c'): value=321
                elif key=='limit': value=0 if high else 50000
                if meta['kind']=='add.w': raw=bytes.fromhex('04f5fa54')
                else: raw=arm_wide(value,int(meta['register'][1:]),high)
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body;blocks[key]=(at,body,fields)
    raw=bytes.fromhex('554889e5480faff64889b7980000005dc3' if mac else 'b0b5a1fb014302af01fb023301fb0235c0e91c45b0bd');data[3556:3556+len(raw)]=raw
    for i in range(count):
        struct.pack_into('<3I',data,9000+i*12,2000+i*2,2001+i*2,77777)
        struct.pack_into('<3I',data,10000+i*12,65535,65535,88888)
    struct.pack_into('<3I',data,9012,2100,65535,99999)
    struct.pack_into('<5f',data,11000,0.2,0.8,0.25,1.0,0.625)
    m.data=bytes(data)
    return m,{'resource_ids':list(range(count))},{'provenance':[{'offset':320,'bytes':30}]},blocks


class ShipLOD(unittest.TestCase):
    def test_relocation_and_changed_data(self):
        for mac in [True,False]:
            for shift in [0,0x50000]:
                m,models,lights,_=fixture(mac,shift); result=reader.extract_ship_lod(m,models,lights)
                self.assertTrue(result,(mac,shift))
                self.assertEqual(result['distances'],[321,1021 if mac else 8321])
                self.assertEqual(result['body_resource_ids'][1],[2100,65535])
                self.assertEqual(result['maximum_distance'],50000)
                self.assertEqual(result['squared_distance_factors'],[0.25,0.625,1.0] if mac else [1.0])

    def test_corrupt_contexts_tables_and_links(self):
        for mac in [True,False]:
            for bad in ['body','step','select','cull','square','limit_setter','body_table','child_table','gap','link','extent','duplicate','missing']:
                with self.subTest(mac=mac,bad=bad):
                    m,models,lights,blocks=fixture(mac); data=bytearray(m.data)
                    if bad in blocks:
                        at,body,fields=blocks[bad];field_bytes={p for off,size in fields.values() for p in range(off,off+size)}
                        pos=next(p for p in range(len(body)) if p not in field_bytes);data[256+at+pos]^=1
                    elif bad=='limit_setter':data[3556]^=1
                    elif bad=='body_table':struct.pack_into('<I',data,9000,70000)
                    elif bad=='child_table':struct.pack_into('<I',data,10000,2222)
                    elif bad=='gap':struct.pack_into('<I',data,9000,65535)
                    elif bad=='link':
                        at,_,fields=blocks['step'];off,size=fields['call_3d' if mac else 'call_26'];data[256+at+off:256+at+off+size]=struct.pack('<i',6000-at-off-size) if mac else branch(m.text['address']+at+off,m.text['address']+6000)
                    elif bad=='extent':m.sections[1]['length']=10
                    elif bad=='duplicate':
                        at,body,_=blocks['body'];data[1856:1856+len(body)]=body
                    elif bad=='missing':lights={}
                    m.data=bytes(data);self.assertEqual(reader.extract_ship_lod(m,models,lights),{})
