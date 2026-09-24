"""Per-source voice tables, language pointers and radio timing stay connected."""
import copy
import struct
import unittest
from declaration_fixture import literal_fixture
from gof2_content import radio_audio as reader


def variants():
    return [('x86_64', reader.LAYOUTS['x86_64'], reader.DATA['x86_64']),
            ('armv7', reader.LAYOUTS['armv7'], reader.DATA['armv7']),
            ('x86_64', reader.MAC_ALTERNATE, reader.MAC_DATA)]


def fixture(arch,layout,data,shift=0,count=23):
    rows=copy.deepcopy(layout)
    table=b''.join(struct.pack('<ii',1000+i,200+i) for i in range(1504))
    values={'lookup_table':table,'language_table':bytes(data['language_table'][1]),
            'default_name':b'english\0','override_name':b'deutsch\0'}
    for key,(delta,size) in data.items():rows[key]=[delta,size,values[key].hex()]
    mach,origin,_,_=literal_fixture(arch,rows,shift,list(data))
    address=mach.text['address']+origin-mach.slice_offset-mach.text['offset']
    for key in ['default_name','override_name']:
        delta,size=data[key]
        mach.sections.append({'segment':b'__TEXT','name':b'__cstring','address':address+delta,
                              'offset':origin+delta-mach.slice_offset,'length':size})
    raw=bytearray(mach.data)
    struct.pack_into('<2Q' if arch=='x86_64' else '<2I',raw,
                     origin+data['language_table'][0]-mach.slice_offset,
                     address+data['default_name'][0],address+data['override_name'][0])
    mach.data=bytes(raw)
    dialogue={'campaign_cursor':0 if count==23 else 1,
              'events':[{'text_id':1000+i} for i in range(count)],
              'provenance':{k:{'offset':origin+layout[k][0],'bytes':layout[k][1]}
                            for k in ['display_delay','duration']}}
    fonts={'languages':{'rows':[{}, {'file':'de.lang','language_id':1}]}}
    return mach,dialogue,fonts,origin


class RadioAudioTests(unittest.TestCase):
    def test_relocated_owners_and_actual_table_values(self):
        for arch,layout,data in variants():
            for shift,count in [(0,23),(0x700000,3)]:
                mach,dialogue,fonts,origin=fixture(arch,layout,data,shift,count)
                result=reader.extract_radio_audio(mach,dialogue,fonts)
                self.assertEqual(result['event_ids'],list(range(200,200+count)))
                self.assertEqual(result['text_ids'],list(range(1000,1000+count)))
                self.assertEqual({k:result[k] for k in reader.VALUES},reader.VALUES)
                for span in result['provenance'].values():self.assertEqual(set(span),{'offset','bytes'})
                for valid in [-1,19999]:
                    raw=bytearray(mach.data)
                    struct.pack_into('<i',raw,origin+data['lookup_table'][0]-mach.slice_offset+4,valid)
                    mach.data=bytes(raw)
                    self.assertEqual(reader.extract_radio_audio(mach,dialogue,fonts)['event_ids'][0],valid)

    def test_every_proof_and_language_pointer(self):
        for arch,layout,data in variants():
            mach,dialogue,fonts,origin=fixture(arch,layout,data)
            for key,(delta,size,_) in layout.items():
                for endpoint in [0,size-1]:
                    bad=copy.copy(mach);raw=bytearray(mach.data)
                    raw[origin+delta+endpoint-mach.slice_offset]^=255;bad.data=bytes(raw)
                    self.assertFalse(reader.extract_radio_audio(bad,dialogue,fonts),(arch,key,endpoint))
            for key in ['language_table','default_name','override_name']:
                bad=copy.copy(mach);raw=bytearray(mach.data)
                raw[origin+data[key][0]-mach.slice_offset]^=1;bad.data=bytes(raw)
                self.assertFalse(reader.extract_radio_audio(bad,dialogue,fonts),(arch,key))

    def test_invalid_and_absent_voice_rows(self):
        for arch,layout,data in variants():
            mach,dialogue,fonts,origin=fixture(arch,layout,data)
            for column,row,value in [(4,0,-2),(4,0,20000),(0,0,-1),(0,0,65536),
                                     (0,0,65535),(0,1,1000)]:
                bad=copy.copy(mach);raw=bytearray(mach.data)
                struct.pack_into('<i',raw,origin+data['lookup_table'][0]-mach.slice_offset+row*8+column,value)
                bad.data=bytes(raw)
                self.assertFalse(reader.extract_radio_audio(bad,dialogue,fonts),(arch,column,row,value))

    def test_timing_language_and_section_boundaries(self):
        for arch,layout,data in variants():
            for change in ['duration','display_delay','language','language_id','count','cursor','section','truncation','arch']:
                mach,dialogue,fonts,origin=fixture(arch,layout,data)
                if change in ['duration','display_delay']:dialogue['provenance'][change]['offset']+=2
                elif change=='language':fonts['languages']['rows'][1]['file']='fr.lang'
                elif change=='language_id':fonts['languages']['rows'][1]['language_id']=0
                elif change=='count':dialogue['events'].pop()
                elif change=='cursor':dialogue['campaign_cursor']=2
                elif change=='section':mach.sections.pop()
                elif change=='truncation':mach.data=mach.data[:origin-mach.slice_offset]
                else:mach.architecture='unsupported'
                self.assertFalse(reader.extract_radio_audio(mach,dialogue,fonts),(arch,change))
