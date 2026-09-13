"""Recover two catalogue-indexed light-mesh layers from supported ship factories.

The original compiler uses bit masks on x86-64 and sentinel checks on ARM. Both
must agree with the referenced tables. Only mesh IDs and provenance are exported;
engine flames, LOD selection and special ship construction are separate features.
"""
import re
import struct

from .ship_models import section_bytes


def lit(value):
    return re.escape(bytes.fromhex(value))


def table(mach, address, count):
    value = section_bytes(mach, address, count * 2, b'__const')
    return (list(struct.unpack('<' + str(count) + 'H', value[0])), value[1]) if value else None


def extract_ship_lights(mach, models):
    count = len(models.get('resource_ids', []))
    if not 1 <= count <= 64:
        return {}
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    base = section['address']
    file_base = section['offset'] + mach.slice_offset
    candidates = []
    if mach.architecture == 'x86_64':
        root_pattern = lit('4d63f4488d05') + rb'(.{4})' + lit('420fb73470488b15') + rb'.{4}' + lit('4c89ffb901000000e8') + rb'.{4}'
        first_pattern = (lit('48b8') + rb'(.{8})' + lit('4c0fa3f073') + rb'(.)' + lit('488d05') + rb'(.{4})'
            + lit('420fb73470488b3d') + rb'.{4}' + lit('488d95d0feffffb901000000e8') + rb'.{4}'
            + lit('488b3d') + rb'.{4}' + lit('488db5d4feffffe8') + rb'.{4}'
            + lit('8b95d0feffff8bb5d4feffff488b3d') + rb'.{4}' + lit('e8') + rb'.{4}'
            + lit('8bb5d4feffff4c89ffe8') + rb'(.{4})' + lit('8b85d0feffff41894728'))
        second_pattern = (lit('48b8') + rb'(.{8})' + lit('4c0fa3f073') + rb'(.)'
            + lit('c785c8feffffffffffff488b3d') + rb'.{4}' + lit('488db5c8feffffe8') + rb'.{4}'
            + lit('488d05') + rb'(.{4})' + lit('420fb714708bb5c8feffff488b3d') + rb'.{4}'
            + lit('31c9e8') + rb'.{4}' + lit('8bb5c8feffff4c89ffe8') + rb'(.{4})')
    else:
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        root_pattern = rb'(.{4})' + lit('0623') + rb'(.{4}).{8}' + lit('79447a44499031f81610499812684b9301230596') + rb'.{4}'
        first_pattern = (rb'(.{4})(.{4})' + lit('059a784430f812104ff0ff30924610900f904ff6ff708142') + rb'(.{2})'
            + lit('499c') + rb'.{8}' + lit('0faa78444ff0ff350123064630684b95') + rb'.{4}'
            + lit('306810a94b95') + rb'.{4}' + lit('30680f9a10994b95') + rb'.{4}'
            + lit('109920464b95') + rb'(.{4})' + lit('0f9849990862'))
        second_pattern = (rb'(.{4})(.{4})' + lit('784430f81a404ff6ff708442') + rb'(.{2})'
            + lit('4ff0ff36ddf824810d96') + rb'.{8}' + lit('0da97844054628684b96') + rb'.{4}'
            + lit('286822460d9900234b96') + rb'.{4}' + lit('0d9940464b96') + rb'(.{4})')

    def arm_target(raw, address, mnemonic):
        ins = list(decoder.disasm(raw, address))
        if len(ins) != 1 or ins[0].mnemonic != mnemonic:
            return None
        return ins[0].operands[0].imm

    def arm_table(match, origin, root=False):
        low = list(decoder.disasm(match[1], origin + match.start(1)))
        high = list(decoder.disasm(match[2], origin + match.start(2)))
        register = 'r1' if root else 'r0'
        if len(low) != 1 or len(high) != 1 or low[0].mnemonic != 'movw' or high[0].mnemonic != 'movt' \
                or low[0].op_str.split(',')[0] != register or high[0].op_str.split(',')[0] != register:
            return None
        # PC-relative ADD follows root's resource-manager pointer pair, or the
        # first light table's stack index reload, or immediately the second pair.
        pc_offset = 18 if root else (10 if match.re.pattern == first_pattern else 8)
        return low[0].operands[1].imm + (high[0].operands[1].imm << 16) + origin + match.start() + pc_offset + 4

    for root in re.finditer(root_pattern, code, re.S):
        if mach.architecture == 'x86_64':
            root_address = base + root.start(1) + 4 + struct.unpack('<i', root[1])[0]
        else:
            if root.start() % 2: continue
            root_address = arm_table(root, base, True)
            if root_address is None: continue
        root_table = table(mach, root_address, count)
        if not root_table or root_table[1] not in models.get('table_offsets', []) or root_table[0] != models['resource_ids']:
            continue
        window = code[root.end():root.end() + 400]
        origin = base + root.end()
        first = list(re.finditer(first_pattern, window, re.S))
        second = list(re.finditer(second_pattern, window, re.S))
        if len(first) != 1 or len(second) != 1 or first[0].end() > second[0].start():
            continue
        layers, origins, targets = [], [], []
        for match in (first[0], second[0]):
            if mach.architecture == 'x86_64':
                address = origin + match.start(3) + 4 + struct.unpack('<i', match[3])[0]
                if match.start(2) + 1 + match[2][0] != match.end(): break
                target = origin + match.start(4) + 4 + struct.unpack('<i', match[4])[0]
            else:
                address = arm_table(match, origin)
                if address is None: break
                if arm_target(match[3], origin + match.start(3), 'beq') != origin + match.end(): break
                target = arm_target(match[4], origin + match.start(4), 'bl')
            value = table(mach, address, count)
            if not value or target is None: break
            if mach.architecture == 'x86_64':
                mask = struct.unpack('<Q', match[1])[0]
                if mask >> count or any(bool(mask >> i & 1) != (id != 65535) for i, id in enumerate(value[0])): break
            layers.append(value[0]); targets.append(target)
            origins.extend([{'offset': value[1], 'bytes': count * 2},
                            {'offset': file_base + root.end() + match.start(), 'bytes': len(match[0])}])
        if len(layers) != 2 or targets[0] != targets[1]:
            continue
        candidates.append({'resource_ids': [list(pair) for pair in zip(*layers)],
                           'provenance': [{'offset': file_base + root.start(), 'bytes': len(root[0])}] + origins})
    return candidates[0] if len(candidates) == 1 else {}
