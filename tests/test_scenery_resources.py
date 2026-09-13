"""Synthetic relocated declarations and disconnected-resource rejection."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import scenery_resources as reader
from test_font_selection import expand
from test_ship_models import branch
from test_materials import arm_wide


def fixture(mac,shift=0):
    base=0x4000+shift;off=512;data=bytearray(25000);slice_offset=4096 if mac else 0
    sites={'entry':988 if mac else 994,'probability':5000,'selector':2000,'models':3000,'item':8000,'item_origin':8280 if mac else 8176,'station_system':9000,'system_x':9100,'system_y':9200,'sqrt_wrapper':10000,'sqrt':10100,'draw':16000,'table':20000,'stub':21000}
    blocks={}
    links={}
    for key,fields in [('station_system',('call_e2','call_101') if mac else ('call_a4','call_b8')),('system_x',('call_f6','call_139') if mac else ('call_b0','call_de')),('system_y',('call_111','call_168') if mac else ('call_c4','call_100')),('item_origin',('call_129','call_158') if mac else ('call_d2','call_ea')),('sqrt_wrapper',('call_188',) if mac else ('call_11c',))]:
        for field in fields:links[field]=sites[key]
    def block(key,spec):
        at=sites[key];raw,fields=expand(spec)
        for name,(p,n) in fields.items():
            if name in ('ore_first','weight_base','weight_min','fallback','override_item'):
                value={'ore_first':154,'weight_base':90,'weight_min':40,'fallback':164,'override_item':217}[name]
                if not mac and name=='ore_first':value=bytes.fromhex('4ff09a0b')
                elif not mac and name=='weight_base':value=bytes.fromhex('c0f15a00')
                else:value=value.to_bytes(n,'little')
            elif not mac and name.startswith('word_'):
                top=name in ('word_12','word_58','word_7e','word_18')
                delta=sites['table']-at-0x20 if key=='models' else 0
                value=arm_wide((delta>>16) if top else (delta&65535),0,top)
            elif name.startswith('ref_'):
                value=struct.pack('<i',sites['table']-at-p-n) if key=='models' else bytes(n)
            else:
                dest=15000
                if key=='entry':dest=sites['probability']
                elif key=='probability':dest=links.get(name,dest)
                elif key=='selector':dest=sites['draw']
                elif key=='sqrt_wrapper':dest=sites['sqrt']
                elif key=='sqrt':dest=sites['stub']
                value=struct.pack('<i',dest-at-p-n) if mac else branch(base+at+p,base+dest)
                if key=='sqrt_wrapper' and not mac:
                    first,second=struct.unpack('<2H',value);value=struct.pack('<2H',first,second&~0x4000)
            raw[p:p+n]=value
        data[off+at:off+at+len(raw)]=raw;blocks[key]=(at,raw,fields)
    prefix='MAC_' if mac else 'ARM_'
    block('entry','e8 {call:4} 48898520ffffff' if mac else '{call:4} 0a90')
    for key in ['probability','selector','models','item','sqrt']:block(key,getattr(reader,prefix+key.upper()))
    for key,spec in [('station_system','554889e58b47145dc3' if mac else 'c0687047'),('system_x','554889e58b472c5dc3' if mac else '006a7047'),('system_y','554889e58b47305dc3' if mac else '406a7047'),('item_origin','554889e58b47105dc3' if mac else '00697047'),('sqrt_wrapper','554889e55de9 {call:4}' if mac else '0846 {call:4}')]:block(key,spec)
    struct.pack_into('<4i',data,off+sites['table'],1100,1200,1300,1400)
    data[off+sites['stub']:off+sites['stub']+6]=bytes.fromhex('ff2500000000')
    sections=[{'name':b'__text','segment':b'__TEXT','address':base,'offset':off,'length':18000},{'name':b'__const','segment':b'__TEXT','address':base+20000,'offset':off+20000,'length':16},{'name':b'__stubs','segment':b'__TEXT','address':base+21000,'offset':off+21000,'length':6}]
    if mac:
        # Minimal symbol metadata sufficient to identify the imported sqrt stub.
        struct.pack_into('<8I',data,0,0xfeedfacf,0x1000007,0,2,3,256,0,0)
        struct.pack_into('<2I',data,32,0x19,152);struct.pack_into('<I',data,32+64,1)
        section=32+72;struct.pack_into('<QQI',data,section+32,base+21000,6,off+21000);struct.pack_into('<3I',data,section+64,8,0,6)
        struct.pack_into('<6I',data,184,2,24,23000,1,23100,7)
        struct.pack_into('<2I',data,208,11,80);struct.pack_into('<2I',data,208+56,23200,1)
        struct.pack_into('<IB',data,23000,1,1);data[23100:23107]=b'\0_sqrt\0';struct.pack_into('<I',data,23200,0)
    m=SimpleNamespace(data=bytes(data),text=sections[0],sections=sections,slice_offset=slice_offset,architecture='x86_64' if mac else 'armv7')
    population={'provenance':{'count':{'offset':slice_offset+off+1000,'bytes':66 if mac else 70},'draw':{'offset':slice_offset+off+sites['draw'],'bytes':171 if mac else 114}}}
    return m,population,blocks


class SceneryResources(unittest.TestCase):
    def test_relocated_resources_and_weights(self):
        for mac in [True,False]:
            for shift in [0,0x800000]:
                m,p,_=fixture(mac,shift);r=reader.extract_scenery_resources(m,p)
                self.assertEqual(r.get('model_ids'),[1100,1200,1300,1400],(mac,shift,r))
                self.assertEqual((r['weight_base'],r['weight_minimum']),(90,40))
                self.assertEqual(r['ore_item_ids'],list(range(154,164)))
                self.assertEqual(len(r['provenance']),12)

    def test_proofs_links_and_unsupported_inputs(self):
        for mac in [True,False]:
            m,p,blocks=fixture(mac);result=reader.extract_scenery_resources(m,p);self.assertTrue(result)
            for key,span in result['provenance'].items():
                bad=copy.copy(m);raw=bytearray(m.data)
                if key=='model_table':struct.pack_into('<i',raw,span['offset']-m.slice_offset,-1)
                else:raw[span['offset']-m.slice_offset]^=255
                bad.data=bytes(raw);self.assertFalse(reader.extract_scenery_resources(bad,p),(mac,key))
            self.assertFalse(reader.extract_scenery_resources(m,{}))
            for change in ['duplicate','draw','second_origin','truncated']:
                bad=copy.copy(m);raw=bytearray(m.data)
                if change=='duplicate':
                    at,body,_=blocks['models'];raw[512+3500:512+3500+len(body)]=body
                elif change=='truncated':raw=raw[:6000]
                else:
                    key='selector' if change=='draw' else 'probability';field=('call_30' if mac else 'call_3e') if change=='draw' else ('call_158' if mac else 'call_ea')
                    at,_,fields=blocks[key];start,n=fields[field];raw[512+at+start:512+at+start+n]=bytes(n)
                bad.data=bytes(raw);self.assertFalse(reader.extract_scenery_resources(bad,p),(mac,change))

    def test_mac_sqrt_import_metadata(self):
        for change in ['name','type','index','stride','truncated']:
            m,p,_=fixture(True);raw=bytearray(m.data)
            if change=='name':raw[23102]=ord('x')
            elif change=='type':raw[23004]=15
            elif change=='index':struct.pack_into('<I',raw,23200,1)
            elif change=='stride':struct.pack_into('<I',raw,32+72+72,0)
            else:raw=raw[:23104]
            m.data=bytes(raw);self.assertFalse(reader.extract_scenery_resources(m,p),change)
