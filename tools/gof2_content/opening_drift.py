"""Recover opening actor drift constants from bounded declarative contexts.

The native runtime receives parameters and provenance only, never source code.
Elapsed time must be supplied by the scene; this reader does not seed save clocks.
"""
import math
import struct
from .opening_loadout import template
from .ship_models import section_bytes
from . import opening_camera as camera

MAC_WAVE = """
554889e55350f30f1145f4488d1d
{ref_b:4}
488b3be8
{call_15:4}
0f57c0f3480f2ac0f30f5945f4e8
{call_27:4}
f30f1145f0488b3be8
{call_34:4}
0f57c0f3480f2ac0f30f5945f4e8
{call_46:4}
0f57c9f30f1055f00f2ed177
{jump_56:1}
0f5705
{ref_58:4}
4883c4085b5dc3
"""

ARM_WAVE = """
b0b502af2ded028b
{word_8:4}
41ec181b
{word_10:4}
784405682868
{call_1a:4}
{call_1e:4}
40ec300b00ff980d10ee100a
{call_2e:4}
04462868
{call_36:4}
{call_3a:4}
40ec300b00ff980d44ec184b10ee100a
{call_4e:4}
b5eec08af1ee10fa40ec100bd8bfb9ff800710ee100abdec028bb0bd
"""

MAC_SINE = """
554889e54883ec10f30f1145fcf30f5a45fce8
{call_12:4}
f20f5ac04883c4105dc3
"""

ARM_SINE = """
80b56f4681b040ec100bb0ee402a8ded002ab7eec20a51ec100b
{call_1a:4}
41ec100bb7eec02b12ee100a01b080bd
"""

MAC_TRANSLATE = """
554889e54156534881ec90000000f30f119564fffffff30f118d68fffffff30f11856cffffff4889fb8b7314488b7b38e8
{call_30:4}
4c8b4018488b5020488b7028488b78308b4838894de848897de0488975d8488955d04c8945c8488b481048894dc0488b08488b4008488945b848894db0f30f109564fffffff30f5855dcf30f108d68fffffff30f584dccf30f10856cfffffff30f5845bc488dbd70ffffff4c8d75b04c89f6e8
{call_a7:4}
8b7314488b7b384c89f2e8
{call_b6:4}
4881c4900000005b415e5dc390
"""

ARM_TRANSLATE = """
f0b503af2de900059fb004460e46e1689846e06a9246
{call_16:4}
00f1200160f98f0a10ad61f98f2a00f110012c3060f98f6a05f12c0061f98f4a294645f98f0a46ec306b40f98f6a05f1200040f98f2a05f110004aec32ab40f98f4a01a89ded130a9ded171a00ef200d9ded1b2a01ef221d48ec308b10ee102a11ee103a02ef200d8ded000a20ef1001
{call_8a:4}
e1682a46e06a
{call_94:4}
1fb0bde80005f0bd
"""

ARM_FIELDS = {'ARM_WAVE': {'word_8': {'kind': 'movw', 'register': 'r0'}, 'word_10': {'kind': 'movt', 'register': 'r0'}, 'call_1a': {'kind': 'bl'}, 'call_1e': {'kind': 'blx'}, 'call_2e': {'kind': 'bl'}, 'call_36': {'kind': 'bl'}, 'call_3a': {'kind': 'blx'}, 'call_4e': {'kind': 'bl'}}, 'ARM_SINE': {'call_1a': {'kind': 'blx'}}, 'ARM_TRANSLATE': {'call_16': {'kind': 'bl'}, 'call_8a': {'kind': 'bl'}, 'call_94': {'kind': 'bl'}}}


