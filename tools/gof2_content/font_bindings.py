"""Static font-to-texture/group declarations, independent of texture filenames."""
import struct
from .opening_loadout import template
from .opening_dialogue import Declaration
from .ship_models import section_bytes

MAC_LANGUAGE = '0fbf55f689d683fa0f4889b580feffff0f87 {outside:4} 488d05 {table:4} 488b8d80feffff48630c88488d0401ffe0'
ARM_LANGUAGE = 'bdf924120f295490539100f2 {outside:2} 5399dfe811f0'
MAC_GUARDS = {'medium': '488d05 {flag:4} f600010f84 {other:4}',
              'large': '488d05 {flag:4} 8a18bf18000000e8 {allocate:4} 4989c7f6c3010f84 {other:4}'}
ARM_GUARDS = {'medium': '{low:4} {high:4} 7844016808780028 {other:4}',
              'large': '{low:4} {high:4} 7844006804784ff0ff30c8f870051020 {allocate:4} {record:4} 002c {other:4}'}

MAC_RECORD = '''bf18000000e8 {record_allocate:4} 4889c3bf04000000e8 {payload_allocate:4}
66c700 {texture:2} 66c74002 {group:2} 66c703 {id:2}
c7430401000000c74308ffffffff48894310'''


def font_records(mach):
    """Recognize complete finite type-1 records, never execute declarations."""
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    rows = []
    if mach.architecture == 'x86_64':
        for match in template(MAC_RECORD).finditer(code):
            targets = [match.end(key) + struct.unpack('<i', match[key])[0] for key in ('record_allocate', 'payload_allocate')]
            if targets[0] != targets[1]: continue
            rows.append({'id': int.from_bytes(match['id'], 'little'),
                         'texture_id': int.from_bytes(match['texture'], 'little'),
                         'font_group': int.from_bytes(match['group'], 'little'),
                         'source_offset': mach.slice_offset + text['offset'] + match.start(),
                         'source_bytes': len(match[0])})
    elif mach.architecture == 'armv7':
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        # The four-byte font payload is returned in r0; every record field and
        # repeated record-pointer reload must agree before it is accepted.
        import re
        for match in re.finditer(bytes.fromhex('0420'), code):
            if match.start() % 2: continue
            start = text['address'] + match.start()
            try:
                d = Declaration(mach, start, decoder, bound=96)
                d.take('movs', 'r0, #4')
                allocator = d.call('blx')
                d.take('add', 'r6, sp, #0xc')
                texture = d.number('r2')
                d.take('add.w', 'r1, r6, #0x1020')
                group = 0
                ins = d.take()
                if ins.mnemonic == 'movt' and ins.op_str.startswith('r2, #'):
                    group = ins.operands[1].imm
                    ins = d.take()
                if ins.mnemonic not in ('movw', 'movs', 'mov.w') or ins.operands[0].reg != capstone.arm.ARM_REG_R3 or ins.operands[1].type != capstone.arm.ARM_OP_IMM: continue
                identifier = ins.operands[1].imm
                scratch = d.take()
                if (scratch.mnemonic, scratch.op_str) not in [('add.w', 'r6, sp, #0x5000'), ('add', 'r6, sp, #0x4c')]: continue
                d.take('mov', 'r5, r1')
                load = d.take('ldr.w')
                if not load.op_str.startswith('r1, [r5, #'): continue
                memory = load.op_str.split(', ', 1)[1]
                d.take('str', 'r2, [r0]')
                d.take('ldr.w', 'r2, ' + memory)
                d.take('strh', 'r3, [r2]')
                d.take('movs', 'r3, #1')
                d.take('ldr.w', 'r2, ' + memory)
                d.take('str', 'r3, [r2, #4]')
                d.take('mov.w', 'r3, #-1')
                d.take('ldr.w', 'r2, ' + memory)
                d.take('str', 'r3, [r2, #8]')
                d.take('ldr.w', 'r2, ' + memory)
                d.take('str', 'r0, [r2, #0xc]')
                end = d.end
                # The preceding allocation must produce this same record slot.
                p = Declaration(mach, start - 22, decoder, bound=32)
                p.take('movs', 'r0, #0x10')
                marker = p.take('str.w')
                if not marker.op_str.endswith(', [r4, #0x570]'): continue
                if p.call('blx') != allocator: continue
                p.take('str.w', 'r0, ' + memory)
                p.number('r0')
                p.take('str.w', 'r0, [r4, #0x570]')
                if p.end != start: continue
                rows.append({'id': identifier, 'texture_id': texture, 'font_group': group,
                             'source_offset': mach.slice_offset + text['offset'] + match.start() - 22,
                             'source_bytes': end - start + 22})
            except (ValueError, StopIteration, IndexError):
                continue
    # Conflicts are not guessed away, and partial records never become a font.
    if len(rows) > 256 or any(not 0 <= row['id'] < 65535 or not 0 <= row['texture_id'] < 65535 or not 0 <= row['font_group'] < 32 for row in rows): return []
    if len({row['id'] for row in rows}) != len(rows): return []
    return sorted(rows, key=lambda row: row['id'])


