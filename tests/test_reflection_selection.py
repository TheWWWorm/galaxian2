"""Independent identifiers and relocated linked contexts; no proprietary fixture."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import reflection_selection as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac,shift=0):
    base=0x100000+shift;data=bytearray(10000);blocks={};locations={'select':64,'bind':512}
    links=({'call_a':1800,'call_2f':1900,'call_37':2000,'call_4d':3000,'call_59':512} if mac else {'call_14':1800,'call_30':1900,'call_36':2000,'call_4a':3000,'call_5a':512})
    for key,at in locations.items():
        name=('MAC_' if mac else 'ARM_')+key.upper();body,fields=expand(getattr(reader,name))
        for field,(off,size) in fields.items():
            site=base+at+off
            if mac:
                if field in ['texture_base','special_id']:raw=struct.pack('<I',22000 if field=='texture_base' else 31000)
                else:raw=struct.pack('<i',base+(links.get(field,3000) if key=='select' and field.startswith('call_') else 3000)-site-size)
            else:
                meta=reader.ARM_FIELDS[name][field];kind=meta['kind']
                if field.startswith('call_'):
                    target=base+(links.get(field,3000) if key=='select' else 3000)
                    raw=bytearray(branch(((site+4)&~3)-4 if kind=='blx' else site,target))
                    if kind=='blx':raw[3]&=~0x10
                else:raw=arm_wide(22000 if field=='texture_base' else 31000 if field=='special_id' else 0,int(meta['register'][1:]),kind=='movt')
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body;blocks[key]=(at,body,fields)
    data[256+2000:256+2000+(9 if mac else 4)]=bytes.fromhex('554889e58b473c5dc3' if mac else '006b7047')
    data[256+1600:256+1600+(7 if mac else 6)]=(bytes.fromhex('31c9e8')+struct.pack('<i',3000-1607)) if mac else bytes.fromhex('0023')+branch(base+1602,base+3000)
    section={'name':b'__text','segment':b'__TEXT','address':base,'offset':256,'length':8192}
    m=SimpleNamespace(architecture='x86_64' if mac else 'armv7',slice_offset=16384,data=bytes(data),text=section,sections=[section])
    def provenance(offset,size):return {'offset':16384+256+offset,'bytes':size}
    projection={'provenance':{'predicate':provenance(1800,26 if mac else 10)}}
    sky={'provenance':{'system':provenance(1900,13 if mac else 6),'texture':provenance(1600,7 if mac else 6)}}
    return m,projection,sky,blocks


class ReflectionSelection(unittest.TestCase):
    def test_identifiers_and_relocation(self):
        for mac in [True,False]:
            for shift in [0,0x240000]:
                m,p,s,_=fixture(mac,shift);result=reader.extract_reflection_selection(m,p,s)
                self.assertEqual({k:result.get(k) for k in ['texture_base','special_id']},{'texture_base':22000,'special_id':31000})
                self.assertEqual(result['provenance']['select'],{'offset':16704,'bytes':94})
                self.assertEqual(result['provenance']['bind']['bytes'],330 if mac else 240)

    def test_reject_unsupported_or_unlinked_context(self):
        for mac in [True,False]:
            for bad in ['select','bind','getter','duplicate','predicate','system','load','missing','extent','identifier','bind_link','helper_link','global_link']:
                if not mac and bad=='global_link':continue
                with self.subTest(mac=mac,bad=bad):
                    m,p,s,blocks=fixture(mac);data=bytearray(m.data)
                    if bad in ['select','bind']:data[256+blocks[bad][0]+(12 if bad=='select' and not mac else 0)]^=1
                    elif bad=='getter':data[256+2000]^=1
                    elif bad=='duplicate':
                        _,body,_=blocks['select'];data[256+1024:256+1024+len(body)]=body
                    elif bad=='predicate':p['provenance']['predicate']['offset']+=4
                    elif bad=='system':s['provenance']['system']['offset']+=4
                    elif bad=='load':data[256+1600]^=1
                    elif bad=='missing':p={}
                    elif bad=='extent':m.text['length']=100
                    else:
                        key='bind' if bad=='helper_link' else 'select'
                        field=('call_8b' if mac else 'call_50') if bad=='helper_link' else 'texture_base' if bad=='identifier' else 'ref_25' if bad=='global_link' else ('call_59' if mac else 'call_5a')
                        at,_,fields=blocks[key];off,size=fields[field];site=m.text['address']+at+off
                        if bad=='identifier':raw=struct.pack('<I',65534) if mac else arm_wide(65534,1,False)
                        elif mac:raw=struct.pack('<i',m.text['address']+3500-site-size)
                        else:
                            kind=reader.ARM_FIELDS['ARM_'+key.upper()][field]['kind'];raw=bytearray(branch(((site+4)&~3)-4 if kind=='blx' else site,m.text['address']+3500))
                            if kind=='blx':raw[3]&=~0x10
                        data[256+at+off:256+at+off+size]=raw
                    m.data=bytes(data);self.assertEqual(reader.extract_reflection_selection(m,p,s),{})
