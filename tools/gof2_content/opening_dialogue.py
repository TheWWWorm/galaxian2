"""Bounded readers for the opening and rescue declarative radio-event lists.

The reader accepts one compiler layout per architecture, verifies dispatch slot
zero/one and linked record constructors, and emits data only. It does not interpret
mission code, execute instructions or infer campaign completion from dialogue.
"""
import struct
from .opening_loadout import template
from .ship_models import section_bytes

MAC_SINGLE = '554889e54156534489c34989fe49c746080000000049c70600000000418976104189561441894e1841895e1cbf04000000e8 {allocate:4} 49894628891841c746200100000041c646300041c646310041c74634000000005b415e5dc3'
MAC_RANGE = '554889e54157415653504489cb4589c74989fe49c746080000000049c70600000000418976104189561441894e1845897e1c4863c3b90400000048f7e148c7c7ffffffff480f41f8e8 {allocate:4} 85db498946287e198d4bff31d2eb0748ffc2498b4628418d341789349039d175ee41895e2041c646300041c646310041c74634000000004883c4085b415e415f5dc3'
ARM_SINGLE = 'f0b503af04460026042004f108092660bd68666089e82e00 {allocate:4} e06105600120a061204684f8206084f821606662f0bd'
ARM_RANGE = 'f0b503af2de90005d7f80c80044604204ff0000a04f10809c4f800a0a8fb0006bd68c4f804a089e82e00002e18bf0126002e18bf4ff0ff30 {allocate:4} e061b8f1010f05db414640f8045b01350139fad1c4f81880204684f820a084f821a0c4f824a0bde80005f0bd'


class Declaration:
    """Consume a finite declaration grammar, with no arbitrary instruction runner."""
    def __init__(self, mach, address, decoder, bound=2048):
        region = section_bytes(mach, address, bound, b'__text')
        if region is None: raise ValueError('Truncated declaration')
        self.instructions = iter(decoder.disasm(region[0], address))
        self.end = address

    def take(self, mnemonic=None, operands=None):
        ins = next(self.instructions)
        if not ins.id or (mnemonic is not None and ins.mnemonic != mnemonic) or (operands is not None and ins.op_str != operands):
            raise ValueError(f'Unsupported declaration at {ins.address:x}: {ins.mnemonic} {ins.op_str}; expected {mnemonic} {operands}')
        self.end = ins.address + ins.size
        return ins

    def number(self, register):
        ins = self.take()
        if ins.mnemonic == 'xor' and ins.op_str == f'{register}, {register}': return 0
        if ins.mnemonic not in ('mov', 'movs', 'movw', 'mov.w') or len(ins.operands) != 2 or ins.reg_name(ins.operands[0].reg) != register or ins.operands[1].type != 2:
            raise ValueError('Nonconstant declaration field')
        return ins.operands[1].imm

    def call(self, mnemonic):
        ins = self.take(mnemonic)
        if ins.operands[0].type != 2: raise ValueError('Indirect declaration call')
        return ins.operands[0].imm


def extract_opening_dialogue(mach):
    return extract_dialogue(mach, 0)


def extract_arrival_dialogue(mach, opening):
    """Slot one is accepted only with its independently verified opening owner."""
    if not opening:
        return {}
    result = extract_dialogue(mach, 1)
    if not result:
        return {}
    for key in ('dispatch', 'dispatch_table', 'single_constructor', 'duration', 'display_delay'):
        if result['provenance'][key] != opening.get('provenance', {}).get(key):
            return {}
    # Both declarations must return to the same list-construction epilogue.
    import capstone
    mac = mach.architecture == 'x86_64'
    decoder = capstone.Cs(capstone.CS_ARCH_X86 if mac else capstone.CS_ARCH_ARM,
                          capstone.CS_MODE_64 if mac else capstone.CS_MODE_THUMB)
    decoder.detail = True
    exits = []
    for data in (opening, result):
        span = data['provenance'].get('shared_store', data['provenance']['declaration'])
        offset = span['offset'] + span['bytes'] - (5 if mac else 4) - mach.slice_offset
        address = mach.text['address'] + offset - mach.text['offset']
        rows = list(decoder.disasm(mach.data[offset:offset + (5 if mac else 4)], address))
        if len(rows) != 1 or rows[0].mnemonic != ('jmp' if mac else 'b.w'):
            return {}
        exits.append(rows[0].operands[0].imm)
    return result if exits[0] == exits[1] else {}


