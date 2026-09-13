"""Bounded portrait texture declarations; no executable code is emitted or run.

Portrait filenames are authored stems plus source-selected suffixes. Their numeric
IDs are read from record declarations, never inferred from filename order.
"""
import struct
from .opening_loadout import template
from .opening_dialogue import Declaration
from .font_selection import extract_font_selection
from .bundle import safe_name
from .formats import ContentError

MAC_PREFIX = """
554889e5415741564154534881ec10260000488b4740488b18488d05
{ref_1c:4}
f600017409488d05
{ref_28:4}
eb28488d05
{ref_31:4}
f6000175eb488d0d
{ref_3d:4}
488d05
{ref_44:4}
488d15
{ref_4b:4}
f60201480f45c1488d0d
{ref_59:4}
f601017409488d35
{ref_65:4}
eb15488d35
{ref_6e:4}
488d0d
{ref_75:4}
f60101480f44f0
"""

ARM_PREFIX = """
f0b503af2de9000dadf1400424f00f04a54604f9ed8204f9efc2adf5065d84b0
{value_20:4}
0df50056
{value_28:4}
{value_2c:4}
{value_30:4}
79447a44806a
{value_3a:4}
0968
{value_40:4}
12687b440068dff890901b680c78f94404901578c6f874310df500561f49c6f878910df5005641f00101c6f87c710df500567944c6f884d107ae06f505500df50056c6f88011
{call_8a:4}
{value_8e:4}
44ea0501
{value_96:4}
11f0ff0f78440ed1
{value_a2:4}
{value_a6:4}
{value_aa:4}
7944
{value_b0:4}
7a4409680978002908bf1046
{value_c0:4}
{value_c4:4}
79440968097849b1
{value_d0:4}
{value_d4:4}
794412e0
{literal_dc:8}
{value_e4:4}
{value_e8:4}
79440a68
{value_f0:4}
{value_f4:4}
79441278002a08bf01460df500544ff0ff300022c4f8600105ac04f59850
{call_116:4}
"""


def source_string(mach, address):
    section = mach.cstring
    offset = section['offset'] + address - section['address']
    end = section['offset'] + section['length']
    if not section['offset'] <= offset < end or (offset > section['offset'] and mach.data[offset - 1] != 0):
        raise ValueError('Portrait string is not a source string boundary')
    stop = mach.data.find(b'\0', offset, min(offset + 1025, end))
    if stop < 0: raise ValueError('Truncated portrait resource string')
    return {'value': mach.data[offset:stop].decode('utf8'),
            'offset': offset + mach.slice_offset, 'bytes': stop - offset + 1}


def mac_stack(d, register):
    import capstone
    ins = d.take('lea')
    if len(ins.operands) != 2 or ins.reg_name(ins.operands[0].reg) != register:
        raise ValueError('Unknown portrait string destination')
    op = ins.operands[1]
    if op.type != capstone.x86.X86_OP_MEM or ins.reg_name(op.mem.base) != 'rbp' or op.mem.index or not -65536 <= op.mem.disp < 0:
        raise ValueError('Unknown portrait string storage')
    return op.mem.disp


def mac_reference(d, register):
    import capstone
    ins = d.take('lea')
    if len(ins.operands) != 2 or ins.reg_name(ins.operands[0].reg) != register:
        raise ValueError('Unknown portrait string pointer')
    op = ins.operands[1]
    if op.type != capstone.x86.X86_OP_MEM or ins.reg_name(op.mem.base) != 'rip' or op.mem.index:
        raise ValueError('Nonstatic portrait string pointer')
    return ins.address + ins.size + op.mem.disp


