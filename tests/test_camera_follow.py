"""Synthetic follow parameters and bounded coefficient-table recovery."""
import importlib.util
import struct
import unittest
from test_opening_camera import camera_fixture
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch
from gof2_content import camera_follow as reader
from gof2_content.opening_staging import extract_opening_staging
from gof2_content.opening_camera import extract_opening_camera


def fixture(mac,relocation=0):
    m,parents,parent_addresses,_,helpers=camera_fixture(mac,relocation)
    data=bytearray(m.data);base=m.text['address'];prefix='MAC_' if mac else 'ARM_'
    names=['follow','curve','reset','rate_scale','scale','add','subtract','point']
    blocks={k:expand(getattr(reader,prefix+k.upper())) for k in names}
    addresses={};at=base+30000
    for key,(body,_) in blocks.items():addresses[key]=at;at=(at+len(body)+527)&~15
    assert at<base+49000
    def encoded_link(site,dest,size,kind='bl',register='r0'):
        if mac:return (dest-site-size).to_bytes(size,'little',signed=True)
        if kind in ['bl','blx','b.w']:
            raw=bytearray(branch(((site+4)&~3)-4 if kind=='blx' else site,dest))
            if kind=='blx':raw[3]&=~0x10
            if kind=='b.w':raw[3]&=~0x40
            return raw
        d=dest-site-4
        if kind=='b':return struct.pack('<H',0xe000|((d//2)&0x7ff))
        if kind in ['cbz','cbnz']:return struct.pack('<H',0xb100|(0x800 if kind=='cbnz' else 0)|((d&0x40)<<3)|((d&0x3e)<<2)|int(register[1:]))
        if kind in ['bne','beq']:return struct.pack('<H',(0xd100 if kind=='bne' else 0xd000)|((d//2)&255))
        raise ValueError(kind)
    def patch_parent(key,field,dest):
        off,size=parents[key][1][field];site=parent_addresses[key]+off
        start=256+site-base
        data[start:start+size]=encoded_link(site,dest,size,'b.w' if not mac and field.startswith('jump') else 'bl')
    for f in ['call_3c4','call_3f4'] if mac else ['call_206','call_228']:patch_parent('defaults',f,addresses['curve'])
    patch_parent('increment','jump_52' if mac else 'jump_44',addresses['follow']-(0x795 if mac else 0x43c))
    links={
        'follow':{'point':['call_15a','call_192'],'scale':['call_2b3','call_389'],'add':['call_2be','call_3d3'],'subtract':['call_1d0','call_2f9']},
        'reset':{'rate_scale':['jump_21']},'rate_scale':{'curve':['call_37','jump_72']}
    } if mac else {
        'follow':{'point':['call_c8','call_de'],'scale':['call_1a2','call_208'],'add':['call_1ae','call_246'],'subtract':['call_f2','call_1c2']},
        'reset':{'rate_scale':['jump_18']},'rate_scale':{'curve':['call_36','call_60']}}
    edges={'jump_6d':0x78,'jump_73':0x14d,'jump_13d':0x141,'jump_13f':0x14d,'jump_395':0x3c5} if mac else {'jump_3a':0xb6,'jump_a4':0xbc,'jump_b4':0xbc,'jump_210':0x23e}
    const=m.sections[1];constant_end=const['offset']+const['length'];scalars={}
    coefficient_field='ref_2e8' if mac else 'literal_1f8'
    for key,(body,fields) in blocks.items():
        pool=(addresses[key]+len(body)+7)&~7
        for field,(off,size) in fields.items():
            site=addresses[key]+off;meta=reader.ARM_FIELDS.get(prefix+key.upper(),{}).get(field,{})
            if field.startswith(('call_','jump_')):
                alias=next((name for name,refs in links.get(key,{}).items() if field in refs),None)
                dest=addresses[alias] if alias else addresses[key]+edges[field] if key=='follow' and field in edges else helpers['other']
                kind=meta.get('kind','bl');raw=encoded_link(site,dest,size,kind,meta.get('register','r0'))
            elif field.startswith(('ref_','literal_')):
                width=8 if key=='curve' else 4
                value=57.25 if key=='curve' and field==coefficient_field else 0.0 if key=='curve' else 1.0
                bits=bytes.fromhex('0000000000000080') if mac and key=='curve' and field=='ref_235' else struct.pack('<d' if width==8 else '<f',value)
                if mac:
                    dest=const['address']+constant_end-const['offset'];file=constant_end;constant_end+=width
                    raw=encoded_link(site,dest,4)
                else:
                    dest=pool;pool+=width;file=256+dest-base;disp=dest-((site+4)&~3)
                    assert 0<=disp<=1020 and disp%4==0
                    reg=meta['register'];n=int(reg[1:]);double=reg[0]=='d'
                    raw=struct.pack('<HH',0xed9f|(((n>>4) if double else (n&1))<<6),(((n&15) if double else (n//2))<<12)|(0xb00 if double else 0xa00)|(disp//4))
                data[file:file+width]=bits;scalars[(key,field)]=file
            elif field.startswith('rate_'):raw=struct.pack('<f',.02 if field=='rate_4' else .03)
            elif field.startswith('word_'):
                val=struct.unpack('<I',struct.pack('<f',.02 if field in ['word_0','word_c'] else .03))[0]
                high=meta['kind']=='movt';raw=arm_wide(val>>16 if high else val&65535,int(meta['register'][1:]),high)
            else:raise ValueError(field)
            assert len(raw)==size
            body[off:off+size]=raw
        start=256+addresses[key]-base;data[start:start+len(body)]=body
    const['length']=constant_end-const['offset'];m.data=bytes(data)
    return m,blocks,addresses,scalars


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class CameraFollow(unittest.TestCase):
    def test_relocated_changed_rates_and_coefficients(self):
        for mac in [True,False]:
            for relocation in [0,0x80000]:
                with self.subTest(mac=mac,relocation=relocation):
                    m,*_=fixture(mac,relocation);camera=extract_opening_camera(m,extract_opening_staging(m));self.assertTrue(camera)
                    result=reader.extract_camera_follow(m,camera);self.assertTrue(result)
                    self.assertAlmostEqual(result['look_rate'],.02)
                    self.assertAlmostEqual(result['eye_rate'],.03)
                    self.assertEqual(result['response_matrix'][0][0],-57.25)
                    self.assertEqual(sum(v!=0 for row in result['response_matrix'] for v in row),1)

    def test_corrupt_follow_scope_rejected(self):
        for mac in [True,False]:
            for bad in ['missing','helper','link','rate','coefficient','sign','edge','duplicate','truncated']:
                if not mac and bad=='sign':continue
                with self.subTest(mac=mac,bad=bad):
                    m,blocks,addresses,scalars=fixture(mac);data=bytearray(m.data)
                    def file(key,field=None):return 256+addresses[key]-m.text['address']+(blocks[key][1][field][0] if field else 0)
                    if bad=='helper':data[file('scale')]^=1
                    elif bad=='link':data[file('rate_scale','call_37' if mac else 'call_36')]^=4
                    elif bad=='rate':
                        if mac:struct.pack_into('<f',data,file('reset','rate_4'),float('nan'))
                        else:
                            off=file('reset','word_c');data[off:off+4]=arm_wide(0x7fc0,2,True)
                    elif bad=='coefficient':struct.pack_into('<d',data,scalars[('curve','ref_2e8' if mac else 'literal_1f8')],float('inf'))
                    elif bad=='sign':data[scalars[('curve','ref_235')]+7]=0
                    elif bad=='edge':data[file('follow','jump_73' if mac else 'jump_3a')]^=4
                    elif bad=='duplicate':
                        body=blocks['curve'][0];data[256+47000:256+47000+len(body)]=body
                    elif bad=='truncated':data=data[:file('point')+len(blocks['point'][0])-1]
                    m.data=bytes(data)
                    camera={} if bad=='missing' else extract_opening_camera(m,extract_opening_staging(m))
                    self.assertEqual(reader.extract_camera_follow(m,camera),{})

if __name__=='__main__':unittest.main()