def extract_dialogue(mach, cursor):
    if cursor not in (0, 1): return {}
    import capstone
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    decoder = capstone.Cs(capstone.CS_ARCH_X86 if mac else capstone.CS_ARCH_ARM,
                          capstone.CS_MODE_64 if mac else capstone.CS_MODE_THUMB)
    decoder.detail = True
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    # Only constant dispatch data are followed, never arbitrary branch execution.
    candidates = []
    pattern = (template('4989ff49c787b00100000000000081fea10000000f87 {outside:4} 89f0488d0d {table:4} 486304814801c8ffe0') if mac else
               template('a12c {outside:4} dfe814f0'))
    for match in pattern.finditer(code):
        if not mac and match.start() % 2: continue
        try:
            address = text['address'] + match.start()
            if mac:
                table = address + match.end('table') - match.start() + struct.unpack('<i', match['table'])[0]
                data = section_bytes(mach, table, 162 * 4, b'__text')
                if data is None: raise ValueError('Missing dispatch table')
                start = table + struct.unpack_from('<i', data[0], cursor * 4)[0]
            else:
                jump = list(decoder.disasm(match['outside'], address + 2))
                if len(jump) != 1 or jump[0].mnemonic != 'bhi.w': raise ValueError('Unsupported cursor guard')
                table = address + len(match[0])
                data = section_bytes(mach, table, 162 * 2, b'__text')
                if data is None: raise ValueError('Missing dispatch table')
                start = table + 2 * struct.unpack_from('<H', data[0], cursor * 2)[0]
            result = read_list(mach, start, decoder, mac, cursor)
            timing, extents = read_timing(mach, code, decoder)
            result['timing'] = timing
            result['provenance'].update(extents)
            result['provenance']['dispatch'] = {'offset': mach.slice_offset + text['offset'] + match.start(), 'bytes': len(match[0])}
            result['provenance']['dispatch_table'] = {'offset': data[1], 'bytes': len(data[0])}
            candidates.append(result)
        except (ValueError, StopIteration, IndexError, struct.error):
            continue
    return candidates[0] if len(candidates) == 1 else {}


