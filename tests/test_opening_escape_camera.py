import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import opening_escape_camera as reader


def variants():
    return [*reader.LAYOUTS.items(), ('x86_64', reader.MAC_ALTERNATE)]


def fixture(arch, shift=0, rows=None):
    rows=reader.LAYOUTS[arch] if rows is None else rows
    mach,origin,offset,low=literal_fixture(arch,rows,shift,[k for k in rows if k.endswith('_constant')])
    staging={'escape':{'present':True},'provenance':{'initial':{'offset':origin,'bytes':366 if arch=='x86_64' else 320}}}
    actors={}
    return mach,staging,actors,offset,low


class OpeningEscapeCameraTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only_output(self):
        for arch,rows in variants():
            for shift in [0,0x700000]:
                m,s,a,*_=fixture(arch,shift,rows);data=reader.extract_opening_escape_camera(m,s)
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],s['provenance']['initial']['offset']+rows[key][0])

    def test_every_changed_span_and_truncation(self):
        for arch,rows in variants():
            m,s,a,offset,low=fixture(arch,rows=rows)
            for key,(delta,_,_) in rows.items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_opening_escape_camera(bad,s),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_opening_escape_camera(m,s))

    def test_parent_capabilities_and_section_boundaries(self):
        for arch,rows in variants():
            for key in ['escape','origin','size','section','arch']:
                m,s,a,*_=fixture(arch,rows=rows)
                if key in ['escape']:s[key]={}
                elif key=='origin':s['provenance']['initial']['offset']+=2
                elif key=='size':s['provenance']['initial']['bytes']+=1
                elif key=='section':m.sections[0]['segment']=b'__DATA'
                else:m.architecture='unsupported'
                self.assertFalse(reader.extract_opening_escape_camera(m,s),key)
