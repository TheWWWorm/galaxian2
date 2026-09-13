"""Relocated synthetic flare declarations; no original assets or tables."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import sun_flares as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch

COLORS=[[70,71,69],[73,72,74],[76,75,77],[64,67,68],[79,80,78],[64,65,66]]

def fixture(mac,shift=0):
    base=0x100000+shift;data=bytearray(12000);blocks={}
    locations={'resources':64,'system_type':256,'palette':512}
    if not mac:locations['fallback']=512+0x48
    getters={'system':2000,'system_id':2040}
    tables={'system_types':8192,'red':8400,'green':8500,'blue':8600,'palette_selectors':2500}
    for key,at in locations.items():
        name=('MAC_' if mac else 'ARM_')+key.upper();body,fields=expand(getattr(reader,name));color_index=0
        for field,(off,size) in fields.items():
            site=base+at+off
            if mac:
                if field.startswith('value_'):raw=struct.pack('<I',64+color_index);color_index+=1
                elif field.startswith('id_'):raw=struct.pack('<I',200)
                else:
                    dest=2200
                    if key=='system_type':dest=getters['system' if field=='call_6' else 'system_id'] if field.startswith('call') else tables['system_types']
                    elif key=='palette':dest=tables['palette_selectors']
                    raw=struct.pack('<i',base+dest-site-size)
            else:
                kind,register=reader.ARM_FIELDS[name][field]
                reg={'fp':11,'sl':10}.get(register,int(register[1:]) if register and register.startswith('r') else 0)
                if kind=='bl':
                    dest=getters['system' if field=='bl_4' else 'system_id'] if key=='system_type' else 2200
                    raw=branch(site,base+dest)
                elif kind=='add.w':raw=struct.pack('<HH',0xf106,0x01c8)
                elif kind=='mov.w':raw=struct.pack('<HH',0xf04f,(reg<<8)+COLORS[5][{10:0,8:1,11:2}[reg]])
                else:
                    if key=='system_type':dest=tables['system_types'];pc=0x1a
                    elif key=='palette':
                        group={'r0':('red',0x20),'r1':('green',0x22),'r2':('blue',0x24)}[register]
                        dest=tables[group[0]];pc=group[1]
                    else:dest=2300;pc=14
                    relative=(dest-at-pc)&0xffffffff
                    value=relative>>16 if kind=='movt' else relative&65535
                    raw=arm_wide(value,reg,kind=='movt')
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body;blocks[key]=(at,body,fields)
    raws={'system':'554889e5488b87280200005dc3','system_id':'554889e58b47205dc3'} if mac else {'system':'d0f890017047','system_id':'40697047'}
    for key,raw in raws.items():data[256+getters[key]:256+getters[key]+len(bytes.fromhex(raw))]=bytes.fromhex(raw)
    for index in range(3):
        at=2800+index*128;body,fields=expand(reader.MAC_IMAGE if mac else reader.ARM_IMAGE)
        for field,(off,size) in fields.items():
            if mac:
                if field.startswith('call'):raw=struct.pack('<i',2200-at-off-size)
                elif field.startswith('slot'):raw=struct.pack('<i',-800+index*8)
                else:raw=struct.pack('<H',{'value_17':4000+index,'value_1c':10+index,'value_22':200+index}[field])
            elif field=='blx_2':
                raw=bytearray(branch((base+at+off)&~3,base+2200));raw[3]&=~0x10
            elif field.startswith('number'):
                raw=arm_wide({'number_8':4000+index,'number_10':10+index,'number_14':200+index}[field],3 if field=='number_14' else 2,field=='number_10')
            else:raw=struct.pack('<HH',0xf8d5,((1 if field=='ldr_w_1c' else 2)<<12)+0x120+index*4)
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body;blocks['image_'+str(index)]=(at,body,fields)
    values=[i%6 for i in range(34)]
    data[256+8192:256+8192+136]=struct.pack('<34I',*values)
    if mac:
        offsets=[512+v-2500 for v in [0x37,0x4a,0x5d,0x81,0x70]]
        data[256+2500:256+2520]=struct.pack('<5i',*offsets)
    else:
        for index,key in enumerate(['red','green','blue']):
            at=256+tables[key];data[at:at+20]=struct.pack('<5I',*(row[index] for row in COLORS[:5]))
    text={'name':b'__text','segment':b'__TEXT','address':base,'offset':256,'length':4096}
    const={'name':b'__const','segment':b'__TEXT','address':base+8192,'offset':256+8192,'length':2048}
    mach=SimpleNamespace(architecture='x86_64' if mac else 'armv7',data=bytes(data),slice_offset=16384,text=text,sections=[text,const])
    sky={'provenance':{key:{'offset':16384+256+at} for key,at in getters.items()}}
    expected={'scope':'ordinary_sun_flares','image_ids':[200,201,202],'images':[{'id':200+i,'texture_id':4000+i,'region':10+i} for i in range(3)],'system_types':values,'colors':COLORS}
    return mach,sky,blocks,expected

class SunFlares(unittest.TestCase):
    def test_relocated_changed_data(self):
        for mac in [True,False]:
            for shift in [0,0x350000]:
                m,sky,_,expected=fixture(mac,shift);result=reader.extract_sun_flares(m,sky)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({key:result[key] for key in expected},expected)

    def test_fail_closed(self):
        for mac in [True,False]:
            for bad in ['resources','system_type','palette','image_0','image_1','image_2','duplicate','duplicate_image','getter','link','types','color','truncated','missing','selector']:
                with self.subTest(mac=mac,bad=bad):
                    m,sky,blocks,_=fixture(mac);data=bytearray(m.data)
                    if bad in blocks:data[256+blocks[bad][0]+(8 if bad=='resources' and not mac else 0)]^=1
                    elif bad=='duplicate':
                        body=blocks['resources'][1];data[256+1000:256+1000+len(body)]=body
                    elif bad=='duplicate_image':
                        body=blocks['image_0'][1];data[256+1600:256+1600+len(body)]=body
                    elif bad=='getter':data[256+2040]^=1
                    elif bad=='link':sky['provenance']['system_id']['offset']+=4
                    elif bad=='types':struct.pack_into('<I',data,256+8192,6)
                    elif bad=='color':
                        if mac:
                            at,_,fields=blocks['palette'];off,_=fields['value_0'];struct.pack_into('<I',data,256+at+off,256)
                        else:struct.pack_into('<I',data,256+8400,256)
                    elif bad=='truncated':m.sections[1]['length']=135
                    elif bad=='missing':sky={}
                    elif mac:struct.pack_into('<i',data,256+2500,1)
                    else:data[256+512+0x48]=0
                    m.data=bytes(data)
                    self.assertEqual(reader.extract_sun_flares(m,sky),{})
