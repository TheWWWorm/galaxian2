"""Station declaration relocation, dependency and mutation boundaries."""
import copy
import unittest
from types import SimpleNamespace
from gof2_content import station_entry as reader


def fixture(shift=0):
    low=min(v[0] for v in reader.LAYOUTS.values())-32
    high=max(v[0]+v[1] for v in reader.LAYOUTS.values())+32
    bias,offset=8192,128
    anchor=0x10000000+shift-low
    raw=bytearray(offset+high-low)
    sections=[]
    for kind in ['__text','__const']:
        rows=[v for v in reader.LAYOUTS.values() if v[2]==kind]
        start=min(v[0] for v in rows);end=max(v[0]+v[1] for v in rows)
        sections.append({'segment':b'__TEXT','name':kind.encode(),'address':anchor+start,'offset':offset+start-low,'length':end-start})
    for delta,size,kind,pattern in reader.LAYOUTS.values():raw[offset+delta-low:offset+delta-low+size]=bytes.fromhex(pattern)
    m=SimpleNamespace(architecture='x86_64',slice_offset=bias,data=bytes(raw),text=sections[0],sections=sections)
    arrival={'campaign_cursor':1,'provenance':{'actor':{'offset':bias+offset-low,'bytes':315}}}
    return m,arrival,{'scope':'opening_rescue_session'},offset,low


class StationEntryTests(unittest.TestCase):
    def test_relocation_and_data_only_output(self):
        for shift in [0,0x2400000]:
            m,a,s,*_=fixture(shift)
            result=reader.extract_station_entry(m,a,s)
            self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
            self.assertEqual(len(result['dialogue']['events']),19)
            for key,span in result['provenance'].items():
                self.assertEqual(set(span),{'offset','bytes'})
                self.assertEqual(span['offset'],a['provenance']['actor']['offset']+reader.LAYOUTS[key][0])
            result['dialogue']['events'].clear()
            self.assertEqual(len(reader.extract_station_entry(m,a,s)['dialogue']['events']),19)

    def test_source_edges_rejected(self):
        m,a,s,offset,low=fixture()
        for key,(delta,size,kind,_) in reader.LAYOUTS.items():
            for edge in [0,size-1]:
                bad=copy.copy(m);data=bytearray(m.data);data[offset+delta-low+edge]^=128;bad.data=bytes(data)
                self.assertEqual(reader.extract_station_entry(bad,a,s),{},(key,edge))

    def test_unavailable_sources(self):
        for case in ['architecture','cursor','anchor','extent','session','scope','truncated','section']:
            m,a,s,*_=fixture()
            if case=='architecture':m.architecture='armv7'
            elif case=='cursor':a['campaign_cursor']=2
            elif case=='anchor':a['provenance']['actor']['offset']+=1
            elif case=='extent':a['provenance']['actor']['bytes']=314
            elif case=='session':s={}
            elif case=='scope':s={'scope':'unknown'}
            elif case=='section':m.sections=m.sections[:1]
            else:m.data=m.data[:128]
            self.assertEqual(reader.extract_station_entry(m,a,s),{},case)
