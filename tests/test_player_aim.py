import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import player_aim as reader


def variants():
    return [*reader.LAYOUTS.items(), ('x86_64', reader.MAC_ALTERNATE)]


def fixture(arch, shift=0, rows=None):
    rows=reader.LAYOUTS[arch] if rows is None else rows
    constants=[k for k in rows if k.endswith('_constant')]
    mach,origin,offset,low=literal_fixture(arch,rows,shift,constants)
    staging={'provenance':{'initial':{'offset':origin}},'player_flight':{'verified':True},'player_motion':{'verified':True},'projectile_impacts':{'verified':True}}
    return mach,staging,{'verified':True},offset,low


class PlayerAimTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only_output(self):
        for arch,rows in variants():
            for shift in [0,0x700000]:
                args=fixture(arch,shift,rows);data=reader.extract_player_aim(*args[:3])
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],args[1]['provenance']['initial']['offset']+rows[key][0])

    def test_every_changed_span_and_truncation(self):
        for arch,rows in variants():
            m,s,p,offset,low=fixture(arch,rows=rows)
            for key,(delta,_,_) in rows.items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_player_aim(bad,s,p),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_player_aim(m,s,p))

    def test_dependencies_and_section_boundaries(self):
        for arch,rows in variants():
            for key in ['player_flight','player_motion','projectile_impacts','projection','origin','section','arch']:
                m,s,p,*_=fixture(arch,rows=rows)
                if key in s:s[key]={}
                elif key=='projection':p={}
                elif key=='origin':s['provenance']['initial']['offset']+=2
                elif key=='section':m.sections[-1]['segment']=b'__DATA'
                else:m.architecture='unsupported'
                self.assertFalse(reader.extract_player_aim(m,s,p),key)
