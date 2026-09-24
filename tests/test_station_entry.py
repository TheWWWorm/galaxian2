"""Station declaration relocation, dependency and mutation boundaries."""
import copy
import unittest
from declaration_fixture import literal_fixture
from gof2_content import station_entry as reader


def variants():
    return [(reader.LAYOUTS,reader.VALUES),(reader.MAC_ALTERNATE,reader.MAC_VALUES)]


def fixture(rows,shift=0):
    layout={k:[v[0],v[1],v[3]] for k,v in rows.items()}
    constants=[k for k,v in rows.items() if v[2]=='__const']
    mach,origin,offset,low=literal_fixture('x86_64',layout,shift,constants)
    arrival={'campaign_cursor':1,'provenance':{'actor':{'offset':origin,'bytes':315}}}
    return mach,arrival,{'scope':'opening_rescue_session'},offset,low


class StationEntryTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for layout,expected in variants():
            for shift in [0,0x2400000]:
                m,a,s,*_=fixture(layout,shift)
                result=reader.extract_station_entry(m,a,s)
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},expected)
                self.assertEqual(len(result['dialogue']['events']),19)
                for key,span in result['provenance'].items():
                    self.assertEqual(set(span),{'offset','bytes'})
                    self.assertEqual(span['offset'],a['provenance']['actor']['offset']+layout[key][0])
                result['dialogue']['events'].clear()
                self.assertEqual(len(reader.extract_station_entry(m,a,s)['dialogue']['events']),19)

    def test_source_edges_rejected(self):
        for layout,expected in variants():
            m,a,s,offset,low=fixture(layout)
            for key,(delta,size,kind,_) in layout.items():
                for edge in [0,size-1]:
                    bad=copy.copy(m);data=bytearray(m.data);data[offset+delta-low+edge]^=128;bad.data=bytes(data)
                    self.assertEqual(reader.extract_station_entry(bad,a,s),{},(key,edge))

    def test_unavailable_sources(self):
        for layout,expected in variants():
            for case in ['architecture','cursor','anchor','extent','session','scope','truncated','section']:
                m,a,s,*_=fixture(layout)
                if case=='architecture':m.architecture='armv7'
                elif case=='cursor':a['campaign_cursor']=2
                elif case=='anchor':a['provenance']['actor']['offset']+=1
                elif case=='extent':a['provenance']['actor']['bytes']=314
                elif case=='session':s={}
                elif case=='scope':s={'scope':'unknown'}
                elif case=='section':m.sections=m.sections[:1]
                else:m.data=m.data[:128]
                self.assertEqual(reader.extract_station_entry(m,a,s),{},case)