def mac_record(mach, start, decoder, suffix_slot, calls):
    d = Declaration(mach, start, decoder, bound=320)
    t = d.take
    def number(register, expected):
        if d.number(register) != expected: raise ValueError('Unknown portrait record allocation')
    def call(kind):
        target = d.call('call')
        if kind in calls and calls[kind] != target: raise ValueError('Inconsistent portrait constructor link')
        calls[kind] = target
    number('edi', 24); call('allocate'); t('mov', 'r14, rax')
    number('edi', 16); call('allocate'); t('mov', 'r15, rax')
    stem_slot = mac_stack(d, 'rdi')
    stem = source_string(mach, mac_reference(d, 'rsi'))
    t('xor', 'edx, edx'); call('string')
    t('mov', 'r12b, 1')
    partial_slot = mac_stack(d, 'rdi')
    if mac_stack(d, 'rsi') != stem_slot or mac_stack(d, 'rdx') != suffix_slot:
        raise ValueError('Portrait suffix is not joined to its stem')
    call('concat'); t('mov', 'r12b, 1')
    extension_slot = mac_stack(d, 'rdi')
    extension = source_string(mach, mac_reference(d, 'rsi'))
    if extension['value'] != '.aei': raise ValueError('Unknown portrait texture extension')
    t('xor', 'edx, edx'); call('string'); t('mov', 'r12b, 1')
    path_slot = mac_stack(d, 'rdi')
    if mac_stack(d, 'rsi') != partial_slot or mac_stack(d, 'rdx') != extension_slot:
        raise ValueError('Portrait extension is not joined to its filename')
    call('concat'); t('mov', 'r12b, 1')
    if mac_stack(d, 'rsi') != path_slot: raise ValueError('Portrait payload uses another filename')
    if len({stem_slot, partial_slot, extension_slot, path_slot, suffix_slot}) != 5:
        raise ValueError('Overlapping portrait string storage')
    t('mov', 'rdi, r15'); t('xorps', 'xmm0, xmm0'); call('payload')
    ins = t('mov')
    if not ins.op_str.startswith('word ptr [r14], ') or len(ins.operands) != 2 or ins.operands[1].type != 2:
        raise ValueError('Unknown portrait resource ID')
    identifier = ins.operands[1].imm
    t('mov', 'dword ptr [r14 + 4], 2')
    t('mov', 'dword ptr [r14 + 8], 0xffffffff')
    t('mov', 'qword ptr [r14 + 0x10], r15')
    t('xor', 'r12b, r12b'); t('mov', 'rdi, rbx'); t('mov', 'rsi, r14'); call('insert')
    record_end = d.end
    for index, slot in enumerate([path_slot, extension_slot, partial_slot, stem_slot]):
        if index < 3: t('xor', 'r12b, r12b')
        if mac_stack(d, 'rdi') != slot: raise ValueError('Portrait temporary-string cleanup mismatch')
        call('destroy_string')
    return {'id': identifier, 'stem': stem['value'], 'stem_offset': stem['offset'], 'stem_bytes': stem['bytes'],
            'extension_offset': extension['offset'], 'extension_bytes': extension['bytes'],
            'source_offset': mach.slice_offset + mach.text['offset'] + start - mach.text['address'],
            'source_bytes': record_end - start}, d.end


def read_mac(mach, match, decoder):
    start = mach.text['address'] + match.start()
    def reference(key):
        return start + match.end(key) - match.start() + struct.unpack('<i', match[key])[0]
    flags = {name: reference(key) for name, key in [('large', 'ref_1c'), ('wide', 'ref_4b'), ('medium', 'ref_75')]}
    selection = extract_font_selection(mach)
    if selection.get('_profile_globals') != flags: raise ValueError('Portrait and font display flags disagree')
    if len(set(flags.values()) | {reference('ref_31'), reference('ref_59')}) != 5: raise ValueError('Conflicting portrait display flags')
    if reference('ref_28') != reference('ref_3d'): raise ValueError('Inconsistent expanded portrait suffix')
    suffixes = {key: source_string(mach, reference(ref)) for key, ref in [('baseline', 'ref_44'), ('expanded', 'ref_28'), ('medium', 'ref_6e'), ('large', 'ref_65')]}
    d = Declaration(mach, start + len(match[0]), decoder, bound=32)
    suffix_slot = mac_stack(d, 'rdi'); d.take('xor', 'edx, edx')
    calls = {'string': d.call('call')}
    rows = []
    at = d.end
    for _ in range(152):
        row, at = mac_record(mach, at, decoder, suffix_slot, calls)
        rows.append(row)
    return rows, suffixes


