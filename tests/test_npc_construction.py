"""Synthetic relocated construction declarations; no supplied game data."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import npc_construction as reader
from test_font_selection import expand
from test_ship_models import branch


def fixture(mac,shift=0):
    origin=0x200000+shift;offset=256;bias=4096;arch='x86_64' if mac else 'armv7'
    data=bytearray(25000);positions={};fields={}
    bases={'constructor':1000,'factory':4000,'cargo':6000,'item_layout':8000,'fragments':10000,
           'category':11000,'rank':11100,'price':11200,'chance':11300,'requirements':11400,'predicate':11500}
    def write(at,raw):data[offset+at:offset+at+len(raw)]=raw
    def extent(at,n):return {'offset':bias+offset+at,'bytes':n}
    patterns={k:v[3] for k,v in reader.LAYOUTS[arch].items()}
    patterns['selection']=reader.GUIDANCE_LAYOUTS[arch]['selection'][3]
    patterns['effect_wrapper']='554889e55de9 {inner:4}' if mac else '90b5044601af {inner:4} 204690bd'
    for key,pattern in patterns.items():
        if key=='selection':at=16000
        elif key=='effect_wrapper':at=17000
        else:base,delta,_,_=reader.LAYOUTS[arch][key];at=bases[base]+delta
        positions[key]=at;raw,fields[key]=expand(pattern);write(at,raw)
    destinations={}
    for n,group in enumerate(reader.SAME_TARGETS[arch]):
        for name in group:destinations[name]=20000+16*n
    for base,(key,field) in reader.LINKS[arch].items():destinations[key+'.'+field]=bases[base]
    destinations['item_arrays.'+('call_18' if mac else 'call_14')]=bases['item_layout']
    destinations['selection.'+('call_33' if mac else 'call_3c')]=destinations['spawn.'+('call_72' if mac else 'call_86')]
    destinations['tail.'+('call_101' if mac else 'call_94')]=17000
    destinations['effect_wrapper.inner']=17500
    for name,destination in destinations.items():
        key,field=name.split('.');at=positions[key];p,n=fields[key][field]
        write(at+p,struct.pack('<i',destination-at-p-n) if mac else branch(origin+at+p,origin+destination))
    values={'rotation_divisor':180.0,'rotation_multiplier':reader.VALUES['rotation_multiplier'],'scale_divisor':100.0}
    literal_positions={}
    for n,(name,value) in enumerate(values.items()):
        if mac:
            target=22000+n*4;field=['ref_244','ref_276','ref_329'][n];p,length=fields['fragments'][field];at=positions['fragments']
            write(at+p,struct.pack('<i',target-at-p-length))
        else:target=10000+588+n*4
        write(target,struct.pack('<f',value));literal_positions[name]=target
    weights=22032;write(weights,struct.pack('<5i',*reader.VALUES['category_weights']));literal_positions['weights']=weights
    at=positions['cargo']
    if mac:
        p,n=fields['cargo']['ref_300'];write(at+p,struct.pack('<i',weights-at-p-n))
    else:
        value=weights-at-278
        for field,imm,base in [('weights_low',value&65535,0xf240),('weights_high',(value>>16)&65535,0xf2c0)]:
            p,n=fields['cargo'][field]
            write(at+p,struct.pack('<HH',base|((imm>>12)&15)|(((imm>>11)&1)<<10),(((imm>>8)&7)<<12)|(1<<8)|(imm&255)))
    if mac:write(18000+18*4,struct.pack('<i',19000-18000));write(19000,bytes.fromhex('41c6475001'))
    else:
        # Thumb TBB table entries are unsigned relative halfword offsets.
        write(18000+18,bytes([100]));write(18200,bytes.fromhex('84f85080'))
    positions['equipment_case']=19000 if mac else 18200
    zero=17500+(121 if mac else 76);write(zero,bytes.fromhex('49c7461800000000' if mac else '002300686a65ab65ea652a666a666a626b60ab60eb60'));positions['effect_zero']=zero
    opening=14000;discard=opening+(272 if mac else 240)
    write(discard,bytes.fromhex('48c7407000000000' if mac else 'c1f84cb0'));positions['discard']=discard
    if not mac:write(opening+94,bytes.fromhex('4ff0000b'));positions['cargo_zero']=opening+94
    text={'name':b'__text','segment':b'__TEXT','offset':offset,'address':origin,'length':21500}
    m=SimpleNamespace(architecture=arch,data=bytes(data),slice_offset=bias,text=text,sections=[text,{'name':b'__const','segment':b'__TEXT','offset':offset+22000,'address':origin+22000,'length':500}])
    initial={'routes':{'available':True},'holding':{'available':True},'provenance':{'factory_entry':extent(4000,4)},
             'flight':{'provenance':{'bank':extent(1000+(2272 if mac else 1794),4)}},
             'guidance':{'provenance':{'selection':extent(16000,len(expand(patterns['selection'])[0]))}}}
    actors={'actors':[{'actor_id':i,'actor_kind':8,'hull_catalogue_id':[2,23,2][i]} for i in range(3)],'npc_initialization':initial,'provenance':{'declaration':extent(opening,400)}}
    vehicle={'provenance':{'item_type_layout':extent(8000,30),'equipment_table':extent(18000,120 if mac else 30)}}
    return m,actors,vehicle,positions,literal_positions,fields,offset


class ConstructionTests(unittest.TestCase):
    def test_independent_relocated_layouts(self):
        for mac in [False,True]:
            for shift in [0,0x600000]:
                m,a,v,*_=fixture(mac,shift);result=reader.extract_npc_construction(m,a,v)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),23 if mac else 24)

    def test_changed_declarations_literals_and_links(self):
        for mac in [False,True]:
            m,a,v,positions,literals,fields,offset=fixture(mac)
            for key,at in {**positions,**literals}.items():
                changed=copy.copy(m);data=bytearray(m.data);data[offset+at]^=255;changed.data=bytes(data)
                self.assertFalse(reader.extract_npc_construction(changed,a,v),(mac,key))
            for group in reader.SAME_TARGETS[m.architecture]:
                key,field=group[0].split('.');at=positions[key]+fields[key][field][0]
                changed=copy.copy(m);data=bytearray(m.data)
                data[offset+at:offset+at+4]=struct.pack('<i',1000) if mac else branch(m.text['address']+at,m.text['address']+19900)
                changed.data=bytes(data)
                self.assertFalse(reader.extract_npc_construction(changed,a,v),(mac,key,field))

    def test_missing_scope_sections_and_bounds(self):
        for mac in [False,True]:
            m,a,v,*_=fixture(mac)
            for key in ['flight','routes','guidance','holding']:
                changed=copy.deepcopy(a);changed['npc_initialization'][key]={}
                self.assertFalse(reader.extract_npc_construction(m,changed,v))
            changed=copy.deepcopy(m);changed.sections.append(copy.copy(m.text))
            self.assertFalse(reader.extract_npc_construction(changed,a,v))
            changed=copy.copy(m);changed.data=m.data[:22040]
            self.assertFalse(reader.extract_npc_construction(changed,a,v))
            changed=copy.copy(m);changed.architecture='unsupported'
            self.assertFalse(reader.extract_npc_construction(changed,a,v))


if __name__=='__main__':unittest.main()
