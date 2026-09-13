"""Relocated synthetic speaker/name declarations without original content."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from gof2_content.speaker_bindings import extract_speaker_bindings, MAC_SPEAKERS, MAC_NAMES, ARM_SPEAKERS, ARM_NAMES
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    start=0x10000+relocation; name_start=start+512; getter=start+1024; data_start=start+4096
    speaker,sf=expand(MAC_SPEAKERS if mac else ARM_SPEAKERS)
    names,nf=expand(MAC_NAMES if mac else ARM_NAMES)
    def put(block,fields,key,value):
        at,n=fields[key];assert len(value)==n;block[at:at+n]=value
    for block,fields,base,is_name in [(speaker,sf,start,False),(names,nf,name_start,True)]:
        for key,(at,n) in fields.items():
            if key.startswith('call_'):
                target=start+1200+at*4
                if key==('call_1' if mac else 'call_0'): target=getter
                elif (not is_name and key in (['call_25','call_f3'] if mac else ['call_24','call_9c'])):target=start+1800
                elif (not is_name and key in (['call_1b','call_b3','call_e9'] if mac else ['call_16','call_82'])):target=start+1804
                elif (is_name and key in (['call_a0','call_eb'] if mac else ['call_96','call_f8'])):target=start+1808
                if mac:raw=struct.pack('<i',target-base-at-4)
                else:
                    blx=not is_name and key in ['call_16','call_24','call_82','call_9c']
                    raw=bytearray(branch(((base+at+4)&~3)-4 if blx else base+at,target))
                    if blx:raw[3]&=~0x10
                put(block,fields,key,raw)
            elif mac and key.startswith('ref_'):
                target=data_start+2048
                if not is_name and key=='ref_101':target=data_start
                put(block,fields,key,struct.pack('<i',target-base-at-4))
    def scalar(block,fields,key,value):put(block,fields,key,int(value).to_bytes(fields[key][1],'little',signed=True))
    if mac:
        for key,value in {'number_b':500,'number_30':-500,'number_7f':4,'number_85':3,'number_9e':3}.items():scalar(speaker,sf,key,value)
        for key,value in {'number_50':500,'number_5e':-500,'number_b7':200}.items():scalar(names,nf,key,value)
    else:
        def wide(block,fields,key,value,reg=0,top=False):put(block,fields,key,arm_wide(value,reg,top))
        def ref(block,fields,base,lo,hi,pc,target):
            delta=target-base-pc;wide(block,fields,lo,delta&65535);wide(block,fields,hi,delta>>16,top=True)
        for key in ['value_6','value_2c']:wide(speaker,sf,key,500)
        scalar(speaker,sf,'number_72',4);scalar(speaker,sf,'number_76',3)
        ref(speaker,sf,start,'value_36','value_3c',0x44,data_start+2048)
        ref(speaker,sf,start,'value_86','value_8e',0x98,data_start)
        ref(names,nf,name_start,'value_6','value_a',0x16,data_start+2052)
        ref(names,nf,name_start,'value_54','value_5c',0x68,data_start+2048)
        ref(names,nf,name_start,'value_b8','value_c0',0xc8,data_start+2056)
        wide(names,nf,'value_4c',500)
        wide(names,nf,'value_58',(-500*4)&65535,1)
        wide(names,nf,'value_60',65535,1,True)
        # ADDW r1,r4,#200, with the same split immediate layout as MOVW.
        raw=bytearray(arm_wide(200,1));lo,hi=struct.unpack('<2H',raw)
        put(names,nf,'value_bc',struct.pack('<2H',(lo&0x400)|0xf204,hi))
    data=bytearray(8192)
    data[64:64+len(speaker)]=speaker;data[576:576+len(names)]=names
    getter_bytes=bytes.fromhex('554889e58b47145dc3' if mac else 'c0687047')
    data[1088:1088+len(getter_bytes)]=getter_bytes
    for i in range(5):
        pointer=data_start+5000 if i==0 else data_start+128+20*i
        struct.pack_into('<Q' if mac else '<I',data,4096+i*(8 if mac else 4),pointer)
        struct.pack_into('<5i',data,4096+128+20*i,2,0,-1,3,4)
    text={'name':b'__text','segment':b'__TEXT','address':start,'offset':64,'length':2048}
    content={'name':b'__data','segment':b'__DATA','address':data_start,'offset':4096,'length':3072}
    return SimpleNamespace(data=bytes(data),text=text,sections=[text,content],slice_offset=16384,architecture='x86_64' if mac else 'armv7'),sf,nf


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class SpeakerBindings(unittest.TestCase):
    def test_both_architectures_and_relocation(self):
        for mac in [True,False]:
            for relocation in [0,0x30000]:
                with self.subTest(mac=mac,relocation=relocation):
                    mach,_,_=fixture(mac,relocation);scope=extract_speaker_bindings(mach)
                    self.assertEqual(scope.get('first_name_id'),200)
                    self.assertEqual(scope['agent_speaker_start'],500)
                    self.assertEqual(scope['fixed_speaker_count'],5)
                    self.assertEqual([r['status'] for r in scope['portraits']],['unavailable','fixed','fixed','procedural','fixed'])
                    self.assertEqual(scope['portraits'][1]['parts'],[0,-1,3,4])
                    self.assertEqual(scope['portraits'][1]['source_offset'],16384+4096+148)
                    self.assertEqual(scope['provenance']['speaker_getter']['offset'],17472)

    def test_rejects_broken_links_fields_and_tables(self):
        for mac in [True,False]:
            for bad in ['getter','threshold','copy','table','call','parts']:
                with self.subTest(mac=mac,bad=bad):
                    mach,sf,nf=fixture(mac);data=bytearray(mach.data)
                    if bad=='getter':data[1088]=0
                    elif bad=='threshold':data[64+sf['number_b' if mac else 'value_6'][0]]^=1
                    elif bad=='table':
                        key='ref_101' if mac else 'value_86';at,n=sf[key];data[64+at:64+at+n]=b'\0'*n
                    elif bad=='call':
                        key='call_a0' if mac else 'call_96';at,n=nf[key];data[576+at]^=1
                    elif bad=='parts':struct.pack_into('<i',data,4096+148,-2)
                    if bad=='copy':
                        end=285 if mac else 182;data[64+end-1]^=1
                    mach.data=bytes(data)
                    self.assertEqual(extract_speaker_bindings(mach),{})

    def test_source_name_offset_and_missing_scope(self):
        for mac in [True,False]:
            mach,sf,nf=fixture(mac);data=bytearray(mach.data)
            if mac:struct.pack_into('<i',data,576+nf['number_b7'][0],300)
            else:
                lo,hi=struct.unpack('<2H',arm_wide(300,1));at=576+nf['value_bc'][0]
                data[at:at+4]=struct.pack('<2H',(lo&0x400)|0xf204,hi)
            mach.data=bytes(data)
            self.assertEqual(extract_speaker_bindings(mach)['first_name_id'],300)
            mach.data=b'\0'*len(data)
            self.assertEqual(extract_speaker_bindings(mach),{})

if __name__=='__main__':unittest.main()
