"""Recover constants for the ordinary elapsed-time pilot response path.

This does not recover mouse-capture response, ship/equipment modifiers, input
preferences or special control-state selection. No executable logic is emitted.
"""
import math
import re
import struct
from .steering import lit


def extract_pilot_response(mach, rotation):
    if not rotation:
        return {}
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    base = text['address']
    mac = mach.architecture == 'x86_64'
    if mac:
        quantizer = lit('f30f100d') + rb'(.{4})' + lit('f30f59c8f30f59cdf30f2cc14863c0f30f1183040300004869c88320088248c1e92001c889c1c1e91fc1f80501c8')
        ramp = lit('f30f1025') + rb'(.{4})' + lit('f30f5c20f30f5925') + rb'(.{4})' + lit('f3410f2adef30f59ddf30f5edc')
        neutral = lit('0f57c9f3410f2accf3410f598ea4010000f30f5e0d') + rb'(.{4})' + lit('0f57d2f30f58c1')
    elif mach.architecture == 'armv7':
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        quantizer = rb'(.{4})' + lit('42f28301c8f20821b9ff811748ff120d40ff900d84ed961a84ed998abbff202712ee100a94ed9e2a51fb0000411101ebd070')
        ramp = rb'(.{4}).{4}' + lit('45ec305b7844fbff2006') + rb'(.{4})' + lit('006800f1180200ff900d417c002918bf00f1140292ed004a63ef044d04ffb23d80ee030a')
        neutral = lit('46ec306b9bed541afbff2006') + rb'(.{4})' + lit('00ff911d81ee021a00ef010d')
    else:
        return {}
    def matches(pattern):
        return [m for m in re.finditer(pattern, code, re.S) if mac or m.start() % 2 == 0]
    quantizers, ramps, neutrals = matches(quantizer), matches(ramp), matches(neutral)
    # The four signed pitch/yaw return paths must agree on the magnitude.
    if len(quantizers) != 1 or len(ramps) != (2 if mac else 1) or len(neutrals) != 4:
        return {}
    q, r = quantizers[0], ramps[0]
    provenance = []
    for m in [q, *ramps, *neutrals]:
        provenance.append({'offset': mach.slice_offset + text['offset'] + m.start(), 'bytes': len(m[0])})
    def constant(match, group, register=None):
        address = base + match.start(group)
        if mac:
            target = address + 4 + struct.unpack('<i', match[group])[0]
        else:
            ins = list(decoder.disasm(match[group], address))
            if len(ins) != 1 or ins[0].mnemonic != 'vldr' or len(ins[0].operands) != 2 \
                    or ins[0].op_str.split(',')[0] != register \
                    or ins[0].operands[1].type != capstone.arm.ARM_OP_MEM \
                    or ins[0].operands[1].mem.base != capstone.arm.ARM_REG_PC:
                return None
            target = ((address + 4) & ~3) + ins[0].operands[1].mem.disp
        sections = [s for s in mach.sections if s['segment'] == b'__TEXT' and s['offset'] > 0
                    and s['address'] <= target and target + 4 <= s['address'] + s['length']]
        if len(sections) != 1:
            return None
        s = sections[0]; offset = s['offset'] + target - s['address']
        if offset + 4 > len(mach.data): return None
        value = struct.unpack_from('<f', mach.data, offset)[0]
        if not math.isfinite(value): return None
        provenance.append({'offset': offset + mach.slice_offset, 'bytes': 4})
        return value
    gain = constant(q, 1, 's4')
    bias = constant(r, 1, 's6')
    if mac:
        scale = constant(r, 2)
        if constant(ramps[1], 1) != bias or constant(ramps[1], 2) != scale:
            return {}
    else:
        ins = list(decoder.disasm(r[2], base + r.start(2)))
        if len(ins) != 1 or ins[0].mnemonic != 'vmov.f32' or ins[0].op_str.split(',')[0] != 'd18' \
                or len(ins[0].operands) != 2 or ins[0].operands[1].type != capstone.arm.ARM_OP_FP:
            return {}
        scale = ins[0].operands[1].fp
        provenance.append({'offset': mach.slice_offset + text['offset'] + r.start(2), 'bytes': 4})
    returns = [constant(n, 1, 's4') for n in neutrals]
    if gain is None or bias is None or scale is None or any(v is None for v in returns): return {}
    if not -1000000 <= gain < 0 or not 0 < bias <= 10 or not 0 < scale <= 10000: return {}
    if not all(0 < abs(v) <= 10000 for v in returns) or len({abs(v) for v in returns}) != 1 \
            or not any(v < 0 for v in returns) or not any(v > 0 for v in returns):
        return {}
    # The recognized signed integer-division template encodes division by 63.
    return {'target_gain': -gain, 'target_divisor': 63, 'ramp_bias': bias, 'ramp_scale': scale,
            'neutral_divisor': abs(returns[0]), 'mode': 'elapsed', 'command_curve': 'signed_square',
            'provenance': provenance}
