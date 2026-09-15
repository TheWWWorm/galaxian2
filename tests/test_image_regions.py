"""Synthetic image aliases, with independently relocated declarations."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from gof2_content.image_regions import extract_image_bindings, MAC_RECORD, MAC_STACK_RECORD, MAC_RANGE, ARM_RANGE
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch

ARM_RECORD = """
1020c4f87055
{call_6:4}
c4f8f401
{value_e:4}
c4f870050420
{call_18:4}
0bae
{value_1e:4}
06f58041
{value_26:4}
{value_2a:4}
4ff0ff350c46d4f8f4110260d4f8f42113800323d4f8f4215360d4f8f4219560d4f8f421d060c4f870550798
{call_5a:4}
"""


def fixture(mac, sequence=False, relocation=0, stacked=False):
    start=0x10000+relocation
    spec=(MAC_RANGE if mac else ARM_RANGE) if sequence else (MAC_RECORD if mac else ARM_RECORD)
    if stacked:spec=MAC_STACK_RECORD
    code,fields=expand(spec)
    for key,(at,n) in fields.items():
        if key.startswith('call') or key in ['allocate','payload','insert']:
            target=start+512
            if mac: raw=struct.pack('<i',target-start-at-4)
            else:
                blx=key!=('call_74' if sequence else 'call_5a')
                raw=bytearray(branch(((start+at+4)&~3)-4 if blx else start+at,target))
                if blx:raw[3]&=~0x10
        elif key.startswith('outside'):raw=struct.pack('<i',start+600-start-at-4)
        elif key.startswith('value'):
            value,reg,top=({'value_16':5,'value_28':900,'value_30':42}[key],{'value_16':0,'value_28':2,'value_30':3}[key],False) if sequence else ({'value_e':5,'value_1e':900,'value_26':7,'value_2a':42}[key],{'value_e':0,'value_1e':2,'value_26':2,'value_2a':3}[key],key=='value_26')
            raw=arm_wide(value,reg,top)
        elif key=='stack':raw=struct.pack('<i',-0x2c00)
        else:
            value=({'count_d':2,'count_7c':3,'base_31':900,'base_41':42}[key] if sequence else {'texture':900,'region':7,'id':42}[key])
            raw=value.to_bytes(n,'little')
        assert len(raw)==n;code[at:at+n]=raw
    data=bytes(64)+code+bytes(1024-len(code))
    text={'name':b'__text','segment':b'__TEXT','address':start,'offset':64,'length':1024}
    return SimpleNamespace(data=data,text=text,sections=[text],slice_offset=4096,architecture='x86_64' if mac else 'armv7'),fields,len(code)


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class ImageRegions(unittest.TestCase):
    def test_records_and_ranges_survive_relocation(self):
        for mac in [True,False]:
            for sequence in [False,True]:
                for relocation in [0,0x23000]:
                    mach,_,size=fixture(mac,sequence,relocation);data=extract_image_bindings(mach)
                    self.assertTrue(data,(mac,sequence))
                    row=data['ranges' if sequence else 'records'][0]
                    self.assertEqual(row['source_offset'],4160)
                    self.assertEqual(row['source_bytes'],size)
                    if sequence:self.assertEqual([row[k] for k in ['first_id','first_texture_id','count','region']],[42,900,3,0])
                    else:self.assertEqual([row[k] for k in ['id','texture_id','region']],[42,900,7])

    def test_invalid_allocation_copy_and_range_bounds(self):
        for mac in [True,False]:
            for sequence in [False,True]:
                for bad in ['allocate','copy','truncated','range']:
                    if bad=='range' and not sequence:continue
                    with self.subTest(mac=mac,sequence=sequence,bad=bad):
                        mach,fields,size=fixture(mac,sequence);data=bytearray(mach.data)
                        if bad=='allocate':
                            key=('call_2a' if mac else 'call_20') if sequence else ('payload' if mac else 'call_18')
                            at,n=fields[key];data[64+at]^=1
                        elif bad=='copy':
                            if sequence:data[64+size-1]^=1
                            else:
                                pattern=bytes.fromhex('48894310' if mac else 'd060')
                                at=data.find(pattern,64,64+size);self.assertGreaterEqual(at,0);data[at]^=1
                        elif bad=='truncated':mach.text['length']=size-1
                        else:
                            key='count_d' if mac else 'count_7c';at,n=fields[key]
                            data[64+at:64+at+n]=(-1 if mac else 0).to_bytes(n,'little',signed=mac)
                        mach.data=bytes(data)
                        self.assertEqual(extract_image_bindings(mach),{})

    def test_conflicting_record_alternatives_are_retained(self):
        for mac in [True,False]:
            mach,fields,size=fixture(mac);data=bytearray(mach.data);second=bytearray(data[64:64+size])
            if mac:
                at,n=fields['region'];second[at:at+n]=(8).to_bytes(n,'little')
            else:
                at,n=fields['value_26'];second[at:at+n]=arm_wide(8,2,True)
            data[320:320+size]=second;mach.data=bytes(data)
            rows=extract_image_bindings(mach)['records']
            self.assertEqual([(r['id'],r['region']) for r in rows],[(42,7),(42,8)])

if __name__=='__main__':unittest.main()