def extract_portrait_textures(mach):
    import capstone
    if mach.architecture not in ['x86_64', 'armv7']: return {}
    mac = mach.architecture == 'x86_64'
    decoder = capstone.Cs(capstone.CS_ARCH_X86 if mac else capstone.CS_ARCH_ARM, capstone.CS_MODE_64 if mac else capstone.CS_MODE_THUMB)
    decoder.detail = True
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    matches = [m for m in template(MAC_PREFIX if mac else ARM_PREFIX).finditer(code) if mac or m.start() % 2 == 0]
    if len(matches) != 1: return {}
    try:
        rows, suffixes = (read_mac if mac else read_arm)(mach, matches[0], decoder)
        if any(not 0 <= row['id'] <= 65534 for row in rows):
            raise ValueError('Invalid portrait texture ID')
        if len({row['id'] for row in rows}) != len(rows) or len({row['stem'] for row in rows}) != len(rows):
            raise ValueError('Conflicting portrait texture declarations')
        if suffixes['baseline']['value'] != '' or len({row['value'] for row in suffixes.values()}) != 4:
            raise ValueError('Conflicting portrait suffix declarations')
        for value in suffixes.values():
            suffix = value['value']
            if len(suffix) > 32 or any(c not in '_0123456789abcdefghijklmnopqrstuvwxyz' for c in suffix):
                raise ValueError('Unsafe portrait texture suffix')
        for row in rows:
            if not 0 <= row['id'] < 65535 or not row['stem'].startswith('data/') or '.' in row['stem']:
                raise ValueError('Unknown portrait texture stem')
            row['variants'] = {key: 'resources/' + safe_name(row['stem'] + suffixes[key]['value'] + '.aei') for key in suffixes}
        return {'rows': rows, 'suffixes': suffixes,
                'provenance': {'selection': {'offset': mach.slice_offset + section['offset'] + matches[0].start(), 'bytes': len(matches[0][0])}}}
    except (ValueError, StopIteration, IndexError, UnicodeError, struct.error, ContentError):
        return {}


def arm_member(d, mnemonic, register, base, offset):
    import capstone
    ins = d.take()
    if ins.mnemonic.removesuffix('.w') != mnemonic or len(ins.operands) != 2 or ins.reg_name(ins.operands[0].reg) != register:
        raise ValueError('Unknown portrait record member access')
    op = ins.operands[1]
    if op.type != capstone.arm.ARM_OP_MEM or ins.reg_name(op.mem.base) != base or op.mem.index or op.mem.disp != offset:
        raise ValueError('Portrait record/string pointer mismatch')


def arm_add(d, destination, base):
    ins = d.take()
    if ins.mnemonic.removesuffix('.w') not in ('add', 'addw') or len(ins.operands) != 3 or ins.reg_name(ins.operands[0].reg) != destination or ins.reg_name(ins.operands[1].reg) != base or ins.operands[2].type != 2:
        raise ValueError(f'Unknown portrait local-object address at {ins.address:x}: {ins.mnemonic} {ins.op_str}')
    value = ins.operands[2].imm
    if not 0 <= value < 65536: raise ValueError('Invalid portrait stack extent')
    return value


def arm_number(d, register, expected):
    if d.number(register) != expected: raise ValueError('Unexpected portrait declaration constant')


