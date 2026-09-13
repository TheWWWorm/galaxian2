"""Read manual angular-unit constants; no input-response logic is exported."""
import math
import re
import struct
from .ship_models import section_bytes


def lit(value):
    return re.escape(bytes.fromhex(value))


def extract_manual_rotation(mach, cruise):
    if not cruise:
        return {}
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    base = text['address']
    if mach.architecture == 'x86_64':
        consumer = lit('f3410f10842414030000f30f59c1f30f59c3f30f59c4f30f59c2f3410f598c2418030000f30f59cbf30f59ccf30f59caf3410f10104c89f6e8') + rb'(.{4})'
        helper = bytes.fromhex('554889e54883ec504889f848ba3c00000000000000488975f8f30f1145f4f30f114df0f30f1155ecf30f5a45f4')
    elif mach.architecture == 'armv7':
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        consumer = (rb'(.{4})' + lit('94ed9d1a94ed9e2a') + rb'.{4}' + lit('41ff104d') + rb'.{4}'
                    + lit('42ff102d') + rb'(.{4})' + lit('784444ff900d006842ff902d') + rb'(.{4})'
                    + lit('48ff300d48ff322d00ff901d02ff900d11ee102a10ee103a90ed000a28a88ded000a20ef1001') + rb'(.{4})')
        helper = bytes.fromhex('80b56f468eb043ec103bb0ee402a42ec102bb0ee404a97ed026a3c22')
    else:
        return {}
    matches = [m for m in re.finditer(consumer, code, re.S)
               if mach.architecture == 'x86_64' or m.start() % 2 == 0]
    if len(matches) != 1:
        return {}
    match = matches[0]
    regions = []
    def extent(at, length):
        return {'offset': mach.slice_offset + text['offset'] + at, 'bytes': length}
    if mach.architecture == 'x86_64':
        loads = list(re.finditer(lit('f30f1015') + rb'(.{4})' + lit('f30f101d') + rb'(.{4})' + lit('f30f100d') + rb'(.{4})',
                                 code[max(0, match.start() - 512):match.start()], re.S))
        if len(loads) != 1:
            return {}
        load = loads[0]
        at = max(0, match.start() - 512) + load.start()
        # The three inputs are time scale, radians/turn, then source angle units.
        addresses = [base + at + i * 8 + 8 + struct.unpack('<i', load[i + 1])[0] for i in range(3)]
        addresses.reverse()
        target = base + match.end() + struct.unpack('<i', match[1])[0]
        regions.append(extent(at, len(load[0])))
    else:
        addresses = []
        for group in (1, 2, 3):
            ins = list(decoder.disasm(match[group], base + match.start(group)))
            if len(ins) != 1 or ins[0].mnemonic != 'vldr' or len(ins[0].operands) != 2 \
                    or ins[0].operands[0].reg != capstone.arm.ARM_REG_S0 \
                    or ins[0].operands[1].type != capstone.arm.ARM_OP_MEM \
                    or ins[0].operands[1].mem.base != capstone.arm.ARM_REG_PC:
                return {}
            addresses.append(((ins[0].address + 4) & ~3) + ins[0].operands[1].mem.disp)
        branch = list(decoder.disasm(match[4], base + match.start(4)))
        if len(branch) != 1 or branch[0].mnemonic != 'bl':
            return {}
        target = branch[0].operands[0].imm
    regions.append(extent(match.start(), len(match[0])))
    values = []
    for address in addresses:
        sections = [s for s in mach.sections if s['segment'] == b'__TEXT' and s['offset'] > 0
                    and s['address'] <= address and address + 4 <= s['address'] + s['length']]
        if len(sections) != 1:
            return {}
        s = sections[0]
        offset = s['offset'] + address - s['address']
        if offset + 4 > len(mach.data):
            return {}
        value = struct.unpack_from('<f', mach.data, offset)[0]
        if not math.isfinite(value) or value <= 0:
            return {}
        values.append(value)
        regions.append({'offset': offset + mach.slice_offset, 'bytes': 4})
    if values[0] > 1 or values[1] > 10 or values[2] > 1:
        return {}
    found = section_bytes(mach, target, len(helper), b'__text')
    if found is None or found[0] != helper:
        return {}
    regions.append({'offset': found[1], 'bytes': len(helper)})
    return dict(zip(('angle_unit_scale', 'radians_per_turn', 'time_scale'), values),
                rotation_order='local_x_y', provenance=regions)
