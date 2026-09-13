"""Relocated synthetic NPC tuning declarations, without original game assets."""
import copy
import math
import struct
import unittest
from types import SimpleNamespace
from gof2_content import npc_flight as reader
from test_font_selection import expand
from test_ship_models import branch
from test_materials import arm_wide


def fixture(mac, shift=0):
    origin=0x200000+shift; offset=256; bias=4096
    arch='x86_64' if mac else 'armv7'
    data=bytearray(33000)
    bases={'constructor':2000,'update':6000}
    positions={k:bases[b]+d for k,(b,d,_,_) in reader.LAYOUTS[arch].items()}
    positions['actor_wrapper']=1000
    positions['virtual_update']=31000+80
    def write(at,raw): data[offset+at:offset+at+len(raw)]=raw
    def block(at,pattern,values):
        raw,fields=expand(pattern)
        for k,v in values.items():
            p,n=fields[k];assert len(v)==n
            raw[p:p+n]=v
        write(at,raw)
    pattern=reader.MAC_ACTOR_WRAPPER if mac else reader.ARM_ACTOR_WRAPPER
    _,fields=expand(pattern);p,n=fields['constructor']
    block(1000,pattern,{'constructor':struct.pack('<i',2000-1000-p-n) if mac else branch(origin+1000+p,origin+2000)})
    write(positions['virtual_update'],struct.pack('<Q' if mac else '<I',origin+bases['update']+(0 if mac else 1)))
    numbers={'turn_scale':1/32768,'heading_snap_l1':0.125,'bank_sign_angle':math.pi/2,
             'bank_slew_divisor':4.5,'bank_angle_scale':1/2048,'pi':math.pi,
             'slew_numerator':2.0,'history_divisor':5.0}
    references={'turn':{'ref_b' if mac else 'ref_0':'turn_scale'},'snap':{'ref_0':'heading_snap_l1'},
                'sign':{'ref_0':'bank_sign_angle'},'slew':{'ref_d' if mac else 'ref_4':'bank_slew_divisor'},
                'radians':{'ref_0':'bank_angle_scale','ref_8' if mac else 'ref_6':'pi'}}
    if mac:
        references['slew']['ref_5']='slew_numerator'
        references['history']={'ref_33':'history_divisor','ref_c9':'sign_mask'}
    next_literal=30000 if mac else bases['update']+12784
    for key,(_,_,size,pattern) in reader.LAYOUTS[arch].items():
        values={};at=positions[key];_,fields=expand(pattern)
        if key=='bank':
            if mac: values={'bank_limit':struct.pack('<f',500),'bank_gain':struct.pack('<f',12)}
            else:
                for stem,value in [('limit',500),('gain',12)]:
                    word=struct.unpack('<I',struct.pack('<f',value))[0]
                    values[stem+'_low']=arm_wide(word&65535,3)
                    values[stem+'_high']=arm_wide(word>>16,3,True)
        if key=='turn' and mac:values['turn_numerator']=bytes([40])
        if key=='slew' and not mac:values['slew_numerator']=bytes.fromhex('c7ef140f')
        for field,name in references.get(key,{}).items():
            target=next_literal;next_literal+=16 if name=='sign_mask' else 4
            positions[name]=target
            write(target,struct.pack('<4I',*[0x80000000]*4) if name=='sign_mask' else struct.pack('<f',numbers[name]))
            p,n=fields[field]
            if mac:values[field]=struct.pack('<i',target-at-p-n)
            else:
                reg={'turn':0,'snap':4,'sign':0,'slew':8,'radians':4 if field=='ref_0' else 2}[key]
                delta=target-((at+p+4)&~3)
                assert delta%4==0 and abs(delta)<=1020
                values[field]=struct.pack('<HH',0xed9f if delta>=0 else 0xed1f,((reg//2)<<12)|0x0a00|(abs(delta)//4))
        block(at,pattern,values)
    def extent(at,size):return {'offset':bias+offset+at,'bytes':size}
    m=SimpleNamespace(architecture=arch,data=bytes(data),slice_offset=bias,
        sections=[{'name':b'__text','segment':b'__TEXT','offset':offset,'address':origin,'length':28000},
                  {'name':b'__const','segment':b'__TEXT','offset':offset+30000,'address':origin+30000,'length':500},
                  {'name':b'__const','segment':b'__DATA','offset':offset+31000,'address':origin+31000,'length':500}])
    initial={'provenance':{'actor_wrapper':extent(1000,14 if mac else 60)},
             'activation':{'provenance':{'virtual_activation':extent(positions['virtual_update']-(80 if mac else 40),8 if mac else 4)}}}
    return m,{'npc_initialization':initial},positions,offset


class NpcFlightTests(unittest.TestCase):
    def test_relocated_independent_tuning(self):
        for mac in [True,False]:
            for shift in [0,0x600000]:
                m,a,_,_=fixture(mac,shift)
                result=reader.extract_npc_flight(m,a)
                self.assertTrue(result,(mac,shift))
                self.assertEqual(result['bank_limit'],500)
                self.assertEqual(result['bank_gain'],12)
                self.assertEqual(result['turn_numerator'],40 if mac else 48)
                self.assertEqual(result['bank_slew_numerator'],2 if mac else 1.25)
                self.assertEqual(result['turn_scale'],1/32768)
                self.assertEqual(result['bank_angle_scale'],1/2048)

    def test_corrupt_layouts_and_links(self):
        for mac in [True,False]:
            m,a,p,offset=fixture(mac)
            for key in [*reader.LAYOUTS[m.architecture],'actor_wrapper','virtual_update']:
                damaged=copy.copy(m);data=bytearray(m.data)
                data[offset+p[key]]^=255;damaged.data=bytes(data)
                self.assertEqual(reader.extract_npc_flight(damaged,a),{},(mac,key))
            for key in ['bank_sign_angle','pi','heading_snap_l1','turn_scale','bank_slew_divisor']:
                for value in [math.nan,math.inf,-1,0,100001]:
                    damaged=copy.copy(m);data=bytearray(m.data)
                    struct.pack_into('<f',data,offset+p[key],value);damaged.data=bytes(data)
                    self.assertEqual(reader.extract_npc_flight(damaged,a),{},(mac,key,value))
            for size in [offset+p['virtual_update']+1,offset+p['travel']+2]:
                damaged=copy.copy(m);damaged.data=m.data[:size]
                self.assertEqual(reader.extract_npc_flight(damaged,a),{})

    def test_required_scope_and_section_boundaries(self):
        for mac in [True,False]:
            m,a,_,_=fixture(mac)
            self.assertFalse(reader.extract_npc_flight(m,{}))
            changed=copy.deepcopy(a);changed['npc_initialization']['activation']={}
            self.assertFalse(reader.extract_npc_flight(m,changed))
            changed=copy.deepcopy(m);changed.sections[-1]['segment']=b'__TEXT'
            self.assertFalse(reader.extract_npc_flight(changed,a))
            changed=copy.deepcopy(m);changed.sections[0]['length']=10000
            self.assertFalse(reader.extract_npc_flight(changed,a))


if __name__=='__main__':unittest.main()
