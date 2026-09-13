"""Relocated synthetic declarations and corruption checks for portrait placement."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from gof2_content.portrait_layers import extract_portrait_layers, MAC_LAYERS, MAC_ORDER, ARM_LAYERS, ARM_ORDER
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    start=0x10000+relocation; order_start=start+512; data_start=start+4096
    layers,lf=expand(MAC_LAYERS if mac else ARM_LAYERS)
    order,of=expand(MAC_ORDER if mac else ARM_ORDER)
    tables={'part_bases':data_start,'medium':data_start+256,'large':data_start+768,'expanded':data_start+1280,'baseline':data_start+1792}
    def put(block,fields,key,value):
        at,n=fields[key];assert len(value)==n;block[at:at+n]=value
    for block,fields,base in [(layers,lf,start),(order,of,order_start)]:
        for key,(at,n) in fields.items():
            if not key.startswith('call_'):continue
            target=start if block is order else start+2048
            if mac:raw=struct.pack('<i',target-base-at-4)
            else:
                blx=block is layers and key in ['call_4a','call_88','call_134']
                raw=bytearray(branch(((base+at+4)&~3)-4 if blx else base+at,target))
                if blx:raw[3]&=~0x10
            put(block,fields,key,raw)
    if mac:
        refs={'ref_17':'part_bases','ref_76':'medium','ref_c4':'medium','ref_92':'large','ref_f2':'large','ref_d4':'expanded','ref_10b':'expanded','ref_a7':'baseline','ref_118':'baseline'}
        flags={'ref_5f':data_start+2500,'ref_86':data_start+2504,'ref_e2':data_start+2504,'ref_9b':data_start+2508,'ref_fb':data_start+2508,'ref_3f':data_start+2512}
        for key,(at,n) in lf.items():
            if key.startswith('ref_'):
                target=tables[refs[key]] if key in refs else flags[key]
                put(layers,lf,key,struct.pack('<i',target-start-at-4))
    else:
        refs=[('value_1c','value_22',0x2c,0,data_start+2520),('value_64','value_6a',0x74,0,data_start+2524),
              ('value_4e','value_52',0x5a,0,tables['part_bases']),
              ('value_a0','value_a4',0xac,0,tables['medium']),('value_10e','value_112',0x11a,0,tables['medium']),
              ('value_c0','value_c4',0xcc,0,tables['large']),
              ('value_e4','value_e8',0xf0,2,tables['expanded']),('value_166','value_16a',0x172,0,tables['expanded']),
              ('value_f8','value_fc',0x104,2,tables['baseline']),('value_172','value_176',0x17e,0,tables['baseline']),
              ('value_8c','value_90',0x9a,1,data_start+2500),('value_b4','value_b8',0xc0,0,data_start+2504),
              ('value_d2','value_d6',0xde,2,data_start+2508),('value_156','value_15a',0x162,0,data_start+2508)]
        for lo,hi,pc,reg,target in refs:
            delta=(target-start-pc)&0xffffffff
            put(layers,lf,lo,arm_wide(delta&65535,reg));put(layers,lf,hi,arm_wide(delta>>16,reg,True))
    data=bytearray(8192)
    data[64:64+len(layers)]=layers;data[576:576+len(order)]=order
    struct.pack_into('<52i',data,4096,*([500,510,-1,530]*13))
    for index,name in enumerate(['medium','large','expanded','baseline']):
        at=4096+tables[name]-data_start
        struct.pack_into('<104i',data,at,*([16,10+index,32,20+index,0,-3,16,0]*13))
    text={'name':b'__text','segment':b'__TEXT','address':start,'offset':64,'length':3000}
    content={'name':b'__data','segment':b'__DATA','address':data_start,'offset':4096,'length':3072}
    return SimpleNamespace(data=bytes(data),text=text,sections=[text,content],slice_offset=16384,architecture='x86_64' if mac else 'armv7'),lf,of


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class PortraitLayers(unittest.TestCase):
    def test_relocated_tables_and_signed_placements(self):
        for mac in [True,False]:
            for relocation in [0,0x30000]:
                with self.subTest(mac=mac,relocation=relocation):
                    mach,_,_=fixture(mac,relocation);scope=extract_portrait_layers(mach)
                    self.assertEqual(scope['part_bases'],[[500,510,-1,530]]*13)
                    self.assertEqual(scope['draw_order'],[2,1,0,3])
                    self.assertEqual(scope['variants']['baseline'][0],[{'anchor':16,'y':13},{'anchor':32,'y':23},{'anchor':0,'y':-3},{'anchor':16,'y':0}])
                    self.assertEqual(scope['provenance']['part_bases'],{'offset':20480,'bytes':208})

    def test_rejects_mutated_links_stride_order_and_tables(self):
        for mac in [True,False]:
            for bad in ['link','repeat','order','stride','anchor','offset','base','truncated']:
                with self.subTest(mac=mac,bad=bad):
                    mach,lf,of=fixture(mac);data=bytearray(mach.data)
                    if bad=='link':data[576+of['call_13' if mac else 'call_16'][0]]^=1
                    elif bad=='repeat':data[64+lf['ref_c4' if mac else 'value_10e'][0]]^=1
                    elif bad=='order':data[576+len(expand(MAC_ORDER if mac else ARM_ORDER)[0])-1]^=1
                    elif bad=='stride':data[64+10]^=1
                    elif bad=='anchor':struct.pack_into('<i',data,4096+256,64)
                    elif bad=='offset':struct.pack_into('<i',data,4096+256+4,8193)
                    elif bad=='base':struct.pack_into('<i',data,4096,-2)
                    elif bad=='truncated':mach.sections[1]['length']=2000
                    mach.data=bytes(data)
                    self.assertEqual(extract_portrait_layers(mach),{})

    def test_ambiguous_declaration_and_unknown_architecture(self):
        for mac in [True,False]:
            mach,_,_=fixture(mac);data=bytearray(mach.data)
            block=expand(MAC_LAYERS if mac else ARM_LAYERS)[0]
            data[1088:1088+len(block)]=data[64:64+len(block)];mach.data=bytes(data)
            self.assertEqual(extract_portrait_layers(mach),{})
            mach.architecture='unknown';self.assertEqual(extract_portrait_layers(mach),{})

if __name__=='__main__':unittest.main()