def language_files(mach):
    """Read the finite language-index/filename dispatch, without following code."""
    import capstone
    import re
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    decoder = capstone.Cs(capstone.CS_ARCH_X86 if mac else capstone.CS_ARCH_ARM,
                          capstone.CS_MODE_64 if mac else capstone.CS_MODE_THUMB)
    decoder.detail = True
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    pattern = template(MAC_LANGUAGE if mac else ARM_LANGUAGE)
    matches = [m for m in pattern.finditer(code) if mac or m.start() % 2 == 0]
    if len(matches) != 1: return {}
    match = matches[0]
    address = section['address'] + match.start()
    if mac:
        table = address + match.end('table') - match.start() + struct.unpack('<i', match['table'])[0]
    else:
        table = address + len(match[0])
    found = section_bytes(mach, table, 64 if mac else 32, b'__text')
    if found is None or len(found[0]) != (64 if mac else 32): return {}
    targets = [table + delta * (1 if mac else 2) for delta in struct.unpack('<16i' if mac else '<16H', found[0])]
    rows, calls = [], set()
    for index, target in enumerate(targets):
        try:
            d = Declaration(mach, target, decoder, bound=64)
            if mac:
                ins = d.take('lea')
                if not ins.op_str.startswith('rdi, [rbp - '): return {}
                d.take('xor', 'edx, edx')
                ins = d.take('lea')
                if not ins.op_str.startswith('rsi, [rip + '): return {}
                string_address = ins.address + ins.size + ins.operands[1].mem.disp
                calls.add(d.call('call'))
            else:
                d.number('r0')
                d.take('str', 'r0, [sp, #0x230]')
                lo = d.number('r1')
                hi = d.take('movt')
                if not hi.op_str.startswith('r1, #'): return {}
                pc = d.take('add', 'r1, pc')
                string_address = (hi.operands[1].imm << 16 | lo) + pc.address + 4
                ins = d.take('add')
                if not ins.op_str.startswith('r0, sp, #'): return {}
                d.take('movs', 'r2, #0')
                calls.add(d.call('bl'))
            string = section_bytes(mach, string_address, 9, b'__cstring')
            if string is None: return {}
            name = string[0].split(b'\0', 1)[0]
            if not re.fullmatch(rb'[a-z]{2,3}\.lang', name): return {}
            rows.append({'language_id': index, 'file': name.decode('ascii'),
                         'source_offset': mach.slice_offset + section['offset'] + target - section['address'],
                         'source_bytes': d.end - target,
                         'string_offset': string[1], 'string_bytes': len(name) + 1})
        except (ValueError, StopIteration, IndexError): return {}
    if len(calls) != 1 or len({row['file'] for row in rows}) != 16: return {}
    return {'rows': rows, 'provenance': {
        'dispatch': {'offset': mach.slice_offset + section['offset'] + match.start(), 'bytes': len(match[0])},
        'table': {'offset': found[1], 'bytes': len(found[0])}}}


