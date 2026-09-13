"""Read fresh player statistics and equipment capacity declarations, statically.

Depends on validated vehicle, NPC statistics and cursor-zero staging anchors.
No executable bytes or gameplay instructions are returned to the engine.
"""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

VALUES = {"half_extent":1200,"initial_active":True,"initial_damage_allowed":True,
          "is_player":True,"equipment_rule":"last_matching","missing_capacity":0,
          "item_type_value_index":5,"shield_equipment_type":9,"armor_equipment_type":10,
          "shield_property":18,"armor_property":20}


def extract_player_initialization(mach, actors, vehicle, staging):
    import capstone
    arch = mach.architecture
    if arch not in LAYOUTS or not actors.get('npc_initialization') or not vehicle or not staging:
        return {}
    mac = arch == 'x86_64'
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    decoder.detail = True
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    provenance = {}
    matches = {}
    addresses = {}

    def require(value):
        if not value: raise ValueError('Unsupported fresh player initialization')

    def anchor(data, key):
        row = data['provenance'][key]
        at = row['offset'] - mach.slice_offset - text['offset']
        require(type(at) is int and 0 <= at < len(code) and 0 < row['bytes'] <= len(code) - at)
        return text['address'] + at

    def match(key, address):
        size, spec = LAYOUTS[arch][key]
        found = section_bytes(mach, address, size, b'__text')
        result = template(spec).fullmatch(found[0]) if found else None
        require(result is not None)
        provenance[key] = {'offset':found[1], 'bytes':size}
        matches[key] = result
        addresses[key] = address
        return address

    def target(key, field, mnemonic='bl'):
        m = matches[key]; address = addresses[key]
        if mac: return address + m.end(field) + int.from_bytes(m[field], 'little', signed=True)
        ins = list(decoder.disasm(m[field], address + m.start(field)))
        require(len(ins) == 1 and ins[0].mnemonic == mnemonic and ins[0].operands[-1].type == capstone.arm.ARM_OP_IMM)
        return ins[0].operands[-1].imm

    try:
        rows = [m for m in template(LAYOUTS[arch]['factory'][1]).finditer(code) if mac or m.start() % 2 == 0]
        require(len(rows) == 1)
        match('factory', text['address'] + rows[0].start())
        npc = actors['npc_initialization']
        require(target('factory', 'call_28' if mac else 'call_26') == anchor(npc, 'stats_wrapper'))
        require(target('factory', 'call_43' if mac else 'call_42') == target('factory', 'call_69' if mac else 'call_66'))
        for key, field in [('shield_getter','call_51' if mac else 'call_48'),
                           ('armor_getter','call_77' if mac else 'call_72'),
                           ('shield_setter','call_61' if mac else 'call_58'),
                           ('armor_setter','call_87' if mac else 'call_82')]:
            match(key, target('factory', field))
        require(target('shield_setter','call_24' if mac else 'call_20','b.w') ==
                target('armor_setter','call_18' if mac else 'call_8','b.w'))
        match('active', anchor(npc, 'active' if mac else 'flags') + (0 if mac else 2))
        match('damage_permission', anchor(staging,'initial') + (0x56 if mac else 0x30))
        require(target('damage_permission','call_1' if mac else 'call_0') == anchor(staging,'player_getter'))
        match('damage_setter', target('damage_permission','call_14' if mac else 'call_12'))

        table = anchor(vehicle,'equipment_table')
        size = 120 if mac else 30
        found = section_bytes(mach, table, size, b'__text')
        require(found is not None)
        provenance['equipment_table'] = {'offset':found[1], 'bytes':size}
        entries = struct.unpack('<30i',found[0]) if mac else found[0]
        for key, type_id in [('shield_assignment',VALUES['shield_equipment_type']),
                             ('armor_assignment',VALUES['armor_equipment_type'])]:
            # Type indices are checked against the actual dispatch table, not
            # accepted merely because a matching assignment exists elsewhere.
            address = table + entries[type_id] * (1 if mac else 2)
            require(sum(table + entry * (1 if mac else 2) == address for entry in entries) == 1)
            match(key,address)
            require(target(key,'call_18' if mac else 'call_8') == anchor(vehicle,'property_getter'))
        selector = anchor(vehicle,'equipment_selector')
        for key, delta in ({'reset':-175,'loop_initial':-37,'loop_next':713} if mac else
                           {'zero_vector':-210,'reset':-166,'loop_offset':-102,'loop_initial':-68,'loop_next':426}).items():
            match(key,selector + delta)
        if mac:
            require(target('loop_initial','ref_6') == table)
            require(target('loop_initial','ref_13') == target('factory','ref_35'))
            require(target('loop_initial','call_33') == addresses['loop_next'] + 4)
            require(target('loop_next','call_16') == selector - 17)
        else:
            require(target('loop_initial','call_2','b') == selector - 10)
            require(target('loop_next','call_10','blo.w') == selector - 10)
        require(vehicle['equipment_rule'] == 'last_matching' and vehicle['item_type_value_index'] == 5)
        spans = sorted((r['offset'], r['offset'] + r['bytes']) for r in provenance.values())
        require(all(a[1] <= b[0] for a,b in zip(spans,spans[1:])))
        return dict(VALUES, provenance=provenance)
    except (ValueError,KeyError,TypeError,IndexError,OverflowError,struct.error):
        return {}

