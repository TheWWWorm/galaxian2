"""Recover the packed catalogue-indexed hull table, without executing game code.

Resource-name anchors identify candidate data tables. A bounded compiler access
template must independently prove an ID getter followed by a u16 indexed read.
Names alone never produce the full mapping, and conflicting tables are rejected.
"""
import re
import struct


def section_bytes(mach, address, size, name):
    for section in mach.sections:
        if section['segment'] == b'__TEXT' and section['name'] == name and section['address'] <= address and address + size <= section['address'] + section['length']:
            offset = section['offset'] + address - section['address']
            return mach.data[offset:offset + size], offset + mach.slice_offset
    return None


def index_references(mach):
    section = mach.text
    code = mach.data[section['offset']:section['offset'] + section['length']]
    result = []
    if mach.architecture == 'x86_64':
        pattern = re.compile(rb'\xe8(.{4})\x48\x8d\x0d(.{4})\x48\x63\xc0\x0f\xb7\x14\x41', re.S)
        for match in pattern.finditer(code):
            start = section['address'] + match.start()
            getter = section_bytes(mach, start + 5 + struct.unpack('<i', match[1])[0], 8, b'__text')
            if getter is None or getter[0] != bytes.fromhex('55 48 89 e5 8b 07 5d c3'):
                continue
            result.append((start + 12 + struct.unpack('<i', match[2])[0], section['offset'] + match.start() + mach.slice_offset))
    else:
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
        for match in re.finditer(re.escape(bytes.fromhex('79 44 31 f8 10 20')), code):
            start = match.start() - 18
            if start < 0 or start % 2:
                continue
            ins = list(decoder.disasm(code[start:start + 24], section['address'] + start))
            if len(ins) != 7 or ins[0].mnemonic != 'bl' or ins[1].mnemonic != 'movw' or not ins[1].op_str.startswith('r1, #') \
                    or (ins[2].mnemonic, ins[2].op_str) != ('movs', 'r3, #0') \
                    or ins[3].mnemonic != 'movt' or not ins[3].op_str.startswith('r1, #') \
                    or ins[4].mnemonic != 'str.w' or not ins[4].op_str.startswith('sl, [sp, #'):
                continue
            getter = section_bytes(mach, ins[0].operands[0].imm, 4, b'__text')
            if getter is None or getter[0] != bytes.fromhex('00 68 70 47'):
                continue
            address = ins[1].operands[1].imm + (ins[3].operands[1].imm << 16) + ins[5].address + 4
            result.append((address, section['offset'] + start + mach.slice_offset))
    return result


def extract_ship_models(mach, rows, count):
    if not 8 <= count <= 256:
        return {}
    anchors = {i: set() for i in range(8)}
    pattern = re.compile(r'resources/data/assets/main/3d/meshes/ships/ship_(00[0-7])_[a-z]+\.aem')
    for row in rows:
        match = pattern.fullmatch(row['resource'])
        if match and row['kind'] == 'mesh' and row['registration_type'] == 4:
            anchors[int(match[1])].add(row['id'])
    if any(len(values) != 1 for values in anchors.values()):
        return {}
    seed = struct.pack('<8H', *(next(iter(anchors[i])) for i in range(8)))
    candidates = {}
    for section in mach.sections:
        if section['segment'] != b'__TEXT' or section['name'] != b'__const':
            continue
        data = mach.data[section['offset']:section['offset'] + section['length']]
        for match in re.finditer(re.escape(seed), data):
            if match.start() % 2 or match.start() + count * 2 > len(data):
                continue
            address = section['address'] + match.start()
            values = struct.unpack_from('<' + str(count) + 'H', data, match.start())
            if 65535 not in values:
                candidates[address] = (values, section['offset'] + match.start() + mach.slice_offset)
    references = [(address, offset) for address, offset in index_references(mach) if address in candidates]
    # Preserve uncertainty if matching copies differ; no active branch is chosen.
    if not references or len({value[0] for value in candidates.values()}) != 1:
        return {}
    return {'resource_ids': list(candidates[references[0][0]][0]),
            'table_offsets': sorted(value[1] for value in candidates.values()),
            'index_reader_offsets': sorted({offset for _, offset in references})}