def arm_arguments(d, addresses, constants=None):
    """Recognize a bounded packet of literal SP-relative string addresses.

    This grammar permits only constant address declarations and specified literal
    arguments; it cannot follow branches, access memory or interpret game logic.
    The compiler may interleave independent short/wide address declarations.
    """
    constants = constants or {}
    found = set(); temporary = None
    for _ in range(12):
        if len(found) == len(addresses) + len(constants): return
        ins = d.take()
        if not ins.operands: raise ValueError('Missing portrait argument')
        dest = ins.reg_name(ins.operands[0].reg)
        if dest in found: raise ValueError('Portrait argument overwritten')
        if dest in constants:
            if ins.mnemonic not in ['mov', 'movs', 'movw', 'mov.w'] or len(ins.operands) != 2 or ins.operands[1].type != 2 or ins.operands[1].imm != constants[dest]:
                raise ValueError('Nonliteral portrait constructor argument')
            found.add(dest); continue
        if ins.mnemonic.removesuffix('.w') not in ['add', 'addw'] or len(ins.operands) != 3 or ins.operands[2].type != 2:
            raise ValueError(f'Unknown portrait address packet at {ins.address:x}')
        base = ins.reg_name(ins.operands[1].reg)
        value = ins.operands[2].imm
        if not 0 <= value < 65536: raise ValueError('Invalid portrait stack extent')
        if base == 'lr':
            if temporary is None: raise ValueError('Unbound portrait stack reference')
            value += temporary
        elif base != 'sp': raise ValueError('Nonstatic portrait stack reference')
        if dest == 'lr':
            if base != 'sp': raise ValueError('Unknown portrait temporary address')
            temporary = value
        elif dest in addresses and addresses[dest] == value: found.add(dest)
        else: raise ValueError('Portrait string arguments do not match')
    raise ValueError('Oversized portrait address declaration')


def arm_stack(d, register, expected):
    arm_arguments(d, {register: expected})


def arm_wide(d, register, top=False):
    ins = d.take('movt' if top else 'movw')
    if len(ins.operands) != 2 or ins.reg_name(ins.operands[0].reg) != register or ins.operands[1].type != 2:
        raise ValueError('Unknown portrait string address field')
    return ins.operands[1].imm


def arm_pc(d, register, low, high):
    ins = d.take('add', register + ', pc')
    return ins.address + 4 + low + (high << 16)


def arm_marker(d, number, register='r0'):
    if arm_add(d, 'lr', 'sp') != 0x2000: raise ValueError('Unknown portrait declaration frame')
    arm_number(d, register, number)
    arm_member(d, 'str', register, 'lr', 0x160)


def arm_flag(d, offset, value, register='r0'):
    base = arm_add(d, 'lr', 'sp')
    if base not in [0x1000, 0x2000]: raise ValueError('Unknown portrait temporary lifetime')
    arm_number(d, register, value)
    arm_member(d, 'strb', register, 'lr', offset - base)


