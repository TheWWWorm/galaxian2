"""Bounded font-setup declarations; emits IDs and spacing tables, never code."""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

MAC = """
554889e58d46f783f8050f87ee000000488d0d
{ref_10:4}
486304814801c8ffe0488b3d
{ref_20:4}
488d15
{ref_27:4}
be
{value_2e:4}
b901000000e8
{call_38:4}
66b8
{value_3d:2}
8b35
{ref_41:4}
488b3d
{ref_47:4}
f605
{ref_4e:4}
01751366b9
{value_57:2}
f605
{ref_5b:4}
0166b8
{value_62:2}
660f45c10fbfd0e8
{call_6d:4}
488b05
{ref_72:4}
c6403000e942010000488b3d
{ref_82:4}
488d15
{ref_89:4}
be
{value_90:4}
b901000000e8
{call_9a:4}
66b8
{value_9f:2}
8b35
{ref_a3:4}
488b3d
{ref_a9:4}
f605
{ref_b0:4}
01751366b9
{value_b9:2}
f605
{ref_bd:4}
0166b8
{value_c4:2}
660f45c10fbfd0e9e0000000488b3d
{ref_d4:4}
488d15
{ref_db:4}
be
{value_e2:4}
ebac488b3d
{ref_e9:4}
488d15
{ref_f0:4}
be
{value_f7:4}
eb97488b3d
{ref_fe:4}
488d15
{ref_105:4}
83fe0f753dbe
{value_111:4}
b901000000e8
{call_11b:4}
66b8
{value_120:2}
8b35
{ref_124:4}
488b3d
{ref_12a:4}
f605
{ref_131:4}
01759266b9
{value_13a:2}
f605
{ref_13e:4}
0166b8
{value_145:2}
e97affffffbe
{value_14e:4}
b901000000e8
{call_158:4}
f605
{ref_15d:4}
0174148b35
{ref_166:4}
488b3d
{ref_16c:4}
ba
{value_173:4}
eb3af605
{ref_17a:4}
01740f8b35
{ref_183:4}
488b3d
{ref_189:4}
eb168b35
{ref_192:4}
488b3d
{ref_198:4}
f605
{ref_19f:4}
017407ba
{value_1a8:4}
eb05ba
{value_1af:4}
e8
{call_1b4:4}
488b05
{ref_1b9:4}
c6403001488b3d
{ref_1c4:4}
488d15
{ref_1cb:4}
be
{value_1d2:4}
b901000000e8
{call_1dc:4}
8b35
{ref_1e1:4}
488b3d
{ref_1e7:4}
31d2e8
{call_1f0:4}
488d15
{ref_1f5:4}
488b3d
{ref_1fc:4}
be
{value_203:4}
b901000000e8
{call_20d:4}
8b35
{ref_212:4}
488b3d
{ref_218:4}
31d25de9
{call_222:4}
0f1f00f6fdffff58feffffaafeffffd4feffffd4feffffbffeffff
"""
ARM = """
f0b5a1f1090003af052823d8dfe800f0036c7b22228a
{value_16:4}
{value_1a:4}
{value_1e:4}
01237d442868
{value_28:4}
{value_2c:4}
7c442246
{call_34:4}
{value_38:4}
{value_3c:4}
21687a4428681278002a00f0ac80
{value_4e:4}
b4e0
{value_54:4}
0f29
{value_5a:4}
7d442868
{value_62:4}
{value_66:4}
7c4412d1
{value_6e:4}
224601230126
{call_78:4}
{value_7c:4}
{value_80:4}
21687a4428681278a2b1
{value_8e:4}
71e0
{value_94:4}
22460123
{call_9c:4}
{value_a0:4}
{value_a4:4}
7844007888b12168
{value_b0:4}
286871e0
{value_b8:4}
{value_bc:4}
7a441378
{value_c4:4}
002b18bf
{value_cc:4}
52e0
{value_d2:4}
{value_d6:4}
78440078002850d02168286857e0
{value_e8:4}
0126
{value_ee:4}
{value_f2:4}
7d442868
{value_fa:4}
{value_fe:4}
7c441ce0
{value_106:4}
0126
{value_10c:4}
{value_110:4}
7d442868
{value_118:4}
{value_11c:4}
7c440de0
{value_124:4}
0126
{value_12a:4}
{value_12e:4}
7d442868
{value_136:4}
{value_13a:4}
7c4422460123
{call_144:4}
{value_148:4}
{value_14c:4}
21687a442868127812b1
{value_15a:4}
0be0
{value_160:4}
{value_164:4}
7a441378
{value_16c:4}
002b18bf
{value_174:4}
12b2
{call_17a:4}
2868067722e0
{value_184:4}
{value_188:4}
21687a4428681278002a40d0
{value_198:4}
{call_19c:4}
2868012110e0
{value_1a6:4}
{value_1aa:4}
7a441378
{value_1b2:4}
002b18bf
{value_1ba:4}
12b2
{call_1c0:4}
286800210177
{value_1ca:4}
{value_1ce:4}
{value_1d2:4}
01237c442246
{call_1dc:4}
{value_1e0:4}
0022
{value_1e6:4}
21687d442868
{call_1f0:4}
{value_1f4:4}
{value_1f8:4}
{value_1fc:4}
28687c4401232246
{call_208:4}
216800222868bde8f040
{call_216:4}
{value_21a:4}
bde7
"""
MAC_REFS = [[('ref_10', 23)], [('ref_20', 39), ('ref_47', 78), ('ref_72', 121), ('ref_82', 137), ('ref_a9', 176), ('ref_d4', 219), ('ref_e9', 240), ('ref_fe', 261), ('ref_12a', 305), ('ref_16c', 371), ('ref_189', 400), ('ref_198', 415), ('ref_1b9', 448), ('ref_1c4', 459), ('ref_1e7', 494), ('ref_1fc', 515), ('ref_218', 543)], [('ref_27', 46), ('ref_41', 71), ('ref_89', 144), ('ref_a3', 169), ('ref_db', 226), ('ref_f0', 247), ('ref_105', 268), ('ref_124', 298), ('ref_166', 364), ('ref_183', 393), ('ref_192', 408)], [('ref_4e', 85), ('ref_b0', 183), ('ref_131', 312), ('ref_19f', 422)], [('ref_5b', 98), ('ref_bd', 196), ('ref_13e', 325), ('ref_15d', 356)], [('ref_17a', 385)], [('ref_1cb', 466), ('ref_1e1', 487)], [('ref_1f5', 508), ('ref_212', 536)]]
MAC_CALLS = [[('call_38', 61), ('call_9a', 159), ('call_11b', 288), ('call_158', 349), ('call_1dc', 481), ('call_20d', 530)], [('call_6d', 114), ('call_1b4', 441), ('call_1f0', 501), ('call_222', 551)]]
ARM_FIELDS = {'value_16': ('movw', 'r5'), 'value_1a': ('movw', 'r1'), 'value_1e': ('movt', 'r5'), 'value_28': ('movw', 'r4'), 'value_2c': ('movt', 'r4'), 'value_38': ('movw', 'r2'), 'value_3c': ('movt', 'r2'), 'value_4e': ('movw', 'r2'), 'value_54': ('movw', 'r5'), 'value_5a': ('movt', 'r5'), 'value_62': ('movw', 'r4'), 'value_66': ('movt', 'r4'), 'value_6e': ('movw', 'r1'), 'value_7c': ('movw', 'r2'), 'value_80': ('movt', 'r2'), 'value_8e': ('movw', 'r2'), 'value_94': ('movw', 'r1'), 'value_a0': ('movw', 'r0'), 'value_a4': ('movt', 'r0'), 'value_b0': ('mvn', 'r2'), 'value_b8': ('movw', 'r2'), 'value_bc': ('movt', 'r2'), 'value_c4': ('mvn', 'r2'), 'value_cc': ('mvnne', 'r2'), 'value_d2': ('movw', 'r0'), 'value_d6': ('movt', 'r0'), 'value_e8': ('movw', 'r5'), 'value_ee': ('movt', 'r5'), 'value_f2': ('movw', 'r1'), 'value_fa': ('movw', 'r4'), 'value_fe': ('movt', 'r4'), 'value_106': ('movw', 'r5'), 'value_10c': ('movt', 'r5'), 'value_110': ('movw', 'r1'), 'value_118': ('movw', 'r4'), 'value_11c': ('movt', 'r4'), 'value_124': ('movw', 'r5'), 'value_12a': ('movt', 'r5'), 'value_12e': ('movw', 'r1'), 'value_136': ('movw', 'r4'), 'value_13a': ('movt', 'r4'), 'value_148': ('movw', 'r2'), 'value_14c': ('movt', 'r2'), 'value_15a': ('movw', 'r2'), 'value_160': ('movw', 'r2'), 'value_164': ('movt', 'r2'), 'value_16c': ('mvn', 'r2'), 'value_174': ('mvnne', 'r2'), 'value_184': ('movw', 'r2'), 'value_188': ('movt', 'r2'), 'value_198': ('mvn', 'r2'), 'value_1a6': ('movw', 'r2'), 'value_1aa': ('movt', 'r2'), 'value_1b2': ('mvn', 'r2'), 'value_1ba': ('mvnne', 'r2'), 'value_1ca': ('movw', 'r4'), 'value_1ce': ('movw', 'r1'), 'value_1d2': ('movt', 'r4'), 'value_1e0': ('movw', 'r5'), 'value_1e6': ('movt', 'r5'), 'value_1f4': ('movw', 'r4'), 'value_1f8': ('movw', 'r1'), 'value_1fc': ('movt', 'r4'), 'value_21a': ('mvn', 'r2')}
ARM_REFS = [[('value_16', 'value_1e', 40), ('value_54', 'value_5a', 98), ('value_e8', 'value_ee', 250), ('value_106', 'value_10c', 280), ('value_124', 'value_12a', 310), ('value_1e0', 'value_1e6', 496)], [('value_28', 'value_2c', 52), ('value_62', 'value_66', 110), ('value_fa', 'value_fe', 262), ('value_118', 'value_11c', 292), ('value_136', 'value_13a', 322)], [('value_38', 'value_3c', 70), ('value_7c', 'value_80', 138), ('value_148', 'value_14c', 342), ('value_184', 'value_188', 402)], [('value_a0', 'value_a4', 172), ('value_b8', 'value_bc', 196), ('value_160', 'value_164', 364), ('value_1a6', 'value_1aa', 434)], [('value_d2', 'value_d6', 222)], [('value_1ca', 'value_1d2', 476)], [('value_1f4', 'value_1fc', 518)]]
ARM_CALLS = [[('call_34', 52, 'bl'), ('call_78', 120, 'bl'), ('call_9c', 156, 'bl'), ('call_144', 324, 'bl'), ('call_1dc', 476, 'bl'), ('call_208', 520, 'bl')], [('call_17a', 378, 'bl'), ('call_19c', 412, 'bl'), ('call_1c0', 448, 'bl'), ('call_1f0', 496, 'bl'), ('call_216', 534, 'b.w')]]


