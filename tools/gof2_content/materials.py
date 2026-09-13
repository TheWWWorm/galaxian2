"""Bounded static material initializers; exports declarative fields, never code.

The two compiler layouts describe the same eight texture slots and render enum.
Unknown initializer shapes are omitted, not interpreted or executed.
"""
import re
import struct

from .formats import ContentError


def declaration(mach, offset, identifier, payload):
    textures = list(struct.unpack_from('<8H', payload))
    mode = struct.unpack_from('<I', payload, 16)[0]
    # Pointer-sized fields are not exported. Only the observed null form is
    # supported; a non-null value would need an independently verified reader.
    pointer_size = 8 if mach.architecture == 'x86_64' else 4
    pointer_at = 24 if pointer_size == 8 else 20
    if any(payload[pointer_at:pointer_at + pointer_size]):
        return None
    parameters = list(struct.unpack_from('<4I', payload, pointer_at + pointer_size))
    return {'id': identifier, 'texture_ids': textures, 'render_type': mode,
            'parameter_bits': parameters, 'source_offset': offset + mach.slice_offset}


def mac_materials(mach, checkpoint):
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    # Allocation, complete constant fields, optional texture-slot overrides,
    # then the registration ID/type/sentinel and the very same payload pointer.
    pattern = re.compile(
        rb'\xbf\x30\x00\x00\x00\xe8.{4}'
        rb'\xc7\x40\x10(.{4})\x48\xc7\x40\x18\x00\x00\x00\x00'
        rb'\xc7\x40\x20(.{4})\xc7\x40\x24(.{4})'
        rb'\xc7\x40\x28(.{4})\xc7\x40\x2c(.{4})'
        rb'\x48\xc7\x40\x08\xff\xff\xff\xff\x48\xc7\x00\xff\xff\xff\xff'
        rb'((?:\x66\xc7\x00.{2}|\x66\xc7\x40[\x02\x04\x06\x08\x0a\x0c\x0e].{2}){0,8})'
        rb'\x66\xc7\x03(.{2})\xc7\x43\x04\x06\x00\x00\x00'
        rb'\xc7\x43\x08\xff\xff\xff\xff\x48\x89\x43\x10', re.S)
    rows = []
    for match in pattern.finditer(code):
        checkpoint('Reading x86-64 material declarations', match.start() / len(code))
        payload = bytearray(48)
        payload[:16] = b'\xff' * 16
        payload[16:20] = match[1]
        for i in range(4):
            payload[32 + 4*i:36 + 4*i] = match[2+i]
        writes = match[6]
        while writes:
            offset, size = (0, 5) if writes[2] == 0 else (writes[3], 6)
            payload[offset:offset + 2] = writes[size - 2:size]
            writes = writes[size:]
        row = declaration(mach, section['offset'] + match.start(), struct.unpack('<H', match[7])[0], payload)
        if row is not None:
            rows.append(row)
    return rows


