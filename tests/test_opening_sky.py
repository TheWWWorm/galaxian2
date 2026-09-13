"""Synthetic compiler contexts with independently relocated resource IDs."""
import struct
import unittest
from types import SimpleNamespace
from gof2_content import opening_sky as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    base=0x100000+relocation; data=bytearray(4096); blocks={}; prefix='MAC_' if mac else 'ARM_'
    star_size=len(expand(getattr(reader,prefix+'STARS'))[0])
    locations={'stars':64,'opening':64+star_size,'texture':700}
    targets={'system':1600,'system_id':1640,'cursor':1680,'mesh':1800,'texture':1840}
    calls=({'stars':{'call_b':'system','call_13':'system_id','call_47':'mesh','call_5a':'system','call_62':'system_id','call_99':'texture'},
            'opening':{'call_4':'cursor','call_2e':'mesh'},'texture':{'call_2':'texture'}} if mac else
           {'stars':{'call_8':'system','call_10':'system_id','call_42':'mesh','call_50':'system','call_58':'system_id','call_82':'texture'},
            'opening':{'call_6':'cursor','call_2a':'mesh'},'texture':{'call_2':'texture'}})
    for key,at in locations.items():
        body,fields=expand(getattr(reader,prefix+key.upper()))
        for field,(off,size) in fields.items():
            site=base+at+off
            if field.startswith(('call','jump','ref')):
                dest=base+(700 if field.startswith('jump') else targets[calls[key][field]] if field.startswith('call') else 1900)
                raw=(struct.pack('<i',dest-site-size) if mac else
                     struct.pack('<H',0xe000|(((dest-site-4)//2)&2047)) if size==2 else branch(site,dest))
            elif mac: raw=struct.pack('<I',300 if key=='opening' and field=='id_24' else 400 if key=='opening' else 100 if field=='id_38' else 200)
            else:
                meta=reader.ARM_FIELDS[prefix+key.upper()][field]
                value=(0x5556 if field=='word_18' else 0x5555 if field=='word_20' else 100 if field=='word_38' else 200) if key=='stars' else 300 if field=='word_1e' else 400
                register=11 if meta['register']=='fp' else int(meta['register'][1:])
                raw=arm_wide(value,register,meta['kind']=='movt')
            body[off:off+size]=raw
        data[256+at:256+at+len(body)]=body; blocks[key]=(at,body,fields)
    getters=({'system':'554889e5488b87280200005dc3','system_id':'554889e58b47205dc3','cursor':'554889e58b87780200005dc3'} if mac else
             {'system':'d0f890017047','system_id':'40697047','cursor':'d0f8d4017047'})
    for key,raw in getters.items():
        body=bytes.fromhex(raw); at=targets[key];data[256+at:256+at+len(body)]=body
    text={'name':b'__text','segment':b'__TEXT','address':base,'offset':256,'length':2048}
    m=SimpleNamespace(architecture='x86_64' if mac else 'armv7',data=bytes(data),slice_offset=8192,text=text,sections=[text])
    projection={'provenance':{'cursor':{'offset':8192+256+1680,'bytes':len(bytes.fromhex(getters['cursor']))}}}
    return m,projection,blocks


class OpeningSky(unittest.TestCase):
    def test_changed_ids_and_relocation(self):
        for mac in [True,False]:
            for shift in [0,0x180000]:
                m,projection,_=fixture(mac,shift); result=reader.extract_opening_sky(m,projection)
                self.assertTrue(result,(mac,shift))
                self.assertEqual([result[k] for k in ['star_mesh_base','star_texture_base','sky_mesh_id','sky_texture_id']],[100,200,300,400])
                self.assertEqual(result['star_variants'],3)
                self.assertFalse(result['location_match'])
                self.assertEqual(result['provenance']['stars']['offset'],8512)

    def test_rejects_corruption_and_unlinked_calls(self):
        for mac in [True,False]:
            for bad in ['stars','opening','texture','cursor','system','duplicate','link','modulo','id','missing']:
                with self.subTest(mac=mac,bad=bad):
                    m,p,blocks=fixture(mac); data=bytearray(m.data)
                    if bad in ['stars','opening','texture']:data[256+blocks[bad][0]]^=1
                    elif bad=='cursor':p['provenance']['cursor']['offset']+=4
                    elif bad=='system':data[256+1600]^=1
                    elif bad=='duplicate':
                        _,body,_=blocks['stars'];data[256+1100:256+1100+len(body)]=body
                    elif bad=='missing':p={}
                    else:
                        at,_,fields=blocks['stars']
                        field=('call_47' if mac else 'call_42') if bad=='link' else ('id_38' if mac else 'word_38') if bad=='id' else 'word_18' if not mac else None
                        if field is None:
                            data[256+at+0x20]^=1
                        else:
                            off,size=fields[field];site=m.text['address']+at+off
                            raw=(struct.pack('<i',1900-at-off-size) if mac else branch(site,m.text['address']+1900)) if bad=='link' else (struct.pack('<I',65535) if mac else arm_wide(65535 if bad=='id' else 0x5557,1 if bad=='id' else 11,False))
                            data[256+at+off:256+at+off+size]=raw
                    m.data=bytes(data)
                    self.assertEqual(reader.extract_opening_sky(m,p),{})
