"""Recover the opening encounter's authored actor and hull overrides as data.

This does not construct AI, execute a mission or derive actors from dialogue IDs.
Only the supported cursor-zero declaration layout is accepted.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes
from .npc_initialization import extract_npc_initialization

MAC_ACTORS = """
bf18000000e8
{call_5:4}
4889c3bf08000000e8
{call_12:4}
48894308c743100100000048c70000000000c7030000000049899f78010000bf
{count:4}
4889dee8
{call_3e:4}
498b87780100008338000f84
{jump_4d:4}
31db41be
{alternate_hull:4}
c704240000000083fb
{alternate_index:1}
b9
{default_hull:4}
410f44ce4c89ffbe
{actor_kind:4}
31d24531c041b901000000e8
{call_81:4}
498b8f78010000488b4908488904d9498b8778010000488b4008488b3cd8e8
{call_a4:4}
498b8778010000488b4008488b04d8488b7808be01000000e8
{call_c1:4}
498b8778010000488b4008488b3cd8488b07f30f1015
{ref_d8:4}
660f6fc2660f6fcaff9090000000498b8778010000488b4008488b04d8c6406800498b8778010000488b4008488b04d848c7407000000000498b8778010000488b4008488b04d8488b7808be
{actor_hull:4}
e8
{call_130:4}
83fb
{effect_last_actor:1}
7f
{jump_138:1}
498b8778010000488b4008488b3cd831f6e8
{call_14b:4}
498b877801000048ffc33b180f82
{jump_15c:4}
498b8768010000488b38be
{player_hull:4}
e8
{call_171:4}
488d05
{ref_176:4}
488b00c780a8000000
{saved_player_hull:4}
498b8768010000488b00c6406201e9
{jump_198:4}
"""

MAC_DISPATCH = """
488d05
{ref_0:4}
488b38e8
{call_a:4}
3d990000000f8f
{jump_14:4}
83f8030f8f
{jump_1d:4}
85c00f84
{jump_25:4}
"""

ARM_ACTORS = """
4ff0ff30c5f868050c20
{call_a:4}
c5f890020120c5f868050420
{call_1a:4}
1a9c0df50e6101260b46d3f89012d3f890225060d3f89022966000220260d3f890020260
{count:2}
c4f8f810
{call_48:4}
d4f8f800254600680028
{jump_56:2}
4ff0ff3600244ff0000b0df50e680120
{default_hull:2}
{alternate_index:2}
c8f86865
{actor_kind:4}
cdf800b04ff0000201902846cdf808b008bf
{alternate_hull:2}
{call_88:4}
d5f8f810496841f82400d5f8f800406850f82400c8f86865
{call_a4:4}
d5f8f8000121406850f824004068c8f86865
{call_ba:4}
d5f8f800aa46406850f8240001688d6c
{position_low:4}
{position_high:4}
c8f868650a460b46a8475546d5f8f800406850f8241081f848b0c1f84cb0
{actor_hull:2}
50f824004068c8f86865
{call_100:4}
{effect_last_actor:2}
{jump_106:2}
d5f8f8000df50e61406850f82400c1f868650021
{call_11c:4}
d5f8f800013400688442
{jump_12a:2}
d5f8f000
{player_hull_low:4}
0df50e624ff0ff31
{player_hull_high:4}
1a950068c2f868152146
{call_14a:4}
1498012100684466d5f8f000006880f85e10
{jump_160:4}
"""

ARM_DISPATCH = """
{pointer_0:4}
{pointer_4:4}
7844006814900068
{call_10:4}
0446
{pointer_16:4}
{pointer_1a:4}
dff83c1f784479440068c5f87c050df64460c5f88015dff8281fc5f8847541f00101c5f88cd57944c5f88815
{call_4a:4}
992c
{jump_50:4}
032c
{jump_56:4}
002c
{jump_5c:4}
"""


def extract_opening_actors(mach):
    import capstone
    mac=mach.architecture=='x86_64'
    if not mac and mach.architecture!='armv7':return {}
    text=mach.text;code=mach.data[text['offset']:text['offset']+text['length']]
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    def unique(spec):
        matches=[m for m in template(spec).finditer(code) if mac or m.start()%2==0]
        if len(matches)!=1:raise ValueError('Missing or ambiguous opening actor declarations')
        return matches[0]
    def location(m):return text['address']+m.start()
    def scalar(m,key):return int.from_bytes(m[key],'little',signed=True)
    def relative(m,key):return text['address']+m.end(key)+scalar(m,key)
    def immediate(m,key,mnemonic,register=None):
        ins=list(decoder.disasm(m[key],text['address']+m.start(key)))
        if len(ins)!=1 or ins[0].mnemonic!=mnemonic or ins[0].operands[-1].type!=2:raise ValueError('Unsupported opening declaration instruction')
        if register is not None and (len(ins[0].operands)!=2 or ins[0].reg_name(ins[0].operands[0].reg)!=register):raise ValueError('Opening declaration register mismatch')
        return ins[0].operands[-1].imm
    def extent(m):return {'offset':mach.slice_offset+text['offset']+m.start(),'bytes':len(m[0])}
    try:
        actors=unique(MAC_ACTORS if mac else ARM_ACTORS);dispatch=unique(MAC_DISPATCH if mac else ARM_DISPATCH)
        start=location(actors);end=start+len(actors[0])
        if mac:
            if relative(dispatch,'jump_25')!=start:raise ValueError('Opening actor cursor dispatch mismatch')
            getter_address=relative(dispatch,'call_a')
            for key,offset in [('jump_4d',0x162),('jump_138',0x150),('jump_15c',0x5b)]:
                if relative(actors,key)!=start+offset:raise ValueError('Unknown opening actor loop')
            count=scalar(actors,'count');alternate_index=scalar(actors,'alternate_index')
            normal=scalar(actors,'default_hull');alternate=scalar(actors,'alternate_hull')
            kind=scalar(actors,'actor_kind');hull=scalar(actors,'actor_hull');player_hull=scalar(actors,'player_hull')
            if player_hull!=scalar(actors,'saved_player_hull'):raise ValueError('Conflicting prologue hull declarations')
            last=scalar(actors,'effect_last_actor')
            setter_address=relative(actors,'call_130')
            if setter_address!=relative(actors,'call_171'):raise ValueError('Different hull setters')
            value_address=relative(actors,'ref_d8')
            value=section_bytes(mach,value_address,4,b'__const')
            if value is None:raise ValueError('Missing opening actor position')
            position=struct.unpack('<f',value[0])[0]
            exit_address=relative(actors,'jump_198')
            getter_pattern='554889e58b87780200005dc3'
            setter_pattern='554889e589b78000000039b78c0000007d0689b78c0000005de9 {changed:4}'
        else:
            if location(dispatch)+len(dispatch[0])!=start:raise ValueError('Opening actor cursor dispatch mismatch')
            for key,mnemonic in [('jump_50','bgt.w'),('jump_56','bgt.w'),('jump_5c','bne.w')]:
                if immediate(dispatch,key,mnemonic)<end:raise ValueError('Unknown opening actor dispatch')
            immediate(dispatch,'pointer_0','movw','r0');immediate(dispatch,'pointer_4','movt','r0')
            immediate(dispatch,'pointer_16','movw','r0');immediate(dispatch,'pointer_1a','movt','r0')
            immediate(dispatch,'call_4a','blx')
            getter_address=immediate(dispatch,'call_10','bl')
            for key,offset,mnemonic in [('jump_56',0x12c,'beq'),('jump_106',0x120,'bgt'),('jump_12a',0x62,'blo')]:
                if immediate(actors,key,mnemonic)!=start+offset:raise ValueError('Unknown opening actor loop')
            for key in actors.groupdict():
                if key.startswith('call_'):immediate(actors,key,'blx' if key in ['call_a','call_1a'] else 'bl')
            count=immediate(actors,'count','movs','r0');alternate_index=immediate(actors,'alternate_index','cmp','r4')
            normal=immediate(actors,'default_hull','movs','r3')
            # IT EQ is fixed in the pattern; isolated decoding reports MOVS.
            alternate=immediate(actors,'alternate_hull','movs','r3')
            kind=immediate(actors,'actor_kind','mov.w','r1');hull=immediate(actors,'actor_hull','movs','r1')
            player_hull=immediate(actors,'player_hull_low','movw','r4')+(immediate(actors,'player_hull_high','movt','r4')<<16)
            last=immediate(actors,'effect_last_actor','cmp','r4')
            setter_address=immediate(actors,'call_100','bl')
            if setter_address!=immediate(actors,'call_14a','bl'):raise ValueError('Different hull setters')
            bits=immediate(actors,'position_low','movw','r1')+(immediate(actors,'position_high','movt','r1')<<16)
            position=struct.unpack('<f',struct.pack('<I',bits))[0]
            value=None
            exit_address=immediate(actors,'jump_160','b.w')
            getter_pattern='d0f8d4017047'
            setter_pattern='8167d0f884208a42b8bfc0f88410 {changed:4}'
        if not end<=exit_address<text['address']+text['length']:raise ValueError('Unknown opening actor continuation')
        if not 1<=count<=32 or not 0<=alternate_index<count or last!=count-1 or not 0<=normal<=4095 or not 0<=alternate<=4095 or not 0<=kind<=255:
            raise ValueError('Invalid opening actor population')
        if not 1<=hull<=2147483647 or not 1<=player_hull<=2147483647 or not math.isfinite(position) or abs(position)>10000000:raise ValueError('Invalid opening actor values')
        getter_bytes=bytes.fromhex(getter_pattern)
        getter=section_bytes(mach,getter_address,len(getter_bytes),b'__text')
        if getter is None or getter[0]!=getter_bytes:raise ValueError('Unknown campaign cursor getter')
        setter_size=30 if mac else 18
        setter=section_bytes(mach,setter_address,setter_size,b'__text')
        matched=template(setter_pattern).fullmatch(setter[0]) if setter else None
        if matched is None:raise ValueError('Unknown current/max hull setter')
        if not mac:
            ins=list(decoder.disasm(matched['changed'],setter_address+14))
            if len(ins)!=1 or ins[0].mnemonic!='b.w' or ins[0].operands[-1].type!=2:raise ValueError('Unknown hull change dispatch')
        provenance={'declaration':extent(actors),'dispatch':extent(dispatch),
                    'cursor_getter':{'offset':getter[1],'bytes':len(getter[0])},
                    'hull_setter':{'offset':setter[1],'bytes':len(setter[0])}}
        if value:provenance['position']={'offset':value[1],'bytes':4}
        rows=[{'actor_id':i,'hull_catalogue_id':alternate if i==alternate_index else normal,
               'actor_kind':kind,'position':[position]*3,'current_hull_override':hull} for i in range(count)]
        factory = relative(actors, 'call_81') if mac else immediate(actors, 'call_88', 'bl')
        return {'actors':rows,'player_current_hull_override':player_hull,'provenance':provenance,
                'npc_initialization': extract_npc_initialization(mach, factory, relative(actors, 'call_a4') if mac else immediate(actors, 'call_a4', 'bl'))}
    except (ValueError,IndexError,KeyError,struct.error):return {}