def extract_font_selection(mach):
    import capstone
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    matches = [m for m in template((MAC, MAC_ALTERNATE) if mac else ARM).finditer(code) if mac or m.start() % 2 == 0]
    if len(matches) != 1: return {}
    match = matches[0]
    address = section['address'] + match.start()
    values = {}
    if mac:
        for key, raw in match.groupdict().items():
            if key.startswith('value_'): values[key] = int.from_bytes(raw, 'little', signed=True)
        def reference(key):
            end = next(end for group in MAC_REFS for name, end in group if name == key)
            return address + end + struct.unpack("<i", match[key])[0]
        if reference("ref_10") != address + len(match[0]) - 24: return {}
        profile_globals = {"medium": reference("ref_4e"), "large": reference("ref_5b"), "wide": reference("ref_17a")}
        targets = []
        for group in MAC_REFS + MAC_CALLS:
            row = {address + end + struct.unpack('<i', match[key])[0] for key, end in group}
            if len(row) != 1: return {}
            targets.extend(row)
        if len(set(targets)) != len(targets): return {}
        if [values['value_3d'], values['value_57'], values['value_62']] != [values['value_9f'], values['value_b9'], values['value_c4']]: return {}
        font_keys = ['2e', '90', 'e2', 'f7', '111', '14e', '1d2', '203']
        normal = [values['value_1af'], values['value_1a8'], values['value_1a8'], values['value_173']]
        cjk = [values['value_c4'], values['value_9f'], values['value_c4'], values['value_b9']]
        japanese = [values['value_145'], values['value_120'], values['value_145'], values['value_13a']]
    else:
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        for key, (mnemonic, register) in ARM_FIELDS.items():
            ins = list(decoder.disasm(match[key], address + match.start(key) - match.start()))
            if len(ins) != 1 or ins[0].mnemonic != ("mvn" if mnemonic == "mvnne" else mnemonic) or len(ins[0].operands) != 2 or ins[0].reg_name(ins[0].operands[0].reg) != register or ins[0].operands[1].type != capstone.arm.ARM_OP_IMM: return {}
            number = ins[0].operands[1].imm
            values[key] = ~number if mnemonic.startswith('mvn') else number
        def reference(key):
            lo, hi, pc = next(row for group in ARM_REFS for row in group if row[0] == key)
            return address + pc + (values[hi] << 16 | values[lo])
        profile_globals = {"medium": reference("value_38"), "large": reference("value_a0"), "wide": reference("value_d2")}
        targets = []
        for group in ARM_REFS:
            row = {address + pc + (values[hi] << 16 | values[lo]) for lo, hi, pc in group}
            if len(row) != 1: return {}
            targets.extend(row)
        for group in ARM_CALLS:
            row = set()
            for key, at, mnemonic in group:
                ins = list(decoder.disasm(match[key], address + at))
                if len(ins) != 1 or ins[0].mnemonic != mnemonic or ins[0].operands[0].type != capstone.arm.ARM_OP_IMM: return {}
                row.add(ins[0].operands[0].imm)
            if len(row) != 1: return {}
            targets.extend(row)
        if len(set(targets)) != len(targets): return {}
        def signed(key):
            value = values['value_' + key]
            return value - 65536 if value > 32767 else value
        font_keys = ['1a', 'f2', '110', '12e', '6e', '94', '1ce', '1f8']
        normal = [signed('21a'), signed('198'), signed('198'), signed('b0')]
        cjk = [signed('16c'), signed('15a'), signed('16c'), signed('174')]
        japanese = [signed('c4'), signed('8e'), signed('c4'), signed('cc')]
        if [signed('4e'), signed('1b2'), signed('1ba')] != [cjk[1], cjk[0], cjk[3]]: return {}
    fonts = [values['value_' + key] for key in font_keys]
    if any(not 0 <= value < 65535 for value in fonts) or any(not -32 <= value <= 32 for row in [normal, cjk, japanese] for value in row): return {}
    # Modes name three independent source flags by their declaration order;
    # platform/display detection is separate. Native code never uses addresses.
    return {'_profile_globals': profile_globals, 'default_font_id': fonts[5], 'secondary_font_id': fonts[6], 'language_font_id': fonts[7],
            'overrides': [{'language_id': language, 'font_id': font} for language, font in zip([9, 10, 11, 14, 15], fonts[:5])],
            'spacing': {'default': normal, 'cjk': cjk, 'japanese': japanese},
            'source_offset': mach.slice_offset + section['offset'] + match.start(), 'source_bytes': len(match[0])}


# Same dispatch and declarations; the newer Mac compiler uses a one-byte NOP
# before the six-entry table. Each table displacement changes by exactly two.
MAC_ALTERNATE = MAC.replace('0f1f00f6fdffff58feffffaafeffffd4feffffd4feffffbffeffff',
                            '90f8fdffff5afeffffacfeffffd6feffffd6feffffc1feffff')
