"""Relocated compiler-layout fixtures without supplied archives or assets."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import npc_destruction as reader
from gof2_content.opening_npc_guidance import LAYOUTS as GUIDANCE


def fixture(arch, shift=0):
    layouts=reader.LAYOUTS[arch]
    low=min(row[0] for row in layouts.values())-64
    high=max(row[0]+row[1] for row in layouts.values())+64
    offset=128;origin=0x400000+shift;bias=4096
    data=bytearray(offset+high-low)
    for delta,size,raw in layouts.values():data[offset+delta-low:offset+delta-low+size]=bytes.fromhex(raw)
    # Constants share the image mapping but belong to their named section.
    constants=[row[0] for key,row in layouts.items() if key in ['spin_constant','drift_multiplier','drift_base']] if arch=='x86_64' else []
    split=min(constants) if constants else high
    text={'segment':b'__TEXT','name':b'__text','address':origin,'offset':offset,'length':split-low}
    sections=[text]
    if constants:sections.append({'segment':b'__TEXT','name':b'__const','address':origin+split-low,'offset':offset+split-low,'length':high-split})
    m=SimpleNamespace(architecture=arch,slice_offset=bias,data=bytes(data),text=text,sections=sections)
    _,relative,size,_=GUIDANCE[arch]['selection']
    actors={'npc_initialization':{'guidance':{'actor_kind':8,'provenance':{'selection':{'offset':bias+offset+relative-low,'bytes':size}}},'construction':{'verified':True}}}
    return m,actors,offset,low


class DestructionTests(unittest.TestCase):
    def test_both_relocated_layouts(self):
        for arch in reader.LAYOUTS:
            for shift in [0,0x800000]:
                m,actors,*_=fixture(arch,shift)
                result=reader.extract_npc_destruction(m,actors)
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),len(reader.LAYOUTS[arch]))
                result['model_ids'].clear()
                self.assertEqual(reader.VALUES['model_ids'],[16821,16820])

    def test_changed_layouts_and_truncation(self):
        for arch in reader.LAYOUTS:
            m,actors,offset,low=fixture(arch)
            for key,(delta,_,_) in reader.LAYOUTS[arch].items():
                bad=copy.copy(m);raw=bytearray(m.data);raw[offset+delta-low]^=255;bad.data=bytes(raw)
                self.assertFalse(reader.extract_npc_destruction(bad,actors),(arch,key))
            bad=copy.copy(m);bad.data=m.data[:offset+10]
            self.assertFalse(reader.extract_npc_destruction(bad,actors))

    def test_missing_or_moved_anchor(self):
        for arch in reader.LAYOUTS:
            m,actors,*_=fixture(arch)
            for change in ['kind','selection','construction']:
                bad=copy.deepcopy(actors);npc=bad['npc_initialization']
                if change=='kind':npc['guidance']['actor_kind']=9
                elif change=='selection':npc['guidance']['provenance']['selection']['offset']+=2
                else:npc['construction']={}
                self.assertFalse(reader.extract_npc_destruction(m,bad))