def extract_opening_drift(mach, opening):
    if not opening or mach.architecture not in ['x86_64', 'armv7']: return {}
    import capstone
    mac = mach.architecture == 'x86_64'
    text = mach.text; base = text['address']
    code = mach.data[text['offset']:text['offset'] + text['length']]
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB); decoder.detail = True
    prefix = 'MAC_' if mac else 'ARM_'
    blocks = {}; provenance = {}
    def require(value):
        if not value: raise ValueError('Unsupported opening drift context')
    def ins(m, field):
        rows = list(decoder.disasm(m[field], base + m.start(field)))
        require(len(rows) == 1 and rows[0].size == len(m[field])); return rows[0]
    def match(key, spec, metadata, address=None):
        found = [m for m in template(spec).finditer(code) if (mac or m.start() % 2 == 0) and (address is None or base + m.start() == address)]
        require(len(found) == 1); m = found[0]
        if not mac:
            for field, expected in metadata.items():
                i = ins(m, field); require(i.mnemonic == expected['kind'])
                if 'register' in expected: require(i.reg_name(i.operands[0].reg) == expected['register'])
        provenance[key] = {'offset': mach.slice_offset + text['offset'] + m.start(), 'bytes': len(m[0])}
        blocks[key] = m; return m
    def dest(m, field):
        if mac: return base + m.end(field) + int.from_bytes(m[field], 'little', signed=True)
        i = ins(m, field); require(i.operands[-1].type == 2); return i.operands[-1].imm
    def raw(key, address, data):
        found = section_bytes(mach, address, len(data), b'__text')
        require(found is not None and found[0] == data)
        provenance[key] = {'offset': found[1], 'bytes': len(data)}
    def scalar(key, m, field):
        found = section_bytes(mach, dest(m, field), 4, b'__const'); require(found is not None)
        provenance[key] = {'offset': found[1], 'bytes': 4}
        return struct.unpack('<f', found[0])[0]
    try:
        cut = match('cut', getattr(camera, prefix+'CUT'), camera.ARM_FIELDS.get(prefix+'CUT', {}))
        require(provenance['cut'] == opening['provenance']['cut'])
        wave = match('wave', globals()[prefix+'WAVE'], ARM_FIELDS.get(prefix+'WAVE', {}), dest(cut, 'call_22' if mac else 'call_30'))
        sine = match('sine', globals()[prefix+'SINE'], ARM_FIELDS.get(prefix+'SINE', {}), dest(wave, 'call_27' if mac else 'call_2e'))
        require(dest(wave, 'call_46' if mac else 'call_4e') == base + sine.start())
        getter = dest(wave, 'call_15' if mac else 'call_1a')
        require(getter == dest(wave, 'call_34' if mac else 'call_36'))
        raw('elapsed_getter', getter, bytes.fromhex('554889e5488b87480200005dc3' if mac else 'd0e969017047'))
        match('translate', globals()[prefix+'TRANSLATE'], ARM_FIELDS.get(prefix+'TRANSLATE', {}), dest(cut, 'call_56' if mac else 'call_5e'))
        if mac:
            frequency = scalar('frequency', cut, 'ref_1a')
            bias = scalar('bias', cut, 'ref_27')
            require(struct.pack('<f', scalar('sign', wave, 'ref_58')) == bytes.fromhex('00000080'))
            require(dest(wave, 'jump_56') == base + wave.start() + 0x5f)
        else:
            frequency = struct.unpack('<f', struct.pack('<I', ins(cut,'word_c').operands[1].imm | (ins(cut,'word_24').operands[1].imm << 16)))[0]
            bias = -0.5  # Literal VFP operand retained in the matched cut.
            require(dest(wave, 'call_1e') == dest(wave, 'call_3a'))
        for m in [wave, sine, blocks['translate']]:
            for field in m.groupdict():
                if not field.startswith('call_'): continue
                address = dest(m, field)
                found = section_bytes(mach, address, 2, b'__text')
                if found is None: found = section_bytes(mach, address, 6 if mac else 16, b'__stubs' if mac else b'__picsymbolstub4')
                require(found is not None)
        require(math.isfinite(frequency) and 0 < frequency <= 1000 and math.isfinite(bias) and abs(bias) <= 1000000)
        return {'frequency_per_millisecond': frequency, 'bias': bias, 'actor_ids': [0,1,2],
                'through_phase': 2, 'skip_formation_update': True, 'time_unit': 'milliseconds',
                'waveform': 'absolute_sine', 'application': 'per_update_world_y', 'provenance': provenance}
    except (ValueError, KeyError, IndexError, TypeError, OverflowError, struct.error): return {}
