"""Read the ordinary opening NPC main-weapon declaration without running code.

This scope is limited to fresh opening actors, before any generated mission,
companion or later-campaign weapon replacement. It emits content values only.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes
from .weapon_capacity import MAC_CALL, ARM_CALL

LAYOUTS = {'x86_64': {'main': (0,
                     180,
                     'e8 {call_0:4} 88c1b82d00000084c97509498b7d00e8 {call_14:4} 01c0b9 {interval:4} '
                     '29c1890c244c89e7be000000008b5588b9 {capacity:4} 41b8ffffffff41b9 {lifetime:4} '
                     'f30f108578ffffff0f57c90f57d20f57db0f57e4e8 {call_55:4} 4c89e7be01000000e8 {call_62:4} '
                     '4c89e74c89fee8 {call_6d:4} 4c89e731f6e8 {call_77:4} '
                     '41c78424a000000000000000498b8778010000488b40084a8b04308b40444883f80a0f8795faffff488d0d '
                     '{ref_a4:4} 486304814801c8ffe0'),
            'kind': (-1223, 31, '41c78424a0000000 {kind:4} 4c89e7be {item:4} e8 {call_14:4} 41bf {model:4}'),
            'base_damage': (-2070,
                            43,
                            'b8 {damage:4} '
                            '4585e4418d5424020f44d0899564ffffffb8010000008b8d74ffffff83f9044189d4440f44e0'),
            'speed': (-1759, 10, 'f30f1005 {ref_0:4} 7540'),
            'level_zero': (-2464,
                           77,
                           '488d05 {ref_0:4} 488b38e8 {call_a:4} 83c0fef30f2ac0f30f5905 {ref_16:4} 0f2e05 '
                           '{ref_1e:4} 7726488d05 {ref_27:4} 488b38e8 {call_31:4} 83c0fef30f2ac8f30f590d '
                           '{ref_3d:4} 0f57c00f2ec1775a')},
 'armv7': {'main': (0,
                    154,
                    '{call_0:4} 08b12d2005e01898032100683091 {call_12:4} 0422269930920022 {capacity:2} '
                    '049205920692079208920992 {interval:4} a2eb40008ded03da0290 {lifetime:4} '
                    '1a9a01904ff0ff3000900846002120ef1001 {call_50:4} 269c4ff0ff35012130952046 {call_60:4} '
                    '30952046ddf864804146 {call_6e:4} 204600213095 {call_78:4} '
                    '269800214ff0ff3bc165d8f8f8001b9940684058406a0a2813d8dfe800f0'),
           'kind': (190, 22, '2698 {kind:2} 2699ca65 {item:2} cdf8c0b0 {call_e:4} {model:4}'),
           'base_damage': (-700, 24, '8a1c002908bf {damage:2} 13990f92b6ee00fb042908bf01221092'),
           'speed': (-662, 4, '{speed:4}'),
           'level_zero': (-1098,
                          82,
                          'd8f800003094 {call_6:4} '
                          '02389fedda8a83ef140f40ec300bfbff200600ff981db4eec01af1ee10fa13dcd8f800003094 '
                          '{call_30:4} 023840ec300bfbff200600ff980db5eec00af1ee10fa02d580ef100024e0')}}

FRESH = {'x86_64': (11, '41c7865802000001000000'),
 'armv7': (42, '00230124c0f888300a6800f5e071c0f89c31c0f8a031c0f8ac31c0f8b03101f98f8ac0f8d031c0f8b441')}

def extract_opening_npc_weapon(mach, actors, opening, weapon):
    import capstone
    mac = mach.architecture == 'x86_64'
    if mach.architecture not in LAYOUTS: return {}
    layouts = LAYOUTS[mach.architecture]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    decoder.detail = True
    proof = {}
    def require(value):
        if not value: raise ValueError('Unsupported opening NPC weapon declaration')
    def address(span):
        offset = span['offset'] - mach.slice_offset
        sections = [s for s in mach.sections if s['offset'] <= offset and offset + span['bytes'] <= s['offset'] + s['length']]
        require(len(sections) == 1)
        return sections[0]['address'] + offset - sections[0]['offset']
    def read(key, at, size, section=b'__text'):
        found = section_bytes(mach, at, size, section)
        require(found is not None and len(found[0]) == size)
        proof[key] = {'offset': found[1], 'bytes': size}
        return found[0]
    def match(key, at, size, pattern):
        found = template(pattern).fullmatch(read(key, at, size))
        require(found is not None)
        return found
    def instruction(row, key, at, mnemonic, register=None):
        rows = list(decoder.disasm(row[key], at + row.start(key)))
        require(len(rows) == 1 and rows[0].size == len(row[key]))
        i = rows[0]
        require(i.mnemonic == mnemonic and i.operands[-1].type in [capstone.arm.ARM_OP_IMM, capstone.arm.ARM_OP_FP])
        if register: require(i.reg_name(i.operands[0].reg) == register)
        return i.operands[-1].fp if i.operands[-1].type == capstone.arm.ARM_OP_FP else i.operands[-1].imm
    def target(row, key, at):
        return at + row.end(key) + int.from_bytes(row[key], 'little', signed=True) if mac else instruction(row, key, at, 'bl')
    def scalar(row, key, at, mnemonic, register):
        return int.from_bytes(row[key], 'little', signed=True) if mac else instruction(row, key, at, mnemonic, register)
    try:
        initial = actors['npc_initialization']
        require(initial and opening and weapon['launch_modes'] and weapon['projectile_capacity'])
        require([a['actor_id'] for a in actors['actors']] == [0,1,2])
        require([a['actor_kind'] for a in actors['actors']] == [8,8,8])
        require([a['hull_catalogue_id'] for a in actors['actors']] == [2,23,2])
        text = mach.text
        code = mach.data[text['offset']:text['offset'] + text['length']]
        matches = [m for m in template(layouts['main'][2]).finditer(code) if mac or m.start()%2 == 0]
        require(len(matches) == 1)
        main_at = text['address'] + matches[0].start()
        rows = {key: match(key, main_at+offset, size, pattern) for key,(offset,size,pattern) in layouts.items()}
        main = rows['main']; kind_at = main_at + layouts['kind'][0]; kind = rows['kind']
        # The factory is selected through this edition's own source actor kind.
        if mac:
            table = target(main, 'ref_a4', main_at)
            destination = table + struct.unpack('<i',read('actor_kind',table+8*4,4))[0]
        else:
            table = main_at + layouts['main'][1]
            destination = table + 2*read('actor_kind',table+8,1)[0]
        require(destination == kind_at)
        item = scalar(kind,'item',kind_at,'movs','r1')
        kind_id = scalar(kind,'kind',kind_at,'movs','r2')
        model = scalar(kind,'model',kind_at,'movw','sl')
        require(kind_id == 1 and 0 <= item <= 65535 and 0 <= model <= 65535)
        require(item not in weapon['launch_modes']['alternate_item_ids'])
        classification = address(weapon['launch_modes']['provenance']['classification'])
        item_setter = classification - (17 if mac else 78)
        require(target(main,'call_77' if mac else 'call_78',main_at) == item_setter)
        require(target(kind,'call_14' if mac else 'call_e',kind_at) == item_setter)
        # Both owners use the same base projectile constructor, with distinct
        # source arguments. NPC capacity must not inherit the player's pool size.
        cp = weapon['projectile_capacity']['provenance']['constructor_call']
        player_at = address(cp)
        player = match('player_constructor',player_at,cp['bytes'],MAC_CALL if mac else ARM_CALL)
        require(target(main,'call_55' if mac else 'call_50',main_at) == target(player,'ctor',player_at))
        npc_flag = target(main,'call_62' if mac else 'call_60',main_at)
        match('npc_owner',npc_flag,13 if mac else 6,
              '554889e54088b7510100005dc3' if mac else '80f8f9107047')
        cursor = target(main,'call_14' if mac else 'call_12',main_at)
        match('cursor',cursor,12 if mac else 6,'554889e58b87780200005dc3' if mac else 'd0f8d4017047')
        complete = target(main,'call_0',main_at)
        match('post_campaign',complete,16 if mac else 14,
              '554889e583bf780200002c0f9fc05dc3' if mac else 'd0f8d41100202c29c8bf01207047')
        # The reset default is one, but flight entry recalculates fresh rank to
        # zero (verified by npc_hull). Both inputs take the recognized
        # negative-to-zero scaling branch and retain base_damage.
        fresh_at = address(opening['provenance']['declaration']) - (0x974 if mac else 0x734)
        size,pattern = FRESH[mach.architecture]
        match('fresh_level',fresh_at,size,pattern)
        level_at = main_at + layouts['level_zero'][0]; level = rows['level_zero']
        getter = target(level,'call_a' if mac else 'call_6',level_at)
        require(getter == target(level,'call_31' if mac else 'call_30',level_at))
        match('level_getter',getter,12 if mac else 6,'554889e58b87580200005dc3' if mac else 'd0f8b4017047')
        if mac:
            multiplier = target(level,'ref_16',level_at)
            require(multiplier == target(level,'ref_3d',level_at))
            scale = struct.unpack('<f',read('level_scale',multiplier,4,b'__const'))[0]
            speed = struct.unpack('<f',read('speed_value',target(rows['speed'],'ref_0',main_at+layouts['speed'][0]),4,b'__const'))[0]
        else:
            # VFP literal load in the bounded level selector; PC is aligned.
            scale_at = (level_at+12+4)&~3
            scale = struct.unpack('<f',read('level_scale',scale_at+0x368,4))[0]
            speed = instruction(rows['speed'],'speed',main_at+layouts['speed'][0],'vmov.f32','d8')
        require(math.isfinite(scale) and scale > 0 and math.isfinite(speed) and 0 < speed <= 100000)
        damage_at = main_at + layouts['base_damage'][0]
        damage = scalar(rows['base_damage'],'damage',damage_at,'movs','r2')
        interval = scalar(main,'interval',main_at,'mov.w','r2')
        capacity = scalar(main,'capacity',main_at,'movs','r3')
        lifetime = scalar(main,'lifetime',main_at,'movw','r0')
        require(1 <= damage <= 100000 and 1 <= interval <= 100000 and 1 <= lifetime <= 100000 and 1 <= capacity <= 4096)
        spans = sorted((r['offset'],r['offset']+r['bytes']) for r in proof.values())
        require(all(a[1] <= b[0] for a,b in zip(spans,spans[1:])))
        return {'actor_ids':[0,1,2],'actor_kind':8,'item_id':item,'kind':kind_id,'category':0,
                'model_resource_id':model,'damage':damage,'interval_ms':interval,'lifetime_ms':lifetime,
                'speed_units_per_millisecond':speed,'projectile_capacity':capacity,
                'local_muzzle':[0.0,0.0,0.0],'launch_mode':'ordinary','provenance':proof}
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error): return {}
