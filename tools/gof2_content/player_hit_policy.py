"""Static player damage scaling, linked to the existing ordinary collision route."""
import math
import struct
from .ordinary_hit_policy import MAC_ROUTE, ARM_ROUTE
from .opening_loadout import template
from .ship_models import section_bytes


def extract_player_hit_policy(mach, weapon):
    if mach.architecture not in ('x86_64','armv7'): return {}
    import capstone
    mac=mach.architecture=='x86_64';proof={};text=mach.text
    decoder=capstone.Cs(capstone.CS_ARCH_ARM,capstone.CS_MODE_THUMB);decoder.detail=True
    def require(value):
        if not value: raise ValueError('Unsupported player hit policy')
    def read(key,address,size,section):
        row=section_bytes(mach,address,size,section);require(row is not None)
        proof[key]={'offset':row[1],'bytes':size};return row[0]
    try:
        anchor=weapon['ordinary_hit_policy']['provenance']['damage_route']
        at=text['address']+anchor['offset']-mach.slice_offset-text['offset']
        raw=read('damage_route',at,185 if mac else 120,b'__text')
        route=template(MAC_ROUTE if mac else ARM_ROUTE).fullmatch(raw);require(route is not None)
        if mac:
            values=[]
            for key,field in [('nonhostile','constant_32'),('special_first','constant_86'),('special_second','constant_8e')]:
                address=at+route.end(field)+int.from_bytes(route[field],'little',signed=True)
                values.append(struct.unpack('<f',read(key,address,4,b'__const'))[0])
        else:
            # The two VFP immediates and s24 load supply the route's live
            # multiplier registers. Do not infer values from a dead literal.
            setup_at=at-0x344
            setup=read('scaling_setup',setup_at,12,b'__text')
            rows=list(decoder.disasm(setup,setup_at))
            require(len(rows)==3)
            for i,register in enumerate(['d8','d10']):
                require(rows[i].mnemonic=='vmov.f32' and rows[i].reg_name(rows[i].operands[0].reg)==register and rows[i].operands[1].type==capstone.arm.ARM_OP_FP)
            load=rows[2]
            require(load.mnemonic=='vldr' and load.reg_name(load.operands[0].reg)=='s24' and load.operands[1].type==capstone.arm.ARM_OP_MEM and load.reg_name(load.operands[1].mem.base)=='pc')
            literal=((load.address+4)&~3)+load.operands[1].mem.disp
            require(literal==at+98)
            values=[struct.unpack_from('<f',raw,98)[0],rows[0].operands[1].fp,rows[1].operands[1].fp]
        require(all(math.isfinite(x) and x>0 for x in values))
        require(values==[struct.unpack('<f',bytes.fromhex('cdcc4c3e'))[0],3.0,0.25])
        spans=sorted((r['offset'],r['offset']+r['bytes']) for r in proof.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return {'nonhostile_scale':values[0],'special_flight_multipliers':values[1:],
                'rounding':'binary32_then_truncate','nonhostile_precedes_special':True,'provenance':proof}
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error):return {}
