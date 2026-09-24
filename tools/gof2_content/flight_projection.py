"""Import flight perspective parameters; never emit original executable code.

The location-match input is deliberately not bound to a guessed world/save field.
Its native owner must supply verified state before selecting a far plane.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes


def extract_flight_projection(mach):
    if mach.architecture not in ['x86_64', 'armv7']: return {}
    import capstone
    mac = mach.architecture == 'x86_64'
    prefix = 'MAC_' if mac else 'ARM_'
    text = mach.text; base = text['address']
    code = mach.data[text['offset']:text['offset'] + text['length']]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB); decoder.detail = True
    provenance = {}; blocks = {}
    def require(value):
        if not value: raise ValueError('Unsupported flight projection context')
    def ins(m, field):
        rows = list(decoder.disasm(m[field], base + m.start(field)))
        require(len(rows) == 1 and rows[0].size == len(m[field])); return rows[0]
    def dest(m, field):
        if mac: return base + m.end(field) + int.from_bytes(m[field], 'little', signed=True)
        i = ins(m, field)
        if field.startswith('literal_'):
            require(i.operands[1].type == 3 and i.reg_name(i.operands[1].mem.base) == 'pc')
            return ((i.address + 4) & ~3) + i.operands[1].mem.disp
        if field.startswith('address_'): return ((i.address + 4) & ~3) + i.operands[1].imm
        require(i.operands[-1].type == 2); return i.operands[-1].imm
    def match(key, address=None):
        name = prefix + key.upper()
        spec = (globals()[name], MAC_ALTERNATES[key]) if mac and key in MAC_ALTERNATES else globals()[name]
        matches = [m for m in template(spec).finditer(code) if (mac or m.start() % 2 == 0) and (address is None or base + m.start() == address)]
        require(len(matches) == 1); m = matches[0]
        if not mac:
            for field, expected in ARM_FIELDS[name].items():
                i = ins(m, field); require(i.mnemonic == expected['kind'])
                if 'register' in expected: require(i.reg_name(i.operands[0].reg) == expected['register'])
        provenance[key] = {'offset': mach.slice_offset + text['offset'] + m.start(), 'bytes': len(m[0])}
        blocks[key] = m; return m
    def read(key, address, size, section):
        found = section_bytes(mach, address, size, section); require(found is not None)
        provenance[key] = {'offset': found[1], 'bytes': size}; return found[0]
    def branch(m, field, offset): require(dest(m, field) == base + m.start() + offset)
    try:
        start = match('start')
        setter = match('setter', dest(start, 'call_61' if mac else 'call_60'))
        predicate = match('predicate', dest(start, 'call_14' if mac else 'call_18'))
        compare = match('compare', dest(predicate, 'call_12' if mac else 'jump_6'))
        metrics = match('metrics', dest(setter, 'call_ab' if mac else 'call_bc'))
        cursor = read('cursor', dest(start, 'call_31' if mac else 'call_28'), 12 if mac else 6, b'__text')
        require(cursor == bytes.fromhex('554889e58b87780200005dc3' if mac else 'd0f8d4017047'))
        if mac:
            branch(start, 'jump_1b', 0x27); branch(start, 'jump_25', 0x4b)
            require(dest(start, 'ref_0') == dest(start, 'ref_27'))
            branch(compare, 'jump_9', 0x14)
            for field, offset in [('jump_2f',0x3a),('jump_35',0xcf),('jump_bd',0xcf)]: branch(setter,field,offset)
            for field, offset in [('jump_2d',0x38),('jump_33',0x176 if 'call_7c' in metrics.groupdict() else 0x167)]: branch(metrics,field,offset)
            fov = struct.unpack('<f', read('fov',dest(start,'ref_4b'),4,b'__const'))[0]
            near = struct.unpack('<f', read('near',dest(start,'ref_53'),4,b'__const'))[0]
            fallback = struct.unpack('<f', read('fallback',dest(start,'ref_1d'),4,b'__const'))[0]
            far = list(struct.unpack('<2f',read('far',dest(start,'ref_3f'),8,b'__const')))
        else:
            branch(start,'jump_1e',0x3a); branch(start,'jump_38',0x3e)
            for field, offset in [('jump_36',0x3a),('jump_38',0xd4),('jump_ca',0xd4)]: branch(setter,field,offset)
            for field, offset in [('jump_4c',0x50),('jump_4e',0x186)]: branch(metrics,field,offset)
            for field in ['word_2e','word_52','word_92','word_b8']: require(ins(metrics,field).operands[1].imm == 0)
            fov = struct.unpack('<f',struct.pack('<I',ins(start,'word_3e').operands[1].imm | (ins(start,'word_4a').operands[1].imm << 16)))[0]
            near = struct.unpack('<f',struct.pack('<I',ins(start,'word_4e').operands[1].imm << 16))[0]
            fallback = struct.unpack('<f',read('fallback',dest(start,'literal_3a'),4,b'__text'))[0]
            far = list(struct.unpack('<2f',read('far',dest(start,'address_2c'),8,b'__text')))
        for m in blocks.values():
            for field in m.groupdict():
                if field.startswith(('call_', 'jump_')):
                    address = dest(m,field)
                    require(section_bytes(mach,address,2,b'__text') is not None or section_bytes(mach,address,6 if mac else 16,b'__stubs' if mac else b'__picsymbolstub4') is not None)
        require(all(math.isfinite(v) for v in [fov,near,*far]) and 0 < fov < math.pi and 0 < near < min(far) and max(far) <= 1e9 and fallback == far[0])
        return {'vertical_fov_radians': fov, 'near': near, 'far': far[0], 'matching_location_early_far': far[1],
                'early_cursor_limit': 80, 'fov_axis': 'vertical', 'provenance': provenance}
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,struct.error): return {}

MAC_START = """
488d05
{ref_0:4}
448bb3340100004d8b3f488b38e8
{call_14:4}
84c075
{jump_1b:1}
f30f1015
{ref_1d:4}
eb
{jump_25:1}
488d05
{ref_27:4}
488b38e8
{call_31:4}
83f8500f9cc00fb6c0488d0d
{ref_3f:4}
f30f101481f30f1005
{ref_4b:4}
f30f100d
{ref_53:4}
4c89ff4489f6e8
{call_61:4}
"""

ARM_START = """
{word_0:4}
{word_4:4}
d6f8e88078442d6804682068cdf840a0
{call_18:4}
0128
{jump_1e:2}
20684ff0ff311091
{call_28:4}
{address_2c:2}
5028b8bf043191ed000a
{jump_38:2}
{literal_3a:4}
{word_3e:4}
002306944ff0ff34
{word_4a:4}
{word_4e:4}
2846414610948ded000a20ef1001
{call_60:4}
"""

MAC_SETTER = """
554889e54883ec4048897df88975f4f30f1145f0f30f114decf30f1155e8488b7df88b75f43bb7c801000048897de00f82
{jump_2f:4}
e9
{jump_35:4}
f30f1045f0f30f104decf30f1055e8488b7de0f30f1155dcf30f1145d8f30f114dd4e8
{call_5c:4}
f30f2ad8488b7de0f30f115dd0e8
{call_6e:4}
f30f2ae0488b7de04881c7c80100008b75f4f30f1165cce8
{call_8a:4}
488b38f30f1045d8f30f104dd4f30f1055dcf30f105dd0f30f1065cce8
{call_ab:4}
488b45e08bb0e00100003b75f40f85
{jump_bd:4}
8b75f4488b7de0e8
{call_ca:4}
4883c4405dc3
"""

ARM_SETTER = """
80b56f468eb043ec103bb0ee402a42ec102bb0ee404a97ed026a0d900c918ded0b4a8ded0a2a8ded096a0d980c99d0f8642191420890
{jump_36:2}
{jump_38:2}
9ded0b0a9ded0a2a9ded094a08988ded070a8ded062a8ded054a
{call_54:4}
00ee100ab8eec00a08988ded040a
{call_66:4}
00ee100ab8eec00a089800f5b2700c998ded030a
{call_7e:4}
00689ded070a10ee101a029008469ded062a12ee101a9ded054a14ee102a9ded046a16ee103a9ded031a11ee109acdf80090ddf80890cdf80490
{call_bc:4}
0898d0f870110c9a9142
{jump_ca:2}
0c990898
{call_d0:4}
0eb080bd
"""

MAC_PREDICATE = """
554889e5488bb7b8000000488bbf18020000e8
{call_12:4}
5dc390
"""

ARM_PREDICATE = """
416fd0f88801
{jump_6:4}
"""

MAC_COMPARE = """
554889e530c04885f674
{jump_9:1}
8b47103b46100f94c05dc3
"""

ARM_COMPARE = """
02460020002908bf7047896892688a4208bf01207047
"""

MAC_METRICS = """
554889e54883ec40f30f1145fcf30f114df8f30f1155f4f30f115df0f30f1165ec48897de048817de0000000000f85
{jump_2d:4}
e9
{jump_33:4}
48b80100000000000000f2480f2ac048b80200000000000000f3480f2ac8f30f1055fc488b45e0f30f1110f30f1055f8488b45e0f30f115004f30f1055f4488b45e0f30f115008f30f1055fcf30f5ed1f20f1145d00f28c2f30f114dcce8
{call_95:4}
f30f104dfcf30f1055ccf30f5ecaf30f1145c80f28c1e8
{call_b0:4}
f30f104dc8f30f5ec8488b45e0f30f114848488b45e0f30f104048f30f104df0f30f5e4decf30f59c8488b45e0f30f11484cf30f1045f0f30f5e45ec488b45e0f30f114050
"""

# Complete alternate stack/register layouts. Arguments, branch links and
# referenced constants are still proved by the shared reader above.
MAC_ALTERNATES = {
    'setter': MAC_SETTER.replace('f30f1155dcf30f1145d8f30f114dd4', 'f30f1145dcf30f114dd8f30f1155d4')
                        .replace('f30f1045d8f30f104dd4f30f1055dc', 'f30f1045dcf30f104dd8f30f1055d4'),
    'metrics': '''
554889e54883ec30f30f1145fcf30f114df8f30f1155f4f30f115df0f30f1165ec48897de048817de0000000000f85
{jump_2d:4} e9 {jump_33:4}
48b80200000000000000f3480f2ac0f30f104dfc488b45e0f30f1108f30f104df8488b45e0f30f114804f30f104df4488b45e0f30f114808f30f104dfcf30f5ec80f28c1e8
{call_7c:4}
48b80200000000000000f3480f2ac8f30f1055fcf30f5ed1f30f1145d80f28c2e8
{call_a1:4}
48b80200000000000000f3480f2ac8f30f1055d8f30f5ed0488b45e0f30f115048488b45e0f30f104048f30f1055f0f30f5e55ecf30f59c2488b45e0f30f11404cf30f1045f0f30f5e45ec488b45e0f30f114050
''',
}

ARM_METRICS = """
80b56f468db043ec103bb0ee402a42ec102bb0ee404a41ec101bb0ee406a40ec100bb0ee401af86897ed023a0021
{word_2e:4}
8ded0c1a8ded0b6a8ded0a4a8ded092a8ded083a079007988842
{jump_4c:2}
{jump_4e:2}
0220
{word_52:4}
b0ee000a9ded0c2a079981ed002a9ded0b2a079981ed012a9ded0a2a079981ed022a9ded0c2a82ee000a10ee101a05900846
{call_88:4}
00ee100a0220
{word_92:4}
b0ee002a9ded0c4a84ee022a12ee101a049008468ded030a
{call_ae:4}
00ee100a0220
{word_b8:4}
b0ee002a9ded034a84ee000a079981ed120a079991ed120a9ded094a9ded086a84ee064a20ee040a079981ed130a9ded090a9ded084a80ee040a079981ed140a
"""

ARM_FIELDS = {'ARM_START': {'word_0': {'kind': 'movw', 'register': 'r0'}, 'word_4': {'kind': 'movt', 'register': 'r0'}, 'call_18': {'kind': 'bl'}, 'jump_1e': {'kind': 'bne'}, 'call_28': {'kind': 'bl'}, 'address_2c': {'kind': 'adr', 'register': 'r1'}, 'jump_38': {'kind': 'b'}, 'literal_3a': {'kind': 'vldr', 'register': 's0'}, 'word_3e': {'kind': 'movw', 'register': 'r2'}, 'word_4a': {'kind': 'movt', 'register': 'r2'}, 'word_4e': {'kind': 'movt', 'register': 'r3'}, 'call_60': {'kind': 'bl'}}, 'ARM_SETTER': {'jump_36': {'kind': 'blo'}, 'jump_38': {'kind': 'b'}, 'call_54': {'kind': 'bl'}, 'call_66': {'kind': 'bl'}, 'call_7e': {'kind': 'blx'}, 'call_bc': {'kind': 'bl'}, 'jump_ca': {'kind': 'bne'}, 'call_d0': {'kind': 'bl'}}, 'ARM_PREDICATE': {'jump_6': {'kind': 'b.w'}}, 'ARM_COMPARE': {}, 'ARM_METRICS': {'word_2e': {'kind': 'movt', 'register': 'r1'}, 'jump_4c': {'kind': 'bne'}, 'jump_4e': {'kind': 'b'}, 'word_52': {'kind': 'movt', 'register': 'r0'}, 'call_88': {'kind': 'bl'}, 'word_92': {'kind': 'movt', 'register': 'r0'}, 'call_ae': {'kind': 'bl'}, 'word_b8': {'kind': 'movt', 'register': 'r0'}}}
