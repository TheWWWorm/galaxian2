"""Relocated synthetic opening declarations, with meaningful corruption cases."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from gof2_content.opening_actors import extract_opening_actors,MAC_ACTORS,ARM_ACTORS,MAC_DISPATCH,ARM_DISPATCH
from test_font_selection import expand
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac, relocation=0):
    start=0x10000+relocation;dispatch_start=start+512 if mac else start-96;getter=start+1024;setter=start+1100;constant=start+4096
    actors,af=expand(MAC_ACTORS if mac else ARM_ACTORS);dispatch,df=expand(MAC_DISPATCH if mac else ARM_DISPATCH)
    def put(block,fields,key,value):
        at,size=fields[key];assert size==len(value);block[at:at+size]=value
    def near_branch(at,target,kind):
        delta=target-at-4
        if kind=='blo':opcode=0xd300
        elif kind=='bgt':opcode=0xdc00
        elif kind=='beq':opcode=0xd000
        else:raise ValueError(kind)
        return struct.pack('<H',opcode|((delta//2)&255))
    def wide_branch(at,target,kind):
        delta=target-at-4
        if kind=='b.w':
            raw=bytearray(branch(at,target));raw[3]&=~0x40;return bytes(raw)
        # Thumb-2 conditional branch: S:J2:J1:imm6:imm11:0.
        d=delta&0x1fffff;condition={'bgt.w':12,'bne.w':1}[kind]
        return struct.pack('<2H',0xf000|((d>>20)<<10)|(condition<<6)|((d>>12)&63),0x8000|(((d>>18)&1)<<13)|(((d>>19)&1)<<11)|((d>>1)&2047))
    for block,fields,base in [(actors,af,start),(dispatch,df,dispatch_start)]:
        for key,(at,size) in fields.items():
            if key.startswith('call_'):
                target=start+2000
                if block is dispatch and key==('call_a' if mac else 'call_10'):target=getter
                if block is actors and key in (['call_130','call_171'] if mac else ['call_100','call_14a']):target=setter
                if mac:raw=struct.pack('<i',target-base-at-4)
                else:
                    blx=(block is actors and key in ['call_a','call_1a']) or (block is dispatch and key=='call_4a')
                    raw=bytearray(branch(((base+at+4)&~3)-4 if blx else base+at,target))
                    if blx:raw[3]&=~0x10
                put(block,fields,key,raw)
            elif mac and key.startswith('ref_'):put(block,fields,key,struct.pack('<i',constant-base-at-4))
            elif key.startswith('jump_'):
                if mac:
                    destinations={'jump_4d':start+0x162,'jump_138':start+0x150,'jump_15c':start+0x5b,'jump_25':start}
                    target=destinations.get(key,start+2200)
                    put(block,fields,key,int(target-base-at-size).to_bytes(size,'little',signed=True))
                else:
                    if block is actors:
                        cases={'jump_56':(start+0x12c,'beq'),'jump_106':(start+0x120,'bgt'),'jump_12a':(start+0x62,'blo'),'jump_160':(start+2200,'b.w')}
                        target,kind=cases[key]
                    else:target,kind=start+2200,('bne.w' if key=='jump_5c' else 'bgt.w')
                    put(block,fields,key,near_branch(base+at,target,kind) if size==2 else wide_branch(base+at,target,kind))
            elif key.startswith('pointer_'):
                put(block,fields,key,arm_wide(123,0,key in ['pointer_4','pointer_1a']))
    if mac:
        scalars={'count':3,'alternate_hull':7,'alternate_index':1,'default_hull':4,'actor_kind':8,'actor_hull':123,'effect_last_actor':2,'player_hull':9999,'saved_player_hull':9999}
        for key,value in scalars.items():put(actors,af,key,value.to_bytes(af[key][1],'little',signed=True))
    else:
        shorts={'count':(0,3,False),'default_hull':(3,4,False),'alternate_index':(4,1,True),'alternate_hull':(3,7,False),'actor_hull':(1,123,False),'effect_last_actor':(4,2,True)}
        for key,(reg,value,cmp) in shorts.items():put(actors,af,key,struct.pack('<H',(0x2800 if cmp else 0x2000)|(reg<<8)|value))
        put(actors,af,'actor_kind',bytes.fromhex('4ff00801'))
        for key,value,reg,top in [('position_low',0,1,False),('position_high',0x42c8,1,True),('player_hull_low',9999,4,False),('player_hull_high',0,4,True)]:put(actors,af,key,arm_wide(value,reg,top))
    data=bytearray(8192)
    actor_offset=256;dispatch_offset=actor_offset+dispatch_start-start
    data[actor_offset:actor_offset+len(actors)]=actors;data[dispatch_offset:dispatch_offset+len(dispatch)]=dispatch
    raw=bytes.fromhex('554889e58b87780200005dc3' if mac else 'd0f8d4017047')
    data[1280:1280+len(raw)]=raw
    raw=bytes.fromhex('554889e589b78000000039b78c0000007d0689b78c0000005de9')+struct.pack('<i',100) if mac else bytes.fromhex('8167d0f884208a42b8bfc0f88410')+wide_branch(setter+14,setter+100,'b.w')
    data[1356:1356+len(raw)]=raw
    struct.pack_into('<f',data,5000,100)
    text={'name':b'__text','segment':b'__TEXT','address':start-256,'offset':0,'length':4000}
    const={'name':b'__const','segment':b'__TEXT','address':constant,'offset':5000,'length':4}
    return SimpleNamespace(data=bytes(data),text=text,sections=[text,const],slice_offset=16384,architecture='x86_64' if mac else 'armv7'),af,df,dispatch_offset


@unittest.skipUnless(importlib.util.find_spec('capstone'),'optional static-reader dependency')
class OpeningActors(unittest.TestCase):
    def test_relocation_and_source_parameter_changes(self):
        for mac in [True,False]:
            for relocation in [0,0x30000]:
                with self.subTest(mac=mac,relocation=relocation):
                    mach,*_=fixture(mac,relocation);scope=extract_opening_actors(mach)
                    self.assertEqual([a['hull_catalogue_id'] for a in scope['actors']],[4,7,4])
                    self.assertEqual([a['current_hull_override'] for a in scope['actors']],[123]*3)
                    self.assertEqual(scope['actors'][0]['position'],[100]*3)
                    self.assertEqual(scope['player_current_hull_override'],9999)
                    self.assertEqual(scope['provenance']['declaration']['offset'],16640)

    def test_rejects_broken_dispatch_loop_hull_setter_and_values(self):
        for mac in [True,False]:
            for bad in ['dispatch','loop','getter','setter','setter_link','count','hull','position','effect_range']:
                with self.subTest(mac=mac,bad=bad):
                    mach,af,df,do=fixture(mac);data=bytearray(mach.data)
                    if bad=='dispatch':data[do+df['jump_25' if mac else 'jump_5c'][0]]^=(0x10 if mac else 0x40)
                    elif bad=='loop':data[256+af['jump_15c' if mac else 'jump_12a'][0]]^=1
                    elif bad=='getter':data[1280]^=1
                    elif bad=='setter':data[1356]^=1
                    elif bad=='setter_link':data[256+af['call_171' if mac else 'call_14a'][0]]^=1
                    elif bad=='count':data[256+af['count'][0]]=0
                    elif bad=='hull':data[256+af['actor_hull'][0]]=0
                    elif bad=='effect_range':data[256+af['effect_last_actor'][0]]=1
                    elif mac:struct.pack_into('<f',data,5000,float('nan'))
                    else:
                        at=256+af['position_high'][0];data[at:at+4]=arm_wide(0x7fc0,1,True)
                    mach.data=bytes(data)
                    self.assertEqual(extract_opening_actors(mach),{})

if __name__=='__main__':unittest.main()