def ios_materials(mach, checkpoint):
    try:
        import capstone
        from capstone.arm_const import ARM_OP_IMM, ARM_OP_REG, ARM_OP_MEM
    except ImportError as error:
        raise ContentError('Install tools/requirements-bindings.txt for ARM material reading') from error
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
    decoder.detail = True
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    rows = []
    for match in re.finditer(re.escape(b'\x28\x20'), code):
        start = match.start()
        if start % 2:
            continue
        ins = list(decoder.disasm(code[start:start + 192], section['address'] + start))
        if len(ins) < 4 or ins[0].op_str != 'r0, #0x28' or ins[1].mnemonic != 'blx':
            continue
        # This recognizer accepts constant assignments within one allocation
        # initializer only. It never follows branches/calls or reads game memory.
        values = {}
        stack_addresses = {'sp': 0}
        payload = bytearray(40)
        assigned = set()
        pointer_loads = {}
        for k, instruction in enumerate(ins[2:], 2):
            op = instruction.operands
            name = instruction.mnemonic
            if name in ('movs', 'mov.w', 'movw', 'movt') and len(op) == 2 and op[0].type == ARM_OP_REG and op[1].type == ARM_OP_IMM:
                reg = instruction.reg_name(op[0].reg)
                if reg == 'r0':
                    break
                stack_addresses.pop(reg, None)
                if name == 'movt':
                    if reg not in values:
                        break
                    values[reg] = (values[reg] & 65535) | (op[1].imm << 16)
                else:
                    values[reg] = op[1].imm & 0xffffffff
            elif name in ('add', 'add.w') and len(op) == 3 and op[0].type == ARM_OP_REG and op[1].type == ARM_OP_REG and op[2].type == ARM_OP_IMM:
                # Stack scratch addresses may be scheduled among field stores.
                reg, base = (instruction.reg_name(op[j].reg) for j in (0, 1))
                if reg not in ('lr', 'r1', 'r5', 'r6', 'r8') or base not in stack_addresses:
                    break
                stack_addresses[reg] = stack_addresses[base] + op[2].imm
                values.pop(reg, None)
            elif name == 'mov' and instruction.op_str == 'r5, r1' and 'r1' in stack_addresses:
                stack_addresses['r5'] = stack_addresses['r1']
                values.pop('r5', None)
            elif name in ('ldr', 'ldr.w') and len(op) == 2 and op[0].type == ARM_OP_REG and op[1].type == ARM_OP_MEM:
                reg = instruction.reg_name(op[0].reg)
                if reg not in ('r1', 'r2', 'r3') or op[1].mem.index or instruction.reg_name(op[1].mem.base) not in stack_addresses:
                    break
                values.pop(reg, None)
                stack_addresses.pop(reg, None)
                pointer_loads[reg] = instruction.op_str
            elif name in ('str', 'str.w', 'strh', 'strh.w') and len(op) == 2 and op[0].type == ARM_OP_REG and op[1].type == ARM_OP_MEM:
                reg, base = instruction.reg_name(op[0].reg), instruction.reg_name(op[1].mem.base)
                at = op[1].mem.disp
                if op[1].mem.index:
                    break
                if instruction.op_str in ('r3, [r2]', 'r5, [r3]') and name == 'strh':
                    # Exact registration footer, including repeated record
                    # pointer and payload identity. A nearby ID is insufficient.
                    tail = ins[k + 1:k + 8]
                    pointer_load = pointer_loads.get(base)
                    if reg == 'r5':
                        tail = ins[k + 1:k + 9]
                        if len(tail) != 8 or tail[3].mnemonic not in ('add', 'add.w') or not tail[3].op_str.startswith('r5, sp, #') or not pointer_load or not pointer_load.startswith('r3, [r6'):
                            break
                        tail = tail[:3] + tail[4:]
                    if len(tail) != 7 or pointer_load is None or not 0 <= values.get(reg, -1) <= 65535:
                        break
                    sentinel = tail[4].op_str.split(', ', 1)[0]
                    if sentinel not in ('r2', 'r4', 'r6') or values.get(sentinel) != 0xffffffff:
                        break
                    expected = [('movs', reg + ', #6'), ('ldr', pointer_load), ('str', f'{reg}, [{base}, #4]'),
                                ('ldr', pointer_load), ('str', f'{sentinel}, [{base}, #8]'), ('ldr', pointer_load),
                                ('str', f'r0, [{base}, #0xc]')]
                    if [(i.mnemonic.removesuffix('.w'), i.op_str) for i in tail] == expected and assigned == set(range(40)):
                        row = declaration(mach, section['offset'] + start, values[reg], payload)
                        if row is not None:
                            rows.append(row)
                    break
                width = 2 if name.startswith('strh') else 4
                if base != 'r0' or reg not in values or at < 0 or at + width > 40 or at % width:
                    break
                payload[at:at + width] = (values[reg] & ((1 << (width * 8)) - 1)).to_bytes(width, 'little')
                assigned.update(range(at, at + width))
            else:
                break
        if len(rows) > 20000:
            raise ContentError('Too many material declarations')
        checkpoint('Reading ARM material declarations', start / len(code))
    return rows


def extract_materials(mach, checkpoint=lambda *_: None):
    rows = (ios_materials if mach.architecture == 'armv7' else mac_materials)(mach, checkpoint)
    if len(rows) > 20000:
        raise ContentError('Too many material declarations')
    return sorted(rows, key=lambda row: (row['id'], row['source_offset']))


