"""Recover the ordinary scene frame cap and validate its millisecond supplier."""
import re
import struct
from .steering import lit
from .ship_models import section_bytes


def extract_frame_clock(mach, pilot):
    if not pilot: return {}
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    base = text['address']
    mac = mach.architecture == 'x86_64'
    if mac:
        pattern = lit('498b7d10e8') + rb'(.{4})' + lit('3d') + rb'(.{4})' + lit('7f12498b7d10e8') + rb'(.{4})' + lit('4889c131c085c97822498b7d10e8') + rb'(.{4})' + lit('4889c1b8') + rb'(.{4})' + lit('81f9') + rb'(.{4})' + lit('7f09498b7d10e8') + rb'(.{4})' + lit('41894548')
        helper = bytes.fromhex('554889e548897df8488b7df8488b87c0000000482b87c80000005dc3')
        call_groups, cap_groups = (1, 3, 4, 7), (2, 5, 6)
    elif mach.architecture == 'armv7':
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        pattern = rb'(.)' + lit('2c08dcdbf808004ff0ff31b491') + rb'(.{4})' + lit('002810dbdbf808004ff0ff34b494') + rb'(.{4})(.)' + lit('2801dd') + rb'(.)' + lit('2006e0dbf80800b494') + rb'(.{4})' + lit('00e0002000ee900b')
        helper = bytes.fromhex('82b00190c16e026f436f806fc91a62eb000000900846009902b07047')
        call_groups, cap_groups = (2, 3, 6), (1, 4, 5)
    else: return {}
    matches = [m for m in re.finditer(pattern, code, re.S) if mac or m.start() % 2 == 0]
    if len(matches) != 1: return {}
    match = matches[0]
    caps = [struct.unpack('<I', match[g])[0] if mac else match[g][0] for g in cap_groups]
    if len(set(caps)) != 1 or not 1 <= caps[0] <= 1000: return {}
    targets = []
    for group in call_groups:
        address = base + match.start(group)
        if mac: target = address + 4 + struct.unpack('<i', match[group])[0]
        else:
            ins = list(decoder.disasm(match[group], address))
            if len(ins) != 1 or ins[0].mnemonic != 'bl': return {}
            target = ins[0].operands[0].imm
        targets.append(target)
    if len(set(targets)) != 1: return {}
    found = section_bytes(mach, targets[0], len(helper), b'__text')
    if found is None or found[0] != helper: return {}
    return {'max_frame_milliseconds': caps[0], 'time_unit': 'milliseconds',
            'provenance': [{'offset': mach.slice_offset + text['offset'] + match.start(), 'bytes': len(match[0])},
                           {'offset': found[1], 'bytes': len(helper)}]}
