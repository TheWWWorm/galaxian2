"""Synthetic planet lookup contexts and tables, with relocated pointers."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import planet_resources as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac,shift=0):
    base=0x100000+shift;data=bytearray(12000);blocks={}
    locations={'sun':64,'current':256 if mac else 384,'near':384 if mac else 256,'far':512,'mesh':768}
    getters={'system':2000,'sky_index':2040,'cursor':2080,'planet_type':2120}
    tables={'sun_textures':8192,'near_textures':8300,'far_textures':8450}
    links={'sun':{'call_a':'system','bl_a':'system','call_12':'sky_index','bl_10':'sky_index'},'current':{'call_3':'cursor','bl_8':'cursor'},'near':{'call_14':'planet_type','bl_14':'planet_type'},'far':{'call_14':'planet_type','bl_12':'planet_type'}}
    table_fields={'sun':'ref_1a','near':'ref_2d','far':'ref_2d'}
    table_names={'sun':'sun_textures','near':'near_textures','far':'far_textures'}
    for key,at in locations.items():
        name=('MAC_' if mac else 'ARM_')+key.upper();body,fields=expand(getattr(reader,name))
        for field,(off,size) in fields.items():
            site=base+at+off
            if mac:
                if field.startswith('id_'):raw=struct.pack('<I',6010 if key=='mesh' else 6011)
                else:
                    dest=base+(getters.get(links.get(key,{}).get(field),2200) if field.startswith('call') else tables[table_names[key]] if field==table_fields.get(key) else 9400)
                    raw=struct.pack('<i',dest-site-size)
            elif field.startswith('bl_'):raw=branch(site,base+getters.get(links.get(key,{}).get(field),2200))
            else:
                kind,register=reader.ARM_FIELDS[name][field]
                if key in ['current','mesh']:value=6010 if key=='mesh' else 6011
                else:
                    pc={'sun':0x22,'near':0x30,'far':0x2e}[key]
                    relative=(tables[table_names[key]]-at-pc)&0xffffffff
                    value=relative>>16 if kind=='movt' else relative&65535
                raw=arm_wide(value,int(register[1:]),kind=='movt')
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body;blocks[key]=(at,body,fields)
    raws={'system':'554889e5488b87280200005dc3','sky_index':'554889e58b473c5dc3','cursor':'554889e58b87780200005dc3','planet_type':'554889e58b471c5dc3'} if mac else {'system':'d0f890017047','sky_index':'006b7047','cursor':'d0f8d4017047','planet_type':'40697047'}
    for key,raw in raws.items():data[256+getters[key]:256+getters[key]+len(bytes.fromhex(raw))]=bytes.fromhex(raw)
    expected={'scope':'fresh_opening_planet_resources','mesh_id':6010,'opening_texture_id':6011}
    for n,(key,count) in enumerate(reader.COUNTS.items()):
        expected[key]=[20000+n*100+i*3 for i in range(count)]
        start=256+tables[key];data[start:start+4*count]=struct.pack('<'+str(count)+'I',*expected[key])
    text={'name':b'__text','segment':b'__TEXT','address':base,'offset':256,'length':4096}
    const={'name':b'__const','segment':b'__TEXT','address':base+8192,'offset':256+8192,'length':2048}
    mach=SimpleNamespace(architecture='x86_64' if mac else 'armv7',data=bytes(data),slice_offset=16384,text=text,sections=[text,const])
    sky={'provenance':{k:{'offset':16384+256+getters[k]} for k in ['system','cursor']}}
    colors={'provenance':{k:{'offset':16384+256+getters[k]} for k in ['sky_index','planet_type']}}
    return mach,sky,colors,blocks,expected

class PlanetResources(unittest.TestCase):
    def test_relocated_independent_tables(self):
        for mac in [True,False]:
            for shift in [0,0x350000]:
                mach,sky,colors,_,expected=fixture(mac,shift)
                result=reader.extract_planet_resources(mach,sky,colors)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:result[k] for k in expected},expected)
                self.assertEqual(result['provenance']['sun_textures'],{'offset':24832,'bytes':76})

    def test_reject_corrupt_selectors_tables_and_links(self):
        for mac in [True,False]:
            for bad in ['sun','current','near','far','mesh','duplicate','system','cursor','getter','table_id','mesh_id','truncated','missing','register_link','table_overlap']:
                with self.subTest(mac=mac,bad=bad):
                    mach,sky,colors,blocks,_=fixture(mac);data=bytearray(mach.data)
                    if bad in blocks:data[256+blocks[bad][0]]^=1
                    elif bad=='duplicate':
                        body=blocks['sun'][1];data[256+1100:256+1100+len(body)]=body
                    elif bad in ['system','cursor']:sky['provenance'][bad]['offset']+=4
                    elif bad=='getter':data[256+2120]^=1
                    elif bad=='table_id':data[256+8192:256+8196]=struct.pack('<I',65534)
                    elif bad=='mesh_id':
                        at,_,fields=blocks['mesh'];off,size=fields['id_1a' if mac else 'movw_a']
                        data[256+at+off:256+at+off+size]=struct.pack('<I',65534) if mac else arm_wide(65534,1,False)
                    elif bad=='truncated':mach.sections[1]['length']=100
                    elif bad=='missing':colors={}
                    elif bad=='register_link':
                        at,_,fields=blocks['far'];off,size=fields['call_3d' if mac else 'bl_36'];site=mach.text['address']+at+off;dest=mach.text['address']+2250
                        data[256+at+off:256+at+off+size]=struct.pack('<i',dest-site-size) if mac else branch(site,dest)
                    else:
                        at,_,fields=blocks['far'];off,size=fields['ref_2d' if mac else 'movw_1e'];site=mach.text['address']+at+off
                        data[256+at+off:256+at+off+size]=struct.pack('<i',mach.text['address']+8192-site-size) if mac else arm_wide((8192-at-0x2e)&65535,1,False)
                    mach.data=bytes(data)
                    self.assertEqual(reader.extract_planet_resources(mach,sky,colors),{})
