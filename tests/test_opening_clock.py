import importlib.util
import struct
import unittest
from types import SimpleNamespace
from gof2_content import opening_clock as reader
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    base=0x100000+relocation; data=bytearray(8192)
    text={'segment':b'__TEXT','name':b'__text','address':base,'offset':256,'length':7000}
    m=SimpleNamespace(architecture='x86_64' if mac else 'armv7',text=text,sections=[text],slice_offset=0)
    blocks={}; prefix='MAC_' if mac else 'ARM_'
    for index,key in enumerate(['reset','frame']):
        body,fields=expand(getattr(reader,prefix+key.upper())); blocks[key]=(body,fields)
        for field,(off,size) in fields.items():
            site=base+index*1024+off
            if field.startswith('call_'): raw=int(base+3000-site-size).to_bytes(size,'little',signed=True) if mac else branch(site,base+3000)
            elif field.startswith('ref_'): raw=int(base+6000-site-size).to_bytes(size,'little',signed=True)
            elif field=='seed': raw=struct.pack('<i',12) if mac else bytes.fromhex('0023')
            else:
                meta=reader.ARM_FIELDS[prefix+key.upper()][field]
                raw=arm_wide(1,int(meta['register'][1:]),meta['kind']=='movt')
            body[off:off+size]=raw
        data[256+index*1024:256+index*1024+len(body)]=body
    raw=reader.MAC_ADD if mac else reader.ARM_ADD;data[3256:3256+len(raw)]=raw
    raw=bytes.fromhex('554889e5488b87480200005dc3' if mac else 'd0e969017047');data[4256:4256+len(raw)]=raw
    m.data=bytes(data)
    return m,{'provenance':{'elapsed_getter':{'offset':4256,'bytes':len(raw)}}},blocks


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class OpeningClock(unittest.TestCase):
    def test_relocated_reset_and_increment(self):
        for mac in [True,False]:
            for relocation in [0,0x90000]:
                m,drift,_=fixture(mac,relocation)
                result=reader.extract_opening_clock(m,drift,{'ship_id':1})
                self.assertTrue(result)
                self.assertEqual(result['initial_elapsed_ms'],12 if mac else 0)
                self.assertTrue(result['advance_before_controller'])

    def test_corrupt_context(self):
        for mac in [True,False]:
            for bad in ['reset','frame','increment','getter','link','seed','missing','extent','duplicate','truncated']:
                with self.subTest(mac=mac,bad=bad):
                    m,drift,blocks=fixture(mac);data=bytearray(m.data)
                    if bad in ['reset','frame','increment','getter']:
                        off={'reset':256 if mac else 270,'frame':1280 if mac else 1292,'increment':3256,'getter':4256}[bad];data[off]^=1
                    elif bad=='link': data[1280+blocks['frame'][1]['call_e' if mac else 'call_1e'][0]]^=2
                    elif bad=='seed':
                        off,size=blocks['reset'][1]['seed'];data[256+off:256+off+size]=struct.pack('<i',-1) if mac else bytes.fromhex('0123')
                    elif bad=='missing': drift={}
                    elif bad=='extent': drift['provenance']['elapsed_getter']['offset']+=1
                    elif bad=='duplicate':
                        raw=blocks['reset'][0];data[6000:6000+len(raw)]=raw
                    elif bad=='truncated':data=data[:3260]
                    m.data=bytes(data)
                    self.assertEqual(reader.extract_opening_clock(m,drift,{'ship_id':1}),{})

if __name__=='__main__':unittest.main()
