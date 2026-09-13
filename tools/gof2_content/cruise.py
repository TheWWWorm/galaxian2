"""Recover the ordinary forward cruise scalar from bounded declaration layouts.

Constructor and reset values must agree, and a matching displacement consumer
must call the supported forward-transform helper. No boost/steering logic is
emitted. Milliseconds and local +Z are verified semantics of these layouts.
"""
import math
import re
import struct

from .ship_models import section_bytes


def literal(value):
    return re.escape(bytes.fromhex(value))


def extract_cruise(mach):
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    base = section['address']
    origin = section['offset'] + mach.slice_offset
    if mach.architecture == 'x86_64':
        initial = literal('c783f8000000') + rb'(.{4})' + literal('4c8d35') + rb'.{4}' + literal('c783fc000000') + rb'(.{4})'
        reset = literal('554889e55350c787f8000000') + rb'(.{4})' + literal('c6878c01000000')
        step = literal('f3410f2a8d84010000f3410f598dfc000000f3410f1085f8000000f30f59c1498b7d10e8') + rb'(.{4})'
        helper = literal('554889e54156534881ec80000000f30f1145804889fb8b7314488b7b38e8') + rb'.{4}' + literal('4889c7e8') + rb'(.{4})'
        forward_getter = bytes.fromhex('554889e54883ec3048897de8f30f104708f30f104f18f30f105728')
    elif mach.architecture == 'armv7':
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        initial = rb'(.{4})' + literal('d1f800a0') + rb'(.{4})' + literal('c4f8b810c4f8bc00')
        reset = literal('90b5') + rb'.{4}(.{4}).{4}' + literal('c0f8b820794401af0c68002180f83811')
        step = literal('98ed4c0a98ed2f2afbff000698ed2e1ad8f8080040ff920d00ff910d10ee101a') + rb'(.{4})'
        helper = literal('f0b503af2ded028b99b004460d46e168e06a') + rb'.{4}' + literal('04ae01463046') + rb'(.{4})'
        forward_getter = bytes.fromhex('80b56f4682b00191019991ed020a019991ed062a019991ed0a4a10ee101a12ee102a14ee103a')
    else:
        return {}

    def matches(pattern):
        return [m for m in re.finditer(pattern, code, re.S)
                if mach.architecture == 'x86_64' or m.start() % 2 == 0]

    starts, resets, steps = matches(initial), matches(reset), matches(step)
    if len(starts) != 1 or len(resets) != 1 or len(steps) != 1:
        return {}
    start, restore, consume = starts[0], resets[0], steps[0]
    if mach.architecture == 'x86_64':
        value = struct.unpack('<f', start[1])[0]
        default_throttle = struct.unpack('<f', start[2])[0]
        restored = struct.unpack('<f', restore[1])[0]
        target = base + consume.end() + struct.unpack('<i', consume[1])[0]
    else:
        def immediate(match, group, register):
            ins = list(decoder.disasm(match[group], base + match.start(group)))
            if len(ins) != 1 or ins[0].mnemonic != 'mov.w' or ins[0].op_str.split(',')[0] != register \
                    or len(ins[0].operands) != 2 or ins[0].operands[1].type != capstone.arm.ARM_OP_IMM:
                return None
            return struct.unpack('<f', struct.pack('<I', ins[0].operands[1].imm & 0xffffffff))[0]
        default_throttle = immediate(start, 1, 'r0')
        value = immediate(start, 2, 'r1')
        restored = immediate(restore, 1, 'r2')
        branch = list(decoder.disasm(consume[1], base + consume.start(1)))
        if len(branch) != 1 or branch[0].mnemonic != 'bl':
            return {}
        target = branch[0].operands[0].imm
    if value is None or not math.isfinite(value) or not 0 < value <= 1000 \
            or value != restored or default_throttle != 1.0:
        return {}
    # Restrict the destination to file-backed text. The helper's verified layout
    # obtains the local third matrix column before normalizing and translating.
    target_data = section_bytes(mach, target, 64, b'__text')
    if target_data is None:
        return {}
    helper_match = re.match(helper, target_data[0], re.S)
    if helper_match is None:
        return {}
    if mach.architecture == 'x86_64':
        getter_address = target + helper_match.end() + struct.unpack('<i', helper_match[1])[0]
    else:
        branch = list(decoder.disasm(helper_match[1], target + helper_match.start(1)))
        if len(branch) != 1 or branch[0].mnemonic != 'bl':
            return {}
        getter_address = branch[0].operands[0].imm
    getter = section_bytes(mach, getter_address, len(forward_getter), b'__text')
    if getter is None or getter[0] != forward_getter:
        return {}
    return {'speed_units_per_millisecond': value, 'forward_axis': [0, 0, 1],
            'provenance': [{'offset': origin + m.start(), 'bytes': len(m[0])}
                           for m in (start, restore, consume)]
                          + [{'offset': target_data[1], 'bytes': len(helper_match[0])},
                             {'offset': getter[1], 'bytes': len(forward_getter)}]}