def arm_record(mach, start, decoder, index, calls):
    d = Declaration(mach, start, decoder, bound=640)
    t = d.take
    def call(kind, mnemonic='bl'):
        target = d.call(mnemonic)
        if kind in calls and calls[kind] != target: raise ValueError('Inconsistent portrait constructor link')
        calls[kind] = target
    mark = 1 + index * 12
    pair = 8 * index
    stem_slot, partial_slot, extension_slot, path_slot = [base - index * 32 for base in [0x12fc, 0x1304, 0x12f4, 0x130c]]
    flag = 0x17dc + index * 16
    arm_marker(d, mark)
    arm_number(d, 'r0', 16); call('allocate', 'blx')
    arm_stack(d, 'r1', 0x131c)
    if arm_add(d, 'lr', 'sp') != 0x2000: raise ValueError('Unknown portrait frame')
    arm_member(d, 'str', 'r0', 'r1', pair)
    arm_number(d, 'r0', mark + 1); arm_member(d, 'str', 'r0', 'lr', 0x160)
    arm_number(d, 'r0', 8); call('allocate', 'blx')
    first = arm_add(d, 'lr', 'sp'); low = arm_wide(d, 'r1')
    if first + arm_add(d, 'r2', 'lr') != 0x131c or arm_add(d, 'lr', 'sp') != 0x2000: raise ValueError('Portrait payload pointer mismatch')
    high = arm_wide(d, 'r1', True)
    arm_member(d, 'str', 'r0', 'r2', pair + 4); arm_number(d, 'r0', mark + 2)
    stem = source_string(mach, arm_pc(d, 'r1', low, high))
    arm_member(d, 'str', 'r0', 'lr', 0x160)
    arm_arguments(d, {'r0': stem_slot}, {'r2': 0}); call('string')
    arm_flag(d, flag, 1); arm_marker(d, mark + 3)
    arm_arguments(d, {'r0': partial_slot, 'r1': stem_slot, 'r2': 0x1314})
    call('concat')
    flag_base = arm_add(d, 'lr', 'sp')
    if flag_base not in [0x1000, 0x2000]: raise ValueError('Unknown portrait extension frame')
    low = arm_wide(d, 'r1'); arm_number(d, 'r0', 1); high = arm_wide(d, 'r1', True)
    arm_member(d, 'strb', 'r0', 'lr', flag + 4 - flag_base)
    if arm_add(d, 'lr', 'sp') != 0x2000: raise ValueError('Unknown portrait frame')
    arm_number(d, 'r0', mark + 4)
    extension = source_string(mach, arm_pc(d, 'r1', low, high))
    if extension['value'] != '.aei': raise ValueError('Unknown portrait texture extension')
    arm_member(d, 'str', 'r0', 'lr', 0x160)
    arm_arguments(d, {'r0': extension_slot}, {'r2': 0}); call('string')
    arm_flag(d, flag + 8, 1); arm_marker(d, mark + 5)
    arm_arguments(d, {'r0': path_slot, 'r1': partial_slot, 'r2': extension_slot})
    call('concat')
    arm_arguments(d, {'r0': 0x131c}, {'r1': 1})
    flag_base = arm_add(d, 'lr', 'sp')
    if flag_base not in [0x1000, 0x2000]: raise ValueError('Unknown portrait lifetime frame')
    arm_member(d, 'ldr', 'r0', 'r0', pair + 4)
    arm_member(d, 'strb', 'r1', 'lr', flag + 12 - flag_base)
    arm_marker(d, mark + 6, 'r1')
    arm_arguments(d, {'r1': path_slot}, {'r2': 0}); call('payload')
    first = arm_add(d, 'lr', 'sp'); identifier = d.number('r2')
    if first + arm_add(d, 'r0', 'lr') != 0x131c: raise ValueError('Portrait record pointer mismatch')
    flag_base = arm_add(d, 'lr', 'sp')
    if flag_base not in [0x1000, 0x2000]: raise ValueError('Unknown portrait record lifetime frame')
    t('mov', 'r3, r0')
    arm_member(d, 'ldr', 'r1', 'r3', pair); arm_member(d, 'ldr', 'r0', 'r3', pair)
    arm_member(d, 'strh', 'r2', 'r0', 0)
    arm_number(d, 'r2', 2); arm_member(d, 'ldr', 'r0', 'r3', pair); arm_member(d, 'str', 'r2', 'r0', 4)
    t('mov.w', 'r2, #-1'); arm_member(d, 'ldr', 'r0', 'r3', pair); arm_member(d, 'str', 'r2', 'r0', 8)
    arm_member(d, 'ldr', 'r0', 'r3', pair); arm_member(d, 'ldr', 'r2', 'r3', pair + 4); arm_member(d, 'str', 'r2', 'r0', 12)
    arm_number(d, 'r0', 0); arm_member(d, 'strb', 'r0', 'lr', flag + 12 - flag_base)
    arm_marker(d, mark + 7); arm_member(d, 'ldr', 'r0', 'sp', 16); call('insert')
    record_end = d.end
    for j, slot in enumerate([path_slot, extension_slot, partial_slot, stem_slot]):
        if j < 3: arm_flag(d, flag + 8 - j * 4, 0)
        arm_marker(d, mark + 8 + j); arm_stack(d, 'r0', slot); call('destroy_string')
    return {'id': identifier, 'stem': stem['value'], 'stem_offset': stem['offset'], 'stem_bytes': stem['bytes'],
            'extension_offset': extension['offset'], 'extension_bytes': extension['bytes'],
            'source_offset': mach.slice_offset + mach.text['offset'] + start - mach.text['address'],
            'source_bytes': record_end - start}, d.end


