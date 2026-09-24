"""Both Mac station layouts: bounded pointers/header, hashes and source damage."""
import copy
import unittest
from unittest.mock import patch
from declaration_fixture import declaration_fixture
from gof2_content import station_presentation as reader


def variants():
    return [('LAYOUTS',reader.LAYOUTS,reader.VALUES),
            ('MAC_ALTERNATE',reader.MAC_ALTERNATE,reader.MAC_VALUES)]


def extract(mach,arrival):
    return reader.extract_station_presentation(mach,arrival,{'scope':'first_station_entry'})


class StationPresentationTests(unittest.TestCase):
    def test_relocated_complete_layout_and_detachment(self):
        for name,rows,expected in variants():
            for shift in [0,0x2400000]:
                mach,arrival,proofs=declaration_fixture(rows,shift,'sha256:')
                with patch.object(reader,name,proofs):
                    result=extract(mach,arrival)
                    self.assertEqual({k:v for k,v in result.items() if k!='provenance'},expected)
                    self.assertEqual(set(result['provenance']),set(rows))
                    result['dialogue']['voice_event_ids'].clear()
                    self.assertEqual(extract(mach,arrival)['dialogue']['voice_event_ids'],expected['dialogue']['voice_event_ids'])

    def test_every_source_boundary_is_required(self):
        for name,rows,_ in variants():
            mach,arrival,proofs=declaration_fixture(rows,hash_prefix='sha256:')
            origin=arrival['provenance']['actor']['offset']-mach.slice_offset
            with patch.object(reader,name,proofs):
                self.assertTrue(extract(mach,arrival))
                for key,(delta,size,_,_) in rows.items():
                    for edge in [0,size-1]:
                        bad=copy.copy(mach);data=bytearray(mach.data);data[origin+delta+edge]^=255;bad.data=bytes(data)
                        self.assertEqual(extract(bad,arrival),{},(name,key,edge))

    def test_context_section_header_and_truncation(self):
        for name,rows,_ in variants():
            for case in ['architecture','origin','extent','station','section','header_bounds','truncated']:
                mach,arrival,proofs=declaration_fixture(rows,hash_prefix='sha256:')
                station={'scope':'first_station_entry'}
                if case=='architecture':mach.architecture='armv7'
                elif case=='origin':arrival['provenance']['actor']['offset']+=1
                elif case=='extent':arrival['provenance']['actor']['bytes']=314
                elif case=='station':station.clear()
                elif case=='section':mach.sections=[s for s in mach.sections if s['name']!=b'__data']
                elif case=='header_bounds':proofs['zero_fill_section'][0]+=4096
                else:mach.data=mach.data[:128]
                with patch.object(reader,name,proofs):
                    self.assertEqual(reader.extract_station_presentation(mach,arrival,station),{},(name,case))
