"""Synthetic section relocation and fail-closed guidance declaration checks."""
import copy
import struct
import unittest
from types import SimpleNamespace
from gof2_content import opening_npc_guidance as reader
from test_font_selection import expand


def fixture(mac,shift=0):
    origin=0x200000+shift;offset=256;bias=4096
    arch='x86_64' if mac else 'armv7'
    bases={'membership':1000,'constructor':4000,'factory':10000,'update':20000}
    data=bytearray(53000);positions={};literal_positions={}
    def write(at,raw):data[offset+at:offset+at+len(raw)]=raw
    def extent(at,n):return {'offset':bias+offset+at,'bytes':n}
    for key,(base,delta,size,pattern) in reader.LAYOUTS[arch].items():
        at=bases[base]+delta;positions[key]=at;raw,_=expand(pattern);write(at,raw)
    unique={};next_literal=50000
    for name,(register,expected) in reader.LITERALS[arch].items():
        block,field=name.split('.');at=positions[block]
        _,fields=expand(reader.LAYOUTS[arch][block][3]);p,n=fields[field]
        values=expected if isinstance(expected,list) else [expected]
        token=tuple(values)
        if token not in unique:
            if mac:target=next_literal;next_literal+=4*len(values)
            elif block=='boost_damage':target=((positions[block]+952)&~3)+4*len(unique)
            elif block=='boost_response':target=(positions['boost_damage']+980)&~3
            else:target=((positions['fire']-600)&~3)+4*(len(unique)-3)
            unique[token]=target
            write(target,struct.pack('<'+'f'*len(values),*values))
        target=unique[token];literal_positions[name]=target
        if mac:encoded=struct.pack('<i',target-at-p-n)
        elif field=='rates':
            # Thumb SUBW R0,PC,#imm12. Keep its literal pool within reach.
            delta=at+p+4-target
            first=0xf2af|(((delta>>11)&1)<<10)
            second=(((delta>>8)&7)<<12)|(delta&255)
            encoded=struct.pack('<HH',first,second)
        else:
            reg=int(register[1:]);delta=target-((at+p+4)&~3)
            assert delta%4==0 and abs(delta)<=1020,(name,delta)
            encoded=struct.pack('<HH',(0xed9f if delta>=0 else 0xed1f)|((reg&1)<<6),((reg//2)<<12)|0x0a00|(abs(delta)//4))
        write(at+p,encoded)
    slot=51000;write(slot,struct.pack('<Q' if mac else '<I',origin+bases['update']+(0 if mac else 1)))
    text={'name':b'__text','segment':b'__TEXT','offset':offset,'address':origin,'length':45000}
    m=SimpleNamespace(architecture=arch,data=bytes(data),slice_offset=bias,text=text,
        sections=[text,{'name':b'__const','segment':b'__TEXT','offset':offset+50000,'address':origin+50000,'length':500},
                  {'name':b'__const','segment':b'__DATA','offset':offset+51000,'address':origin+51000,'length':500}])
    initial={'provenance':{'factory_entry':extent(bases['factory'],4)},
             'flight':{'provenance':{'virtual_update':extent(slot,8 if mac else 4),'bank':extent(bases['constructor']+(2272 if mac else 1794),24 if mac else 52)}},
             'primary_weapon':{'provenance':{'fresh_level':extent(500,1)}}}
    actors={'npc_initialization':initial,'actors':[{'actor_id':i,'actor_kind':8,'hull_catalogue_id':[2,23,2][i]} for i in range(3)]}
    return m,actors,positions,literal_positions,offset


class GuidanceTests(unittest.TestCase):
    def test_independent_relocated_profiles(self):
        for mac in [False,True]:
            for shift in [0,0x600000]:
                m,a,_,_,_=fixture(mac,shift)
                result=reader.extract_opening_npc_guidance(m,a)
                self.assertTrue(result,(mac,shift))
                self.assertEqual({k:v for k,v in result.items() if k!='provenance'},reader.VALUES)
                self.assertEqual(len(result['provenance']),21 if mac else 20)

    def test_reject_changed_blocks_literals_and_targets(self):
        for mac in [False,True]:
            m,a,positions,literals,offset=fixture(mac)
            for key,at in {**positions,**literals,'virtual_update':51000}.items():
                altered=copy.copy(m);data=bytearray(m.data);data[offset+at]^=255;altered.data=bytes(data)
                self.assertFalse(reader.extract_opening_npc_guidance(altered,a),(mac,key))
            for key in ['actor_id','actor_kind','hull_catalogue_id']:
                altered=copy.deepcopy(a);altered['actors'][1][key]=99
                self.assertFalse(reader.extract_opening_npc_guidance(m,altered))
            for key in ['flight','primary_weapon']:
                altered=copy.deepcopy(a);altered['npc_initialization'][key]={}
                self.assertFalse(reader.extract_opening_npc_guidance(m,altered))

    def test_ambiguity_bounds_and_architecture(self):
        for mac in [False,True]:
            m,a,p,_,offset=fixture(mac)
            changed=copy.copy(m);changed.data=m.data[:offset+51002]
            self.assertFalse(reader.extract_opening_npc_guidance(changed,a))
            changed=copy.deepcopy(m);changed.sections[-1]['segment']=b'__TEXT'
            self.assertFalse(reader.extract_opening_npc_guidance(changed,a))
            changed=copy.copy(m);data=bytearray(m.data);n=reader.LAYOUTS[m.architecture]['membership'][2]
            data[offset+3000:offset+3000+n]=data[offset+p['membership']:offset+p['membership']+n];changed.data=bytes(data)
            self.assertFalse(reader.extract_opening_npc_guidance(changed,a))
            changed=copy.copy(m);changed.architecture='unsupported'
            self.assertFalse(reader.extract_opening_npc_guidance(changed,a))


if __name__=='__main__':unittest.main()
