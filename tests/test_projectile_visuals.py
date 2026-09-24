import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import projectile_visuals as reader


def variants():
    return [*reader.LAYOUTS.items(), ('x86_64', reader.MAC_ALTERNATE)]


def fixture(arch, shift=0, rows=None):
    rows=reader.LAYOUTS[arch] if rows is None else rows
    constants=['model_2','model_19']+[k for k in rows if k.endswith('_constant')] if arch=='x86_64' else ['model_2','model_19']
    mach,origin,offset,low=literal_fixture(arch,rows,shift,constants)
    staging={'provenance':{'initial':{'offset':origin}},'player_flight':{'verified':True}}
    actors={'npc_initialization':{'primary_weapon':{'item_id':19}}}
    return mach,staging,actors,{'ship_id':10},offset,low


class ProjectileVisualTests(unittest.TestCase):
    def test_profiles_relocation_and_data_only_output(self):
        for arch,rows in variants():
            for shift in [0,0x700000]:
                args=fixture(arch,shift,rows);data=reader.extract_projectile_visuals(*args[:4])
                self.assertEqual({k:v for k,v in data.items() if k!='provenance'},reader.VALUES)
                for key,span in data['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],args[1]['provenance']['initial']['offset']+rows[key][0])

    def test_every_changed_span_and_truncation(self):
        for arch,rows in variants():
            m,s,a,o,offset,low=fixture(arch,rows=rows)
            for key,(delta,_,_) in rows.items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_projectile_visuals(bad,s,a,o),key)
            m.data=m.data[:offset+16]
            self.assertFalse(reader.extract_projectile_visuals(m,s,a,o))

    def test_scope_and_section_boundaries(self):
        for arch,rows in variants():
            for key in ['player','npc','ship','origin','section','arch']:
                m,s,a,o,*_=fixture(arch,rows=rows)
                if key=='player':s['player_flight']={}
                elif key=='npc':a['npc_initialization']['primary_weapon']['item_id']=18
                elif key=='ship':o['ship_id']=9
                elif key=='origin':s['provenance']['initial']['offset']+=2
                elif key=='section':m.sections[1]['segment']=b'__DATA'
                else:m.architecture='unsupported'
                self.assertFalse(reader.extract_projectile_visuals(m,s,a,o),key)
