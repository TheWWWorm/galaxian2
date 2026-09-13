"""Synthetic lookup code and color data, independent of proprietary fixtures."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import environment_colors as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac,shift=0):
    base=0x100000+shift;data=bytearray(12000);blocks={}
    locations={'sun':64,'planet':256 if mac else 1500,'rim':768}
    if not mac:locations['planet_table']=512
    getters={'system':2200,'sky_index':2240,'station':2280,'planet_type':2320}
    tables={'sun_rgb':8192,'planet_rgb':8500,'rim_rgb':8900}
    refs={'sun':{'ref_21':'sun_rgb'},'planet':{'ref_24':'planet_rgb'},'rim':{'ref_0':'rim_rgb'}}
    links={'sun':{'call_a':'system','call_12':'sky_index','bl_e':'system','bl_12':'sky_index'},'planet':{'call_a':'station','call_12':'planet_type','bl_2':'station','bl_6':'planet_type'}}
    for key,at in locations.items():
        name=('MAC_' if mac else 'ARM_')+key.upper();body,fields=expand(getattr(reader,name))
        for field,(off,size) in fields.items():
            site=base+at+off
            if mac:
                dest=base+(getters.get(links.get(key,{}).get(field),2400) if field.startswith('call') else tables.get(refs.get(key,{}).get(field),9400))
                raw=struct.pack('<i',dest-site-size)
            elif field.startswith('bl'):raw=branch(site,base+getters.get(links.get(key,{}).get(field),2400))
            elif field.startswith('b_'):raw=struct.pack('<H',0xe000|(((base+512-site-4)//2)&2047))
            elif field.startswith('vldr'):raw=bytes.fromhex('1fed0dba')
            else:
                target,pc=(tables['sun_rgb'],0x30) if key=='sun' and field in ['movw_1e','movt_26'] else (tables['planet_rgb'],0xe) if key=='planet_table' else (tables['rim_rgb'],0x10) if key=='rim' else (9400,0xc)
                relative=(target-at-pc)&0xffffffff;meta=reader.ARM_FIELDS[name][field]
                raw=arm_wide(relative>>16 if meta['kind']=='movt' else relative&65535,int(meta['register'][1:]),meta['kind']=='movt')
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body;blocks[key]=(at,body,fields)
    raw_getters=({'system':'554889e5488b87280200005dc3','sky_index':'554889e58b473c5dc3','station':'554889e5488b87180200005dc3','planet_type':'554889e58b471c5dc3'} if mac else {'system':'d0f890017047','sky_index':'006b7047','station':'d0f888017047','planet_type':'40697047'})
    for name,raw in raw_getters.items():data[256+getters[name]:256+getters[name]+len(bytes.fromhex(raw))]=bytes.fromhex(raw)
    expected={}
    for index,(key,count) in enumerate(reader.COUNTS.items()):
        expected[key]=[[float(index+1),float(i)/32,2.0] for i in range(count)]
        raw=b''.join(struct.pack('<3f',*row) for row in expected[key]);at=256+tables[key];data[at:at+len(raw)]=raw
    text={'name':b'__text','segment':b'__TEXT','address':base,'offset':256,'length':4096}
    const={'name':b'__const','segment':b'__TEXT','address':base+8192,'offset':256+8192,'length':2048}
    m=SimpleNamespace(architecture='x86_64' if mac else 'armv7',data=bytes(data),slice_offset=16384,text=text,sections=[text,const])
    sky={'provenance':{'system':{'offset':16384+256+getters['system']}}}
    return m,sky,blocks,expected


class EnvironmentColors(unittest.TestCase):
    def test_relocated_independent_tables(self):
        for mac in [True,False]:
            for shift in [0,0x250000]:
                m,sky,_,expected=fixture(mac,shift);result=reader.extract_environment_colors(m,sky)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({key:result[key] for key in expected},expected)
                self.assertEqual(result['provenance']['sun_rgb'],{'offset':24832,'bytes':228})

    def test_invalid_contexts_and_tables(self):
        for mac in [True,False]:
            for bad in ['sun','planet','rim','system','getter','duplicate','negative','nan','infinity','oversized','missing','extent','link','overlap']:
                with self.subTest(mac=mac,bad=bad):
                    m,sky,blocks,_=fixture(mac);data=bytearray(m.data)
                    if bad in ['sun','planet','rim']:data[256+blocks[bad][0]+(8 if bad=='sun' and not mac else 0)]^=1
                    elif bad=='system':sky['provenance']['system']['offset']+=4
                    elif bad=='getter':data[256+2320]^=1
                    elif bad=='duplicate':
                        _,body,_=blocks['sun'];data[256+1100:256+1100+len(body)]=body
                    elif bad in ['negative','nan','infinity','oversized']:
                        data[256+8192:256+8196]=struct.pack('<f',{'negative':-1,'nan':float('nan'),'infinity':float('inf'),'oversized':17}[bad])
                    elif bad=='missing':sky={}
                    elif bad=='extent':m.sections[1]['length']=512
                    else:
                        at,_,fields=blocks['planet' if bad=='link' else 'rim'];field=('call_12' if mac else 'bl_6') if bad=='link' else ('ref_0' if mac else 'movw_0');off,size=fields[field];site=m.text['address']+at+off
                        dest=m.text['address']+(2240 if bad=='link' else 8192)
                        raw=(struct.pack('<i',dest-site-4) if mac else branch(site,dest)) if bad=='link' else struct.pack('<i',dest-site-4) if mac else arm_wide((8192-at-0x10)&65535,0,False)
                        data[256+at+off:256+at+off+size]=raw
                    m.data=bytes(data);self.assertEqual(reader.extract_environment_colors(m,sky),{})