def ios_mesh_metadata(mach, registration_start, path, decoder):
    """Follow constant stack aliases inside one bounded mesh initializer only.

    The material/flag stores and final copied-string store must target the same
    allocated descriptor. Matching a nearby filename or stack displacement alone
    is insufficient. Calls are not followed; caller registers are invalidated.
    """
    from capstone.arm_const import ARM_OP_IMM, ARM_OP_REG, ARM_OP_MEM
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    ins = []
    for match in reversed(list(re.finditer(re.escape(b'\x08\x20'), code[max(0, registration_start - 224):registration_start]))):
        start = max(0, registration_start - 224) + match.start()
        if start % 2:
            continue
        candidate = list(decoder.disasm(code[start:registration_start + 12], section['address'] + start))
        if len(candidate) >= 4 and candidate[0].op_str == 'r0, #8' and candidate[1].mnemonic == 'blx':
            ins = candidate
            break
    if not ins:
        return {}
    # Symbols refer only to this initializer's stack slots and allocation.
    aliases = {'sp': ('stack', 0), 'r0': ('payload', 0)}
    constants, slots, result = {}, {}, {}
    found_path = False
    calls = 0
    for instruction in ins[2:]:
        op, name = instruction.operands, instruction.mnemonic
        if name in ('bl', 'blx'):
            calls += 1
            for reg in ('r0', 'r1', 'r2', 'r3', 'r12', 'lr'):
                constants.pop(reg, None)
                aliases.pop(reg, None)
            continue
        if not op or op[0].type != ARM_OP_REG:
            return {}
        reg = instruction.reg_name(op[0].reg)
        if name in ('str', 'str.w', 'strh', 'strb') and len(op) == 2 and op[1].type == ARM_OP_MEM and not op[1].mem.index:
            base = aliases.get(instruction.reg_name(op[1].mem.base))
            if base is None:
                return {}
            offset = base[1] + op[1].mem.disp
            if base[0] == 'stack' and name in ('str', 'str.w'):
                slots[offset] = aliases.get(reg)
            elif base == ('payload', 0):
                if name == 'strh' and offset == 4 and reg in constants and 'material_id' not in result:
                    result['material_id'] = constants[reg] & 65535
                elif name == 'strb' and offset == 6 and reg in constants and 'mesh_flags' not in result:
                    result['mesh_flags'] = constants[reg] & 255
                elif name == 'str' and offset == 0 and reg == 'r0' and instruction.address + instruction.size == section['address'] + registration_start + 12:
                    return result if found_path and calls == 2 and len(result) == 2 else {}
                else:
                    return {}
            else:
                return {}
        elif name in ('ldr', 'ldr.w') and len(op) == 2 and op[1].type == ARM_OP_MEM and not op[1].mem.index:
            base = aliases.get(instruction.reg_name(op[1].mem.base))
            value = slots.get(base[1] + op[1].mem.disp) if base and base[0] == 'stack' else None
            aliases.pop(reg, None)
            constants.pop(reg, None)
            if value is not None:
                aliases[reg] = value
        elif name in ('movs', 'movw', 'movt', 'mov.w') and len(op) == 2 and op[1].type == ARM_OP_IMM:
            aliases.pop(reg, None)
            if name == 'movt':
                if reg not in constants:
                    return {}
                constants[reg] = (constants[reg] & 65535) | (op[1].imm << 16)
            else:
                constants[reg] = op[1].imm & 0xffffffff
        elif name == 'mov' and len(op) == 2 and op[1].type == ARM_OP_REG:
            source = instruction.reg_name(op[1].reg)
            value, constant = aliases.get(source), constants.get(source)
            aliases.pop(reg, None)
            constants.pop(reg, None)
            if value is not None:
                aliases[reg] = value
            if constant is not None:
                constants[reg] = constant
        elif name in ('add', 'add.w') and len(op) == 3 and op[1].type == ARM_OP_REG and op[2].type == ARM_OP_IMM:
            base = aliases.get(instruction.reg_name(op[1].reg))
            aliases.pop(reg, None)
            constants.pop(reg, None)
            if base and base[0] == 'stack':
                aliases[reg] = ('stack', base[1] + op[2].imm)
        elif name == 'add' and len(op) == 2 and op[1].type == ARM_OP_REG and instruction.reg_name(op[1].reg) == 'pc':
            if reg not in constants:
                return {}
            address = constants.pop(reg) + instruction.address + 4
            if mach.resource_string(address) != path:
                return {}
            found_path = True
            aliases.pop(reg, None)
        elif name == 'adds' and instruction.op_str == 'r0, #1':
            # String allocation size is irrelevant to declarative metadata.
            aliases.pop(reg, None)
            constants.pop(reg, None)
        elif name == 'adds' and len(op) == 3 and all(o.type == ARM_OP_REG for o in op):
            left, right = (instruction.reg_name(op[j].reg) for j in (1, 2))
            base, constant = aliases.get(left), constants.get(right)
            if not base or base[0] != 'stack' or constant is None:
                return {}
            aliases[reg] = ('stack', base[1] + constant)
            constants.pop(reg, None)
        else:
            return {}
    return {}
