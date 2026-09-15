"""Mac staged map/UI aliases; other content profiles are unchanged."""
import struct
from types import SimpleNamespace
import unittest
from gof2_content.image_regions import extract_image_bindings
from test_image_regions import fixture


class MapImageRegions(unittest.TestCase):
    def test_mac_staged_aliases_and_invalid_staging(self):
        for relocation in [0,0x23000]:
            mach,fields,size=fixture(True,relocation=relocation,stacked=True)
            rows=extract_image_bindings(mach)['records']
            self.assertEqual([(r['id'],r['texture_id'],r['region'],r['source_bytes']) for r in rows],[(42,900,7,64)])
            for slot in [0,8,-3,-1024*1024-8]:
                altered=bytearray(mach.data);at,n=fields['stack'];altered[64+at:64+at+n]=struct.pack('<i',slot)
                changed=SimpleNamespace(**vars(mach));changed.data=bytes(altered)
                self.assertEqual(extract_image_bindings(changed),{})
            for field in ['payload','texture']:
                changed=SimpleNamespace(**vars(mach));altered=bytearray(mach.data);at,n=fields[field]
                if field=='payload':altered[64+at]^=1
                else:altered[64+at:64+at+n]=(65535).to_bytes(n,'little')
                changed.data=bytes(altered);self.assertEqual(extract_image_bindings(changed),{})
            mach.text['length']=size-1
            self.assertEqual(extract_image_bindings(mach),{})
