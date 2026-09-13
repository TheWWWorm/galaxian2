"""Read source environment RGB tables through bounded, linked lookup contexts.

Only constant floats and file extents leave this import-time reader. No original
instructions are evaluated or emitted into the runtime.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes

COUNTS = {'sun_rgb':19, 'planet_rgb':27, 'rim_rgb':19}


def extract_environment_colors(mach, sky):
    if not sky or mach.architecture not in ['x86_64','armv7']: return {}
    import capstone
    mac=mach.architecture=='x86_64'; prefix='MAC_' if mac else 'ARM_'
    section=mach.text; base=section['address']; file_base=mach.slice_offset+section['offset']
    code=mach.data[section['offset']:section['offset']+section['length']]
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    provenance={}
    def require(ok):
        if not ok: raise ValueError('Unsupported environment color context')
    def ins(m,key):
        rows=list(decoder.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key]));return rows[0]
    def match(key,address=None):
        name=prefix+key.upper(); pattern=template(globals()[name])
        matches=([pattern.match(code,address-base)] if address is not None else
                 [m for m in pattern.finditer(code) if mac or m.start()%2==0])
        require(len(matches)==1 and matches[0] is not None);m=matches[0]
        if not mac:
            for field,meta in ARM_FIELDS[name].items():
                i=ins(m,field);require(i.mnemonic==meta['kind'])
                if 'register' in meta:require(i.reg_name(i.operands[0].reg)==meta['register'])
        provenance[key]={'offset':file_base+m.start(),'bytes':len(m[0])};return m
    def target(m,key):
        return base+m.end(key)+int.from_bytes(m[key],'little',signed=True) if mac else ins(m,key).operands[0].imm
    def arm_address(m,low,high,pc_offset):
        value=ins(m,low).operands[1].imm | (ins(m,high).operands[1].imm<<16)
        return (base+m.start()+pc_offset+value)&0xffffffff
    def getter(key,address,raw):
        data=section_bytes(mach,address,len(raw),b'__text')
        require(data is not None and data[0]==raw)
        provenance[key]={'offset':data[1],'bytes':len(raw)}
    try:
        sun=match('sun');planet=match('planet');rim=match('rim')
        require(sun.end()<rim.start()<sun.end()+2048)
        require(abs(planet.start()-sun.start())<2048)
        system=target(sun,'call_a' if mac else 'bl_e')
        require(system==base+sky['provenance']['system']['offset']-file_base)
        getter('system',system,bytes.fromhex('554889e5488b87280200005dc3' if mac else 'd0f890017047'))
        getter('sky_index',target(sun,'call_12' if mac else 'bl_12'),bytes.fromhex('554889e58b473c5dc3' if mac else '006b7047'))
        getter('station',target(planet,'call_a' if mac else 'bl_2'),bytes.fromhex('554889e5488b87180200005dc3' if mac else 'd0f888017047'))
        getter('planet_type',target(planet,'call_12' if mac else 'bl_6'),bytes.fromhex('554889e58b471c5dc3' if mac else '40697047'))
        if mac:
            addresses=[target(sun,'ref_21'),target(planet,'ref_24'),target(rim,'ref_0')]
        else:
            table=match('planet_table',target(planet,'b_12'))
            require(sun.end()<=table.start()<rim.start())
            addresses=[arm_address(sun,'movw_1e','movt_26',0x30),
                       arm_address(table,'movw_0','movt_6',0xe),
                       arm_address(rim,'movw_0','movt_8',0x10)]
        result={}
        for (key,count),address in zip(COUNTS.items(),addresses):
            found=section_bytes(mach,address,count*12,b'__const')
            require(found is not None)
            values=list(struct.iter_unpack('<3f',found[0]))
            require(all(math.isfinite(v) and 0<=v<=16 for row in values for v in row))
            result[key]=[list(row) for row in values]
            provenance[key]={'offset':found[1],'bytes':count*12}
        spans=sorted((v['offset'],v['offset']+v['bytes']) for v in provenance.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return dict(result,provenance=provenance)
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,struct.error):return {}

MAC_SUN = """
488d05
{ref_0:4}
488b38
e8
{call_a:4}
4889c7
e8
{call_12:4}
418a4e40
8d0440
4c63f8
488d05
{ref_21:4}
f3420f1004b8
f3410f1106
418d5701
4863da
f30f100498
f3410f114604
418d5702
4c63ea
f3420f1004a8
f3410f114608
"""

MAC_PLANET = """
488d05
{ref_0:4}
488b38
e8
{call_a:4}
4889c7
e8
{call_12:4}
418a4e40
8d0440
4863d0
83c002
488d35
{ref_24:4}
f30f100496
f30f1145d0
4863c0
f30f100486
f30f1145d4
ffc2
4863c2
f30f100486
f30f1145cc
"""

MAC_RIM = """
488d0d
{ref_0:4}
f30f1015
{ref_7:4}
f3420f1004b9
f30f59c2
f30f100c99
f30f59ca
f3420f5914a9
4889c7
e8
{call_2b:4}
"""

ARM_SUN = """
{movw_0:4}
{movt_4:4}
7844
0068
0068
{bl_e:4}
{bl_12:4}
98f82810
00eb4004
{movw_1e:4}
04f1020b
{movt_26:4}
661c
7844
{vldr_2e:4}
00eb8b02
00eb8403
00eb8600
0029
93ed000a
92ed002a
90ed004a
88ed000a
88ed014a
88ed022a
20ef1001
"""

ARM_PLANET = """
2868
{bl_2:4}
{bl_6:4}
98f82810
00eb4000
{b_12:2}
"""

ARM_PLANET_TABLE = """
{movw_0:4}
0029
{movt_6:4}
7a44
02eb8000
90ed00aa
90ed019a
90ed028a
"""

ARM_RIM = """
{movw_0:4}
c0ef180f
{movt_8:4}
7844
00eb8b01
00eb8602
00eb8400
92ed001a
90ed000a
91ed002a
01ff301d
00ff300d
daf80000
02ff302d
11ee106a
10ee105a
12ee104a
{bl_42:4}
2946
3246
2346
{bl_4c:4}
"""

ARM_FIELDS = {'ARM_SUN': {'movw_0': {'kind': 'movw', 'register': 'r0'}, 'movt_4': {'kind': 'movt', 'register': 'r0'}, 'bl_e': {'kind': 'bl'}, 'bl_12': {'kind': 'bl'}, 'movw_1e': {'kind': 'movw', 'register': 'r0'}, 'movt_26': {'kind': 'movt', 'register': 'r0'}, 'vldr_2e': {'kind': 'vldr', 'register': 's22'}}, 'ARM_PLANET': {'bl_2': {'kind': 'bl'}, 'bl_6': {'kind': 'bl'}, 'b_12': {'kind': 'b'}}, 'ARM_PLANET_TABLE': {'movw_0': {'kind': 'movw', 'register': 'r2'}, 'movt_6': {'kind': 'movt', 'register': 'r2'}}, 'ARM_RIM': {'movw_0': {'kind': 'movw', 'register': 'r0'}, 'movt_8': {'kind': 'movt', 'register': 'r0'}, 'bl_42': {'kind': 'bl'}, 'bl_4c': {'kind': 'bl'}}}