def font_texture_choices(mach, records, registrations, flags):
    """Associate font atlases with their source registration branches, not names."""
    import capstone
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    decoder = capstone.Cs(capstone.CS_ARCH_X86 if mac else capstone.CS_ARCH_ARM,
                          capstone.CS_MODE_64 if mac else capstone.CS_MODE_THUMB)
    decoder.detail = True
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    specs = MAC_GUARDS if mac else ARM_GUARDS
    guards = {}
    for kind, spec in specs.items():
        candidates = []
        for match in template(spec).finditer(code):
            if not mac and match.start() % 2: continue
            address = section['address'] + match.start()
            if mac:
                flag = address + 7 + struct.unpack('<i', match['flag'])[0]
                other = address + len(match[0]) + struct.unpack('<i', match['other'])[0]
            else:
                ins = list(decoder.disasm(match['low'] + match['high'], address))
                if len(ins) != 2 or ins[0].mnemonic != 'movw' or ins[1].mnemonic != 'movt' or any(not i.op_str.startswith('r0, #') for i in ins): continue
                pointer = address + 12 + (ins[1].operands[1].imm << 16 | ins[0].operands[1].imm)
                # iOS accesses these globals through its static pointer section.
                slot = next((s for s in mach.sections if s['address'] <= pointer and pointer + 4 <= s['address'] + s['length'] and s['offset']), None)
                if slot is None: continue
                at = slot['offset'] + pointer - slot['address']
                flag = struct.unpack_from('<I', mach.data, at)[0]
                branch = list(decoder.disasm(match['other'], address + len(match[0]) - 4))
                if len(branch) != 1 or branch[0].mnemonic != 'beq.w': continue
                other = branch[0].operands[0].imm
                if kind == 'large':
                    call = list(decoder.disasm(match['allocate'], address + match.start('allocate') - match.start()))
                    if len(call) != 1 or call[0].mnemonic != 'blx': continue
                    ins = list(decoder.disasm(match['record'], address + match.start('record') - match.start()))
                    if len(ins) != 1 or ins[0].mnemonic != 'str.w' or not ins[0].op_str.startswith('r0, [sl, #'): continue
            if flag != flags[kind] or not address + len(match[0]) < other < section['address'] + section['length']: continue
            candidates.append({'address': address, 'begin': address + len(match[0]), 'other': other,
                               'source_offset': mach.slice_offset + section['offset'] + match.start(), 'source_bytes': len(match[0])})
        if len(candidates) != 1: return {}
        guards[kind] = candidates[0]
    # iOS has one stack bookkeeping store at the start of the second branch.
    if guards['large']['address'] - guards['medium']['other'] != (0 if mac else 2): return {}
    wanted = {row['texture_id'] for row in records}
    choices = []
    for identifier in sorted(wanted):
        declarations = [r for r in registrations if r['id'] == identifier]
        if len(declarations) != 3 or any(r['kind'] != 'texture' or r['registration_type'] != 2 for r in declarations): return {}
        variants = {}
        offsets = {}
        for row in declarations:
            at = section['address'] + row['source_offset'] - mach.slice_offset - section['offset']
            if guards['medium']['begin'] <= at < guards['medium']['other']: mode = 'medium'
            elif guards['large']['begin'] <= at < guards['large']['other']: mode = 'large'
            elif at >= guards['large']['other']: mode = 'baseline'
            else: return {}
            if mode in variants: return {}
            variants[mode] = row['resource']
            offsets[mode] = row['source_offset']
        if set(variants) != {'baseline', 'medium', 'large'}: return {}
        choices.append({'texture_id': identifier, 'variants': variants, 'source_offsets': offsets})
    return {'rows': choices, 'provenance': {name: {'offset': row['source_offset'], 'bytes': row['source_bytes']} for name, row in guards.items()}}


def extract_font_bindings(mach, registrations):
    from .font_selection import extract_font_selection
    records = font_records(mach)
    languages = language_files(mach)
    selection = extract_font_selection(mach)
    if not records or not languages or not selection: return {}
    flags = selection.pop('_profile_globals')
    textures = font_texture_choices(mach, records, registrations, flags)
    if not textures: return {}
    wanted = {selection[key] for key in ['default_font_id', 'secondary_font_id', 'language_font_id']}
    wanted.update(row['font_id'] for row in selection['overrides'])
    if wanted != {row['id'] for row in records}: return {}
    return {'records': records, 'languages': languages, 'selection': selection, 'textures': textures}
