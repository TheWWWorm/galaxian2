"""Read ordinary NPC constructor declarations linked to the opening factory.

Only constant initialization and bounded argument/getter layouts are inspected.
No executable bytes or source control flow become runtime content.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes

MAC_SELECTION = '488d05 {world:4} 488b38e8 {selector:4} b9 {special:4} 84c0bb {ordinary:4} 0f45d9bf28010000e8 {allocate:4} 4989c44c89e789de4489f2b90100000041b8010000004531c9e8 {stats:4}'
ARM_SELECTION = 'd8f800004ff0ff363096 {selector:4} 04464ff48a703096 {allocate:4} 01221390139830920023 {ordinary:4} cde90023002c18bf {special:4} 2a460123 {stats:4}'
MAC_SELECTOR = '554889e5488d05 {settings:4} f30f10402cf30fc205 {value:4} 00 660f7ec083e0015dc3'
ARM_SELECTOR = '{settings_low:4} {value:4} {settings_high:4} 7844006890ed0b0a0020b4eec10af1ee10fa08bf01207047'
MAC_SHIP = '4c89f78b5db889de448b6dbc4489ea4c89e141b8000000004589f9e8 {actor:4}'
ARM_SHIP = 'f9682b4604911299119a8ded029a8ded03aa8ded018a009420ef1001 {actor:4}'
MAC_ACTOR_WRAPPER = '554889e5450fb6c95de9 {constructor:4}'
ARM_ACTOR_WRAPPER = '90b501af85b00446b86997ed040a97ed032a97ed054a04902046d7f808908ded020a8ded034a8ded012acdf8009020ef1001 {constructor:4} 204605b090bd'
MAC_BASE_CALL = '450fb6c9baffffffffe8 {base:4}'
ARM_BASE_CALL = 'ba6904924ff0ff328ded022a8ded030a8ded014a009420ef1001 {base:4}'


def extract_npc_initialization(mach, factory, opening_deactivation):
    import capstone
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    decoder.detail = True
    provenance = {}
    def require(condition):
        if not condition: raise ValueError('Unsupported NPC initialization')
    def read(key, address, size, section=b'__text'):
        found = section_bytes(mach, address, size, section)
        require(found is not None and len(found[0]) == size)
        provenance[key] = {'offset': found[1], 'bytes': size}
        return found[0]
    def match(key, address, size, spec):
        result = template(spec).fullmatch(read(key,address,size))
        require(result is not None)
        return result
    def arm(m, key, address, mnemonic, register=None):
        rows = list(decoder.disasm(m[key],address+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key]))
        row=rows[0]
        require(row.mnemonic==mnemonic)
        if register is not None: require(row.reg_name(row.operands[0].reg)==register)
        require(row.operands[-1].type in [capstone.arm.ARM_OP_IMM,capstone.arm.ARM_OP_FP])
        return row.operands[-1].fp if row.operands[-1].type==capstone.arm.ARM_OP_FP else row.operands[-1].imm
    def target(m,key,address,branch='bl'):
        return address+m.end(key)+int.from_bytes(m[key],'little',signed=True) if mac else arm(m,key,address,branch)
    def boolean(key,address,opcode):
        raw=read(key,address,len(bytes.fromhex(opcode))+1)
        require(raw[:-1]==bytes.fromhex(opcode) and raw[-1] in [0,1])
        return bool(raw[-1])
    try:
        require(read('factory_entry',factory,4)==bytes.fromhex('554889e5' if mac else 'f0b503af'))
        selection_address=factory+(0x203 if mac else 0x23e)
        selection=match('selection',selection_address,70 if mac else 60,MAC_SELECTION if mac else ARM_SELECTION)
        selector=target(selection,'selector',selection_address)
        getter=match('selector',selector,34 if mac else 36,MAC_SELECTOR if mac else ARM_SELECTOR)
        if mac:
            ordinary=int.from_bytes(selection['ordinary'],'little',signed=True)
            special=int.from_bytes(selection['special'],'little',signed=True)
            value_address=target(getter,'value',selector)+1  # CMP immediate predicate follows displacement.
            value=struct.unpack('<f',read('difficulty_value',value_address,4,b'__const'))[0]
        else:
            ordinary=arm(selection,'ordinary',selection_address,'mov.w','r1')
            special=arm(selection,'special',selection_address,'movw','r1')
            arm(getter,'settings_low',selector,'movw','r0')
            arm(getter,'settings_high',selector,'movt','r0')
            value=arm(getter,'value',selector,'vmov.f32','d1')
        require(1<=ordinary<=10000000 and 1<=special<=10000000 and math.isfinite(value) and 0<=value<=10)
        wrapper=target(selection,'stats',selection_address)
        if mac:
            stub=match('stats_wrapper',wrapper,10,'554889e55de9 {constructor:4}')
            stats=target(stub,'constructor',wrapper)
            require(read('stats_entry',stats,20)==bytes.fromhex('554889e54157415641554154534883ec284589ce'))
            require(read('extent_argument',stats+0xaa,9)==bytes.fromhex('897344899380000000'))
            require(read('pools',stats+0xec,33)==bytes.fromhex('c7437000000000c643620048c783980000000000000048c7839000000000000000'))
            firing=boolean('firing',stats+0x10d,'c683cb000000')
            active=boolean('active',stats+0x305,'c683c8000000')
            damage=boolean('damage',stats+0x31d,'c683ca000000')
            player=boolean('player',stats+0x35b,'c6436d')
        else:
            stub=match('stats_wrapper',wrapper,30,'90b501af82b00446b868d7f80c908de801022046 {constructor:4} 204602b090bd')
            stats=target(stub,'constructor',wrapper)
            require(read('stats_entry',stats,28)==bytes.fromhex('f0b503af2de9000dadf1400424f00f04a54604f9ed8204f9efc298b0'))
            require(read('extent_argument',stats+0x6e,4)==bytes.fromhex('3164b267'))
            require(read('zero_integer',stats+0x42,2)==bytes.fromhex('0024'))
            require(read('zero_register',stats+0x24,4)==bytes.fromhex('c0ef5000'))
            require(read('pools',stats+0x8c,28)==bytes.fromhex('06f18800f4670125c6f88040f46686f85e4040f98f0a304686f8c350'))
            require(read('flags',stats+0x20c,88)==bytes.fromhex('002001214ff0ff35c6f8d00086f8701004acc6f80c1186f8440086f8450086f8680086f8c01086f8c100c6f8b40086f8c210c6f8d40086f85d0086f85c0086f8e00086f8ec0086f8ed00706786f8540086f8550086f86900'))
            firing=active=damage=True
            player=False
        ship_address=factory+(0x324 if mac else 0x2ca)
        ship=match('ship_call',ship_address,32,MAC_SHIP if mac else ARM_SHIP)
        actor_wrapper=target(ship,'actor',ship_address)
        actor=match('actor_wrapper',actor_wrapper,14 if mac else 60,MAC_ACTOR_WRAPPER if mac else ARM_ACTOR_WRAPPER)
        actor_constructor=target(actor,'constructor',actor_wrapper,'bl')
        base_address=actor_constructor+(0x43 if mac else 0x42)
        base=match('base_call',base_address,14 if mac else 30,MAC_BASE_CALL if mac else ARM_BASE_CALL)
        base_constructor=target(base,'base',base_address)
        if mac:
            special_state=boolean('special_state',base_constructor+0x181,'c64358')
            eligible=boolean('collision_enabled',base_constructor+0x1ab,'c683c0000000')
            point=boolean('point_geometry',base_constructor+0x21e,'c6435c')
        else:
            require(read('actor_flags',base_constructor+0x122,62)==bytes.fromhex('00204ff0ff32c0f22401c6f82480f064794486f86e0086f8210086f8710086f8380086f8390086f83a0086f83e0086f83f0086f840007264012286f88820'))
            require(read('point_geometry',base_constructor+0x1a6,26)==bytes.fromhex('02990120002281f8f1004ff0ff3081f82020c1f8e42081f83c20'))
            special_state=point=False
            eligible=True
        deactivate=match('opening_deactivation',opening_deactivation,30 if mac else 28,
                         '554889e553504889fbc783bc00000005000000488b7b0831f6e8 {setter:4}' if mac else
                         '90b504460520c4f884000021606801af {setter:4} 012084f8ad0090bd')
        setter=target(deactivate,'setter',opening_deactivation)
        require(read('activity_setter',setter,13 if mac else 6)==bytes.fromhex('554889e54088b7c80000005dc3' if mac else '80f8c0107047'))
        # The authored opening deactivation overrides the constructor's active flag.
        active=False
        spans=sorted((row['offset'],row['offset']+row['bytes']) for row in provenance.values())
        require(all(a[1]<=b[0] for a,b in zip(spans,spans[1:])))
        return {'ordinary_half_extent':ordinary,'special_half_extent':special,'special_difficulty':value,
                'initial_armor':0,'initial_shield':0.0,'initial_firing_allowed':firing,
                'initial_active':active,'initial_damage_allowed':damage,'is_player':player,
                'initial_special_impact_state':special_state,'initial_collision_enabled':eligible,
                'initial_point_geometry':point,'provenance':provenance}
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error): return {}
