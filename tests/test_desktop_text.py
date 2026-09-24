"""Mac desktop wording variants keep their own bounded substitution tables."""
import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import desktop_text as reader


def variants():
    return [(reader.LAYOUTS,reader.VALUES),(reader.MAC_ALTERNATE,reader.MAC_VALUES)]


def fixture(rows,shift=0):
    mach,origin,offset,low=literal_fixture('x86_64',rows,shift)
    return mach,{'provenance':{'actor':{'offset':origin,'bytes':315}}},offset,low


class DesktopTextTests(unittest.TestCase):
    def test_relocated_source_specific_aliases_and_detachment(self):
        for rows,expected in variants():
            for shift in [0,0x2400000]:
                mach,arrival,*_=fixture(rows,shift)
                value=reader.extract_desktop_text(mach,arrival)
                self.assertEqual({k:v for k,v in value.items() if k!='provenance'},expected)
                self.assertEqual(len(value['pairs']),19 if rows is reader.LAYOUTS else 21)
                value['pairs'].clear()
                self.assertEqual(reader.extract_desktop_text(mach,arrival)['pairs'],expected['pairs'])

    def test_each_source_boundary_and_hybrid_layout_rejected(self):
        for rows,_ in variants():
            mach,arrival,offset,low=fixture(rows)
            for key,(delta,size,_) in rows.items():
                for edge in [0,size-1]:
                    bad=copy.copy(mach);data=bytearray(mach.data);data[offset+delta-low+edge]^=255;bad.data=bytes(data)
                    self.assertEqual(reader.extract_desktop_text(bad,arrival),{},(key,edge))
            other=reader.MAC_ALTERNATE if rows is reader.LAYOUTS else reader.LAYOUTS
            bad=copy.copy(mach);data=bytearray(mach.data)
            delta,size,raw=rows['setter'];replacement=bytes.fromhex(other['setter'][2]);data[offset+delta-low:offset+delta-low+size]=replacement[:size].ljust(size,b'\0');bad.data=bytes(data)
            self.assertEqual(reader.extract_desktop_text(bad,arrival),{})

    def test_context_and_section_bounds(self):
        for rows,_ in variants():
            for case in ['architecture','origin','extent','section','truncated']:
                mach,arrival,*_=fixture(rows)
                if case=='architecture':mach.architecture='armv7'
                elif case=='origin':arrival['provenance']['actor']['offset']+=1
                elif case=='extent':arrival['provenance']['actor']['bytes']=314
                elif case=='section':mach.sections=[]
                else:mach.data=mach.data[:128]
                self.assertEqual(reader.extract_desktop_text(mach,arrival),{},case)
