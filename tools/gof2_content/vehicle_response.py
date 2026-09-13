"""Declarative handling and maneuverability-equipment constants, read statically."""
import math
import re
import struct
from .steering import lit
from .ship_models import section_bytes


def extract_vehicle_response(mach, pilot):
    if not pilot or mach.architecture not in ('x86_64', 'armv7'):
        return {}
    mac = mach.architecture == 'x86_64'
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    base = text['address']
    provenance = {}
    if not mac:
        import capstone
        decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB)
        decoder.detail = True
    def unique(pattern):
        rows = [m for m in re.finditer(pattern, code, re.S) if mac or m.start() % 2 == 0]
        return rows[0] if len(rows) == 1 else None
    def region(name, address, length, expected=None):
        found = section_bytes(mach, address, length, b'__text')
        if found is None or expected is not None and found[0] != expected:
            raise ValueError('Unsupported linked layout')
        provenance[name] = {'offset': found[1], 'bytes': length}
        return found[0]
    def matched(name, match):
        if match is None: raise ValueError('Missing or ambiguous layout')
        region(name, base + match.start(), len(match[0]))
        return match
    def branch(match, group):
        address = base + match.start(group)
        if mac:
            return address + 4 + struct.unpack('<i', match[group])[0]
        ins = list(decoder.disasm(match[group], address))
        if len(ins) != 1 or ins[0].mnemonic != 'bl': raise ValueError('Unsupported call')
        return ins[0].operands[0].imm
    def constant(name, address, raw, register=None):
        if mac:
            target = address + 4 + struct.unpack('<i', raw)[0]
        else:
            ins = list(decoder.disasm(raw, address))
            if len(ins) != 1 or ins[0].mnemonic != 'vldr' or ins[0].op_str.split(',')[0] != register \
                    or len(ins[0].operands) != 2 or ins[0].operands[1].type != capstone.arm.ARM_OP_MEM \
                    or ins[0].operands[1].mem.base != capstone.arm.ARM_REG_PC:
                raise ValueError('Unsupported constant load')
            target = ((address + 4) & ~3) + ins[0].operands[1].mem.disp
        sections = [s for s in mach.sections if s['segment'] == b'__TEXT' and s['offset'] > 0
                    and s['address'] <= target and target + 4 <= s['address'] + s['length']]
        if len(sections) != 1: raise ValueError('Unbacked constant')
        s = sections[0]; offset = s['offset'] + target - s['address']
        if offset + 4 > len(mach.data): raise ValueError('Truncated constant')
        value = struct.unpack_from('<f', mach.data, offset)[0]
        if not math.isfinite(value): raise ValueError('Nonfinite constant')
        provenance[name] = {'offset': mach.slice_offset + offset, 'bytes': 4}
        return value
    def load(name, match, group, register=None):
        return constant(name, base + match.start(group), match[group], register)
    try:
        if mac:
            getter = matched('handling_getter', unique(lit('554889e5488b8f880000000f57c94885c9742b8b010f57c985c07422488b49080f57c931d2f30f1005') + rb'(.{4})' + lit('833c91') + rb'(.)' + lit('7504f30f58c848ffc239c272eff30f104718f30f5805') + rb'(.{4})' + lit('f30f5e05') + rb'(.{4})' + lit('f30f5905') + rb'(.{4})' + lit('f30f5805') + rb'(.{4})' + lit('f30f58c15dc3')))
            upgrade = load('upgrade_bonus', getter, 1)
            tag = getter[2][0]
            conversion = [load(name, getter, group) for name, group in [('base_add', 3), ('base_divisor', 4), ('base_scale', 5), ('base_offset', 6)]]
            setup = matched('response_setup', unique(lit('e8') + rb'(.{4})' + lit('0f57c0f30f2ac0f30f1183f0020000f30f5e05') + rb'(.{4})' + lit('f30f108ba4010000f30f59c1f30f58c1f30f5905') + rb'(.{4})' + lit('f30f1183a4010000')))
            region('equipment_getter', branch(setup, 1), 9, bytes.fromhex('554889e58b47405dc3'))
            percent = load('percent_divisor', setup, 2)
            scale = load('response_scale', setup, 3)
            stores = list(re.finditer(lit('e8') + rb'(.{4})' + lit('f30f1183a4010000'), code[max(0, setup.start()-512):setup.start()], re.S))
            links = [m for m in stores if base + max(0, setup.start()-512) + m.start(1) + 4 + struct.unpack('<i',m[1])[0] == base + getter.start()]
            if len(links) != 1: raise ValueError('Handling setup link missing')
            region('handling_setup', base + max(0, setup.start()-512) + links[0].start(), len(links[0][0]))
            equipment = matched('equipment_assignment', unique(lit('498b4770488b40084a8b3c30be') + rb'(.{4})' + lit('e8') + rb'(.{4})' + lit('41894740')))
            property_id = struct.unpack('<I', equipment[1])[0]
            region('property_getter', branch(equipment, 2), 42, bytes.fromhex('554889e5488b4f388b3931d2eb044883c202b8257899c539fa730d488b410839349075ea8b4490045dc3'))
            selector = matched('equipment_selector', unique(lit('e8') + rb'(.{4})' + lit('83f81d0f87') + rb'.{4}' + lit('89c0486304834801d8ffe0')))
            region('type_getter', branch(selector, 1), 9, bytes.fromhex('554889e58b47085dc3'))
            # The table is relative to the LEA target established before this selector.
            window_start = max(0, selector.start()-128)
            tables = list(re.finditer(lit('488d1d') + rb'(.{4})', code[window_start:selector.start()], re.S))
            if len(tables) != 1: raise ValueError('Ambiguous equipment table')
            table_load = tables[0]
            address = base + window_start + table_load.start()
            table = address + 7 + struct.unpack('<i', table_load[1])[0]
            region('equipment_table_load', address, 7)
            rows = struct.unpack('<30i', region('equipment_table', table, 120))
            type_ids = [i for i, offset in enumerate(rows) if table+offset == base+equipment.start()]
            matched('item_type_layout', unique(lit('554889e5488b47384885c0747d488b48088b4904890f488b48088b490c894f04488b48088b4914894f08')))
        else:
            setup = matched('response_setup', unique(rb'(.{4})' + lit('40ec300bbbff2006') + rb'(.{4})' + lit('80ee0a1a85ed940a95ed540a40ff110d40ef200d00ffb20d85ed540a')))
            getter_pattern = lit('826f002a1cbfd2f80090b9f1000f02d1c0ef10000ee0c0ef10005268') + rb'(.{4})' + lit('002352f823100133') + rb'(.)' + lit('2908bf40ef800d4b45f6d390ed060a00ef800d10ee100a7047')
            targets = []
            for at in range(max(0, setup.start()-512), setup.start(), 2):
                if code[at+4:at+8] != bytes.fromhex('c5f85001'): continue
                ins = list(decoder.disasm(code[at:at+4], base+at))
                if len(ins)==1 and ins[0].mnemonic=='bl': targets.append(ins[0].operands[0].imm)
            getters = [g for g in re.finditer(getter_pattern,code,re.S) if base+g.start() in targets and g.start()%2==0]
            getter = matched('handling_getter',getters[0] if len(getters)==1 else None)
            upgrade = load('upgrade_bonus', getter, 1, 's0')
            tag = getter[2][0]
            conversion = [0.0, 1.0, 1.0, 0.0]  # Recognized direct-base getter, no conversion.
            region('equipment_getter', branch(setup, 1), 4, bytes.fromhex('006c7047'))
            ins = list(decoder.disasm(setup[2], base+setup.start(2)))
            if len(ins)!=1 or ins[0].mnemonic!='vmov.f32' or ins[0].op_str.split(',')[0]!='d18' \
                    or len(ins[0].operands)!=2 or ins[0].operands[1].type!=capstone.arm.ARM_OP_FP:
                raise ValueError('Unsupported response scale')
            scale = ins[0].operands[1].fp
            region('response_scale', base+setup.start(2), 4)
            # A unique s20 literal load supplies the denominator in this setup region.
            start = max(0,setup.start()-512)
            loads=[];links=[]
            for at in range(start,setup.start(),2):
                raw=code[at:at+4]
                decoded=list(decoder.disasm(raw,base+at))
                if len(decoded)==1 and decoded[0].mnemonic=='vldr' and decoded[0].op_str.startswith('s20, [pc,'):
                    loads.append(at)
                if code[at+4:at+8] == bytes.fromhex('c5f85001') and len(decoded)==1 and decoded[0].mnemonic=='bl' and decoded[0].operands[0].imm==base+getter.start():
                    links.append(at)
            if len(loads)!=1 or len(links)!=1: raise ValueError('Missing handling/denominator setup')
            region('percent_load',base+loads[0],4)
            percent=constant('percent_divisor',base+loads[0],code[loads[0]:loads[0]+4],'s20')
            region('handling_setup',base+links[0],8)
            equipment = matched('equipment_assignment', unique(lit('e06e') + rb'(.)' + lit('2140688059') + rb'(.{4})' + lit('2064')))
            property_id=equipment[1][0]
            region('property_getter',branch(equipment,2),48,bytes.fromhex('026bd2f80090b9f1000f08d05268002352f82300884207d002334b45f8d347f62500ccf29950704702eb830040687047'))
            selector_pattern = rb'(.{4})' + lit('1d2800f2') + rb'.{2}' + lit('dfe800f0')
            selectors=[]
            for candidate in re.finditer(selector_pattern,code,re.S):
                if candidate.start()%2: continue
                table=base+candidate.end()
                found=section_bytes(mach,table,30,b'__text')
                if found is not None and any(table+x*2==base+equipment.start() for x in found[0]): selectors.append(candidate)
            selector = matched('equipment_selector',selectors[0] if len(selectors)==1 else None)
            region('type_getter',branch(selector,1),4,bytes.fromhex('80687047'))
            table=base+selector.end()
            rows=region('equipment_table',table,30)
            type_ids=[i for i,offset in enumerate(rows) if table+offset*2==base+equipment.start()]
            matched('item_type_layout',unique(lit('016b002908bf70474968c0ef50004a680260ca6842604a698260')))
        if len(type_ids)!=1: raise ValueError('Missing equipment type binding')
        if not (0<upgrade<=10 and 0<percent<=10000 and 0<scale<=10000 and 0<=tag<=255 and 0<=property_id<=65535):
            raise ValueError('Unsupported vehicle constants')
        if not all(math.isfinite(v) and abs(v)<=100 for v in conversion) or conversion[1]<=0 or conversion[2]<=0:
            raise ValueError('Unsupported base conversion')
        return {'base_add':conversion[0],'base_divisor':conversion[1],'base_scale':conversion[2],'base_offset':conversion[3],
                'upgrade_tag':tag,'upgrade_bonus':upgrade,'equipment_type':type_ids[0],'item_type_value_index':5,
                'equipment_percent_property':property_id,'percent_divisor':percent,'response_scale':scale,
                'equipment_rule':'last_matching','provenance':provenance}
    except (ValueError,struct.error,IndexError):
        return {}