LAYOUTS = {'x86_64': {'factory': (96,
                        '4889c7e8 {call_4:4} 4c89f7beb004000089c24489e14589e84589f9e8 {call_28:4} 488d1d '
                        '{ref_35:4} 488b3be8 {call_43:4} 4889c7e8 {call_51:4} 4c89f789c6e8 {call_61:4} 488b3be8 '
                        '{call_69:4} 4889c7e8 {call_77:4} 4c89f789c6e8 {call_87:4} 41c6466d01'),
            'shield_getter': (9, '554889e58b471c5dc3'),
            'armor_getter': (9, '554889e58b47205dc3'),
            'shield_setter': (28, '554889e589b79c000000f30f2ac6f30f1187900000005de9 {call_24:4}'),
            'armor_setter': (22, '554889e589b79800000089b7940000005de9 {call_18:4}'),
            'shield_assignment': (26, '498b4770488b40084a8b3c30be12000000e8 {call_18:4} 4189471c'),
            'armor_assignment': (26, '498b4770488b40084a8b3c30be14000000e8 {call_18:4} 41894720'),
            'reset': (8, '49c7471c00000000'),
            'loop_initial': (37,
                             '4531f6488d1d {ref_6:4} 4c8d25 {ref_13:4} 4d89f5488b48084a8b3c314885ff0f84 '
                             '{call_33:4}'),
            'loop_next': (20, '498b47704983c60849ffc5443b280f82 {call_16:4}'),
            'damage_permission': (18, 'e8 {call_1:4} 488b38be01000000e8 {call_14:4}'),
            'damage_setter': (13, '554889e54088b7ca0000005dc3'),
            'active': (7, 'c683c800000001')},
 'armv7': {'factory': (94,
                       '{call_0:4} 0246032114981c910f990b9b8de80a004ff49661109b {call_26:4} '
                       '149c4ff0ff36089d28681c96 {call_42:4} 1c96 {call_48:4} 014620461c96 {call_58:4} 28681c96 '
                       '{call_66:4} 1c96 {call_72:4} 014620461c96 {call_82:4} 1498012180f86910'),
           'shield_getter': (4, 'c0697047'),
           'armor_getter': (4, '006a7047'),
           'shield_setter': (24, '41ec301bc0f89410bbff200680ed220a20ef1001 {call_20:4}'),
           'armor_setter': (12, 'c0f88c10c0f89010 {call_8:4}'),
           'shield_assignment': (14, 'e06e122140688059 {call_8:4} e061'),
           'armor_assignment': (14, 'e06e142140688059 {call_8:4} 2062'),
           'zero_vector': (4, 'c0ef5000'),
           'reset': (12, '04f11c0084f85c2040f98f0a'),
           'loop_offset': (8, '0026a060e16e0868'),
           'loop_initial': (4, '0025 {call_2:2}'),
           'loop_next': (14, 'e16e0868013504368542 {call_10:4}'),
           'damage_permission': (16, '{call_0:4} 00680121cdf85068 {call_12:4}'),
           'damage_setter': (6, '80f8c2107047'),
           'active': (36, '01214ff0ff35c6f8d00086f8701004acc6f80c1186f8440086f8450086f8680086f8c010')}}
