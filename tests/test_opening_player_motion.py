"""Static cinematic motion fixtures: relocation, mutation and dependency links."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import opening_player_motion as reader


def layouts():
    return [*reader.LAYOUTS.items(), ('x86_64', reader.MAC_ALTERNATE)]


def fixture(arch, shift=0, rows=None):
    rows=reader.LAYOUTS[arch] if rows is None else rows
    low=min(r[0] for r in rows.values())-64
    high=max(r[0]+r[1] for r in rows.values())+64
    offset=128;bias=4096
    data=bytearray(offset+high-low)
    for relative,size,pattern in rows.values():data[offset+relative-low:offset+relative-low+size]=bytes.fromhex(pattern)
    text={'segment':b'__TEXT','name':b'__text','address':0x400000+shift,'offset':offset,'length':high-low}
    mach=SimpleNamespace(architecture=arch,slice_offset=bias,data=bytes(data),text=text,sections=[text])
    origin=bias+offset-low
    staging={'provenance':{'initial':{'offset':origin,'bytes':366 if arch=='x86_64' else 320}}}
    camera={'pan':{'follow_player_after_event_finished':8}}
    cruise={'speed_units_per_millisecond':2.0,'forward_axis':[0,0,1],
            'provenance':[{'offset':origin+rows['speed'][0]},{},{},{'offset':origin+rows['forward_helper'][0]}]}
    return mach,staging,camera,cruise,{'player_initialization':{'verified':True}},offset,low


class PlayerMotionTests(unittest.TestCase):
    def test_complete_proofs_must_be_unique_and_links_present(self):
        for arch,rows in layouts():
            m,s,*_=fixture(arch,rows=rows)
            origin=s['provenance']['initial']['offset']
            self.assertFalse(reader.recognize(m,origin,[rows,rows]))
            self.assertFalse(reader.recognize(m,origin,[rows],{'absent':origin}))

    def test_relocated_profiles(self):
        for arch,rows in layouts():
            for shift in [0,0x900000]:
                m,s,c,v,a,*_=fixture(arch,shift,rows)
                result=reader.extract_opening_player_motion(m,s,c,v,a)
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)

    def test_each_changed_span_and_truncation(self):
        for arch,rows in layouts():
            m,s,c,v,a,offset,low=fixture(arch,rows=rows)
            for key,(relative,_,_) in rows.items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+relative-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_opening_player_motion(bad,s,c,v,a),(arch,key))
            bad=copy.copy(m);bad.data=m.data[:offset+10]
            self.assertFalse(reader.extract_opening_player_motion(bad,s,c,v,a))

    def test_disconnected_dependencies(self):
        for arch,rows in layouts():
            for key in ['initial','camera','speed','axis','constructor','helper','player']:
                m,s,c,v,a,*_=fixture(arch,rows=rows)
                if key=='initial':s['provenance']['initial']['offset']+=2
                elif key=='camera':c['pan']['follow_player_after_event_finished']=7
                elif key=='speed':v['speed_units_per_millisecond']=3.0
                elif key=='axis':v['forward_axis']=[0,0,-1]
                elif key=='constructor':v['provenance'][0]['offset']+=2
                elif key=='helper':v['provenance'][3]['offset']+=2
                else:a['player_initialization']={}
                self.assertFalse(reader.extract_opening_player_motion(m,s,c,v,a),key)