def read_list(mach, address, decoder, mac, cursor=0):
    if cursor not in (0, 1): raise ValueError('Unsupported radio owner')
    d = Declaration(mach, address, decoder)
    t = d.take
    if mac:
        if d.number('edi') != 24: raise ValueError('Unknown list')
        allocator = d.call('call'); t('mov', 'rbx, rax')
        if d.number('edi') != 8: raise ValueError('Unknown list width')
        array_allocator = d.call('call')
        for op in ['qword ptr [rbx + 8], rax', 'dword ptr [rbx + 0x10], 1', 'qword ptr [rax], 0', 'dword ptr [rbx], 0', 'qword ptr [r15 + 0x1b0], rbx']: t('mov', op)
        count = d.number('edi'); t('mov', 'rsi, rbx'); reserve = d.call('call')
    else:
        slot = '0x18' if cursor == 0 else '0x78'
        frame_id = 1 if cursor == 0 else 25
        t('mov.w', 'r0, #-1'); t('str.w', 'r0, [sp, #0x5f0]'); t('movs', 'r0, #0xc')
        allocator = d.call('blx'); t('str', f'r0, [sp, #{slot}]')
        if d.number('r0') != frame_id: raise ValueError('Unsupported list construction frame')
        t('str.w', 'r0, [sp, #0x5f0]'); t('movs', 'r0, #4'); t('str', 'r5, [sp, #0x14]')
        array_allocator = d.call('blx')
        for op in [('ldr',f'r1, [sp, #{slot}]'),('movs','r3, #1'),('ldr',f'r2, [sp, #{slot}]'),('str','r0, [r2, #4]'),('ldr',f'r2, [sp, #{slot}]'),('str','r3, [r2, #8]'),('movs','r2, #0'),('str','r2, [r0]'),('ldr',f'r0, [sp, #{slot}]'),('str','r2, [r0]'),('ldr','r0, [sp, #0x14]'),('str.w','r1, [r0, #0x114]')]: t(*op)
        count = d.number('r0'); reserve = d.call('bl')
    if count != (23 if cursor == 0 else 3): raise ValueError('Unsupported radio list size')
    shared_store = None
    rows, single_targets, range_targets = [], set(), set()
    for index in range(count):
        if mac:
            if d.number('edi') != 56 or d.call('call') != allocator: raise ValueError('Unknown event allocation')
            t('mov', 'rbx, rax'); t('mov', 'rdi, rbx')
            string_id, speaker, condition, value = [d.number(r) for r in ('esi','edx','ecx','r8d')]
            if index == 9:
                amount = d.number('r9d'); range_targets.add(d.call('call'))
            else:
                amount = 1; single_targets.add(d.call('call'))
            t('mov', 'rax, qword ptr [r15 + 0x1b0]'); t('mov', 'rax, qword ptr [rax + 8]')
            suffix = '' if index == 0 else f' + 0x{index * 8:x}' if index > 1 else ' + 8'
            t('mov', f'qword ptr [rax{suffix}], rbx')
        else:
            t('mov.w','r0, #-1'); t('str.w','r0, [sp, #0x5f0]'); t('movs','r0, #0x28')
            if d.call('blx') != allocator: raise ValueError('Unknown event allocation')
            if d.number('r1') != index + (2 if cursor == 0 else 26): raise ValueError('Unsupported constructor frame')
            slot = f'0x{(28 if cursor == 0 else 124) + index * 4:x}'
            t('str',f'r0, [sp, #{slot}]'); t('ldr',f'r0, [sp, #{slot}]'); t('str.w','r1, [sp, #0x5f0]')
            if index == 9:
                value = d.number('r2'); amount = d.number('r1'); t('str','r2, [sp]')
                speaker = d.number('r2'); t('str','r1, [sp, #4]')
            else:
                value = d.number('r1'); speaker = d.number('r2'); t('str','r1, [sp]'); amount = 1
            string_id = d.number('r1'); condition = d.number('r3')
            (range_targets if index == 9 else single_targets).add(d.call('bl'))
            t('ldr',f'r0, [sp, #{slot}]')
            if cursor == 1 and index == 2:
                shared_address = d.call('b.w')
                shared_store = Declaration(mach, shared_address, decoder, 14)
                t = shared_store.take
            owner = 'r2' if index == 22 or (cursor == 1 and index == 2) else 'r1'
            t('ldr',f'{owner}, [sp, #0x14]'); t('ldr.w',f'r1, [{owner}, #0x114]'); t('ldr','r1, [r1, #4]')
            suffix = '' if index == 0 else f', #0x{index * 4:x}' if index > 2 else f', #{index * 4}'
            t('str',f'r0, [r1{suffix}]')
        if not (0 <= string_id < 65536 and 0 <= speaker < 65536 and condition in (5,6,9,27) and 0 <= value <= 2147483647 and 1 <= amount <= 256):
            raise ValueError('Invalid radio declaration')
        if condition != 9 and amount != 1: raise ValueError('Unexpected event value range')
        if value + amount - 1 > 2147483647: raise ValueError('Event value range overflow')
        if condition == 6 and (value >= count or value == index): raise ValueError('Invalid event dependency')
        rows.append({'text_id':string_id,'speaker_id':speaker,'condition':condition,'values':list(range(value,value+amount))})
    end_target = (shared_store or d).call('jmp' if mac else 'b.w')
    if len(single_targets) != 1 or len(range_targets) != (1 if cursor == 0 else 0): raise ValueError('Inconsistent record constructors')
    if cursor == 1 and [(r['condition'], r['values']) for r in rows] != [(5, [rows[0]['values'][0]]), (6, [0]), (6, [1])]:
        raise ValueError('Unsupported rescue radio dependencies')
    provenance = {'declaration': {'offset': section_bytes(mach,address,d.end-address,b'__text')[1], 'bytes': d.end-address}}
    if shared_store:
        provenance['shared_store'] = {'offset': section_bytes(mach,shared_address,14,b'__text')[1], 'bytes': 14}
    def helper(name, start, spec):
        raw = section_bytes(mach,start,192,b'__text')
        match = template(spec).match(raw[0]) if raw else None
        if match is None: raise ValueError('Unknown record constructor')
        provenance[name] = {'offset':raw[1], 'bytes':len(match[0])}
        if 'allocate' in match.groupdict():
            at = start + match.start('allocate')
            if mac:
                allocator_target = at + 4 + struct.unpack('<i', match['allocate'])[0]
            else:
                instructions = list(decoder.disasm(match['allocate'], at))
                if len(instructions) != 1 or instructions[0].mnemonic != 'blx': raise ValueError('Invalid constructor allocation')
                allocator_target = instructions[0].operands[0].imm
            if allocator_target != array_allocator: raise ValueError('Inconsistent constructor allocation')
        return match
    helper('single_constructor',next(iter(single_targets)),MAC_SINGLE if mac else ARM_SINGLE)
    if cursor == 0:
        read_range_constructor(mach, decoder, mac, next(iter(range_targets)), helper)
    for target in [allocator,array_allocator,reserve,end_target]:
        # External allocator stubs may live in __symbol_stub4 on ARM.
        if not any(s['address'] <= target < s['address']+s['length'] for s in mach.sections): raise ValueError('Unbacked declaration link')
    return {'campaign_cursor':cursor,'events':rows,'provenance':provenance}