def read_arm(mach, match, decoder):
    start = mach.text['address'] + match.start()
    exception_call = list(decoder.disasm(match['call_8a'], start + 0x8a))
    if len(exception_call) != 1 or exception_call[0].mnemonic != 'blx' or exception_call[0].operands[0].type != 2:
        raise ValueError('Unknown portrait declaration setup')
    values = {}
    shapes = {key: (mnemonic, register) for lo, hi, register in [('20','28','r1'), ('2c','30','r2'), ('3a','40','r3'), ('8e','96','r0'), ('a2','a6','r1'), ('aa','b0','r2'), ('c0','c4','r1'), ('d0','d4','r1'), ('e4','e8','r1'), ('f0','f4','r1')] for key, mnemonic in [(lo,'movw'), (hi,'movt')]}
    for key, raw in match.groupdict().items():
        if not key.startswith('value_'): continue
        at = start + match.start(key) - match.start()
        ins = list(decoder.disasm(raw, at))
        if len(ins) != 1 or ins[0].mnemonic not in ['movw', 'movt'] or len(ins[0].operands) != 2 or ins[0].operands[1].type != 2:
            raise ValueError('Invalid portrait suffix pointer')
        if (ins[0].mnemonic, ins[0].reg_name(ins[0].operands[0].reg)) != shapes.get(key[6:]): raise ValueError('Invalid portrait suffix register')
        values[key[6:]] = ins[0].operands[1].imm
    def reference(low, high, at, register):
        # Verify the two halves name the same expected address register.
        for key, mnemonic in [(low, 'movw'), (high, 'movt')]:
            ins = list(decoder.disasm(match['value_' + key], start + int(key, 16)))[0]
            if ins.mnemonic != mnemonic or ins.reg_name(ins.operands[0].reg) != register: raise ValueError('Portrait suffix register mismatch')
        return start + at + values[low] + (values[high] << 16)
    def pointer(address):
        for section in mach.sections:
            if section['address'] <= address and address + 4 <= section['address'] + section['length']:
                return struct.unpack_from('<I', mach.data, section['offset'] + address - section['address'])[0]
        raise ValueError('Portrait display flag pointer is not file-backed')
    flags = {'large': pointer(reference('2c', '30', 0x3a, 'r2')), 'wide': pointer(reference('a2', 'a6', 0xb2, 'r1')), 'medium': pointer(reference('e4', 'e8', 0xf0, 'r1'))}
    if len(set(flags.values()) | {pointer(reference('20','28',0x38,'r1')), pointer(reference('c0','c4',0xcc,'r1'))}) != 5: raise ValueError('Conflicting portrait display flags')
    if extract_font_selection(mach).get('_profile_globals') != flags: raise ValueError('Portrait and font display flags disagree')
    suffixes = {key: source_string(mach, reference(lo, hi, pc, reg)) for key, lo, hi, pc, reg in [
        ('baseline', 'aa', 'b0', 0xb8, 'r2'), ('expanded', '8e', '96', 0xa2, 'r0'),
        ('medium', 'f0', 'f4', 0xfc, 'r1'), ('large', 'd0', 'd4', 0xdc, 'r1')]}
    ins = list(decoder.disasm(match['call_116'], start + 0x116))
    if len(ins) != 1 or ins[0].mnemonic != 'bl' or ins[0].operands[0].type != 2: raise ValueError('Unknown portrait suffix string constructor')
    calls = {'string': ins[0].operands[0].imm}
    rows = []; at = start + len(match[0])
    for index in range(152):
        row, at = arm_record(mach, at, decoder, index, calls)
        rows.append(row)
    return rows, suffixes