def read_range_constructor(mach, decoder, mac, wrapper_address, helper):
    wrapper = helper('range_wrapper',wrapper_address,'554889e55de9 {inner:4}' if mac else '90b501af82b00446b868d7f80c908de801022046 {inner:4} 204602b090bd')
    at = wrapper_address + wrapper.start('inner')
    if mac: inner = at + 4 + struct.unpack('<i',wrapper['inner'])[0]
    else:
        ins = list(decoder.disasm(wrapper['inner'],at))
        if len(ins)!=1 or ins[0].mnemonic!='bl': raise ValueError('Unknown range link')
        inner = ins[0].operands[0].imm
    helper('range_constructor',inner,MAC_RANGE if mac else ARM_RANGE)


def read_timing(mach, code, decoder):
    # Recognized radio layout: start delay, fixed overhead, then time per wrapped
    # source-layout line. A changed timing layout is unsupported, never guessed.
    if mach.architecture == 'x86_64':
        specs = {
            'duration': '488b45b049894528498b45106900d007000005dc0500004189453841c6453d01',
            'display_delay': 'b8d0070000480343284839f0488975a80f8d {end:4} f6433d01',
        }
    else:
        specs = {
            'duration': '0e9a4ff4fa61109850610f98906190680068484300f2dc505062012082f82900',
            'display_delay': '3346002253f8140f596810f5fa6041f10001a0424ff0000028bf01205145a8bf012208bf0246002a {end:4}',
        }
    provenance = {}
    for key, spec in specs.items():
        matches = list(template(spec).finditer(code))
        if len(matches) != 1: raise ValueError('Unknown radio timing layout')
        m = matches[0]
        if mach.architecture == 'armv7':
            if m.start() % 2: raise ValueError('Unaligned radio timing layout')
            if key == 'display_delay':
                ins = list(decoder.disasm(m['end'], mach.text['address'] + m.start('end')))
                if len(ins) != 1 or ins[0].mnemonic != 'bne.w': raise ValueError('Unknown radio delay guard')
        provenance[key] = {'offset': mach.slice_offset + mach.text['offset'] + m.start(), 'bytes': len(m[0])}
    return {'display_delay_ms': 2000, 'base_duration_ms': 1500, 'per_line_ms': 2000}, provenance
