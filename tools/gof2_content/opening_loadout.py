"""Read the bounded opening ship/location/equipment declaration, never execute it.

This is an initial loadout seed, not campaign state or a playable opening mission.
Compiler layouts are recognized as a whole; unsupported/ambiguous layouts yield
no seed. Only catalogue indices, quantities, slots and source extents are emitted.
"""
import re
import struct
from .ship_models import section_bytes


def template(spec):
    """Hex runs and named fixed-width fields in a declaration layout."""
    pieces = []
    for token in spec.split():
        if token.startswith('{'):
            name, size = token[1:-1].split(':')
            pieces.append(('(?P<%s>.{%s})' % (name, size)).encode())
        else:
            pieces.append(re.escape(bytes.fromhex(token)))
    return re.compile(b''.join(pieces), re.S)


MAC = '''
488d05 {ship_global:4} 488b00488b4008488b78 {ship:1} beffffffffe8 {ship_clone:4}
4c89f74889c6e8 {ship_assign:4} 498bbe00020000e8 {ship_price:4}
488d05 {world_global:4} 488b38be {station:4} e8 {station_lookup:4}
4c89f74889c6e8 {station_assign:4} 498bbe0002000031f6e8 {cargo_clear:4}
488d1d {item_global:4}
488b03488b4008488b78 {item0:1} e8 {clone0:4} 498bbe000200004889c631d2e8 {install0:4}
488b03488b4008488b78 {item1:1} e8 {clone1:4} 498bbe000200004889c6ba {slot1:4} e8 {install1:4}
488b03488b4008488bb8 {item2:4} e8 {clone2:4} 498bbe000200004889c631d2e8 {install2:4}
488b03488b4008488bb8 {item3:4} e8 {clone3:4} 498bbe000200004889c6ba {slot3:4} e8 {install3:4}
488b03488b4008488bb8 {item4:4} e8 {clone4:4} 498bbe000200004889c6ba {slot4:4} e8 {install4:4}
488b03488b4008488bb8 {item5:4} e8 {clone5:4} 498bbe000200004889c6ba {slot5:4} e8 {install5:4}
488b03488b4008488bb8 {item6:4} be {quantity:4} e8 {stack_clone:4}
488d0d {player_global:4} 488b09488bb9000200004889c631d2e8 {install6:4}
'''
ARM = '''
08684ff0ff314068 {ship:2} 1894 {ship_clone:4} 014630461894 {ship_assign:4}
d6f87c011894 {ship_price:4} 0498 {station:1} 2100681894 {station_lookup:4}
014630461894 {station_assign:4} d6f87c0100211894 {cargo_clear:4} 029d
28684068 {item0:2} 1894 {clone0:4} 0146d6f87c01 {slot0:1} 221894 {install0:4}
28684068 {item1:2} 1894 {clone1:4} 0146d6f87c01 {slot1:1} 2218944ff00108 {install1:4}
28684068 {item2:4} 1894 {clone2:4} 0146d6f87c01 {slot2:1} 221894 {install2:4}
28684068 {item3:4} 1894 {clone3:4} 0146d6f87c01 {slot3:1} 221894 {install3:4}
28684068 {item4:4} 1894 {clone4:4} 0146d6f87c01 {slot4:1} 221894 {install4:4}
28684068 {item5:4} 1894 {clone5:4} 0146d6f87c01 {slot5:1} 221894 {install5:4}
2868 {quantity:1} 214068 {item6:4} 1894 {stack_clone:4}
0146 {player_low:4} {player_high:4} {slot6:1} 22784400680068d0f87c011894 {install6:4}
'''
MAC_CLONE = '554889e553508b5f18e8 {inner:4} 895818c740 {count:1} {quantity:4} 4883c4085b5dc3'
MAC_STACK = '554889e541565389f3448b7718e8 {inner:4} 448970188958 {count:1} 5b415e5dc3'
ARM_CLONE = '90b501af8469 {inner:4} {quantity:1} 218461416390bd'
ARM_STACK = 'b0b502af0c468569 {inner:4} 85614463b0bd'
MAC_INSTALL = '''554889e5415741564154534189d44989f64989ff4c89f7e8 {category0:4}
85c07e1931db498b47684403249848ffc34c89f7e8 {category1:4} 39c37ce9'''
ARM_INSTALL = '0d46804628461646 {category0:4} 0446'


def extract_opening_loadout(mach, vehicle):
    # Its recognized item constructor establishes category at property-array[3].
    if not vehicle or vehicle.get('item_type_value_index') != 5:
        return {}
    mac = mach.architecture == 'x86_64'
    if not mac and mach.architecture != 'armv7': return {}
    import capstone
    decoder = capstone.Cs(capstone.CS_ARCH_X86 if mac else capstone.CS_ARCH_ARM,
                          capstone.CS_MODE_64 if mac else capstone.CS_MODE_THUMB)
    decoder.detail = True
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    base = text['address']
    rows = [m for m in template(MAC if mac else ARM).finditer(code) if mac or m.start() % 2 == 0]
    if len(rows) != 1: return {}
    seed = rows[0]
    provenance = {'declaration': {'offset': mach.slice_offset + text['offset'] + seed.start(), 'bytes': len(seed[0])}}
    def number(match, key): return int.from_bytes(match[key], 'little')
    def target(match, address, key):
        at = address + match.start(key)
        if mac: return at + 4 + struct.unpack('<i', match[key])[0]
        ins = list(decoder.disasm(match[key], at))
        if len(ins) != 1 or ins[0].mnemonic != 'bl': raise ValueError('Unsupported declaration call')
        return ins[0].operands[0].imm
    def region(name, address, spec):
        pattern = template(spec)
        # All supported helper declarations are shorter than this bound.
        found = section_bytes(mach, address, 128, b'__text')
        if found is None: raise ValueError('Missing helper extent')
        match = pattern.match(found[0])
        if match is None: raise ValueError('Unsupported linked helper')
        provenance[name] = {'offset': found[1], 'bytes': len(match[0])}
        return match
    def load_index(key):
        raw = seed[key]
        if mac:
            displacement = int.from_bytes(raw, 'little', signed=True)
        else:
            ins = list(decoder.disasm(raw, base + seed.start(key)))
            if len(ins) != 1 or ins[0].mnemonic not in ('ldr', 'ldr.w') or len(ins[0].operands) != 2:
                raise ValueError('Unsupported catalogue selection')
            a, b = ins[0].operands
            if a.type != capstone.arm.ARM_OP_REG or a.reg != capstone.arm.ARM_REG_R0 or b.type != capstone.arm.ARM_OP_MEM \
                    or b.mem.base != capstone.arm.ARM_REG_R0 or b.mem.index != 0:
                raise ValueError('Unsupported catalogue pointer')
            displacement = b.mem.disp
        width = 8 if mac else 4
        if displacement < 0 or displacement % width: raise ValueError('Invalid catalogue index')
        return displacement // width
    try:
        calls = {key: target(seed, base, key) for key in seed.groupdict()
                 if key.startswith(('clone', 'install')) or key in ('stack_clone', 'ship_clone', 'ship_assign', 'ship_price', 'station_lookup', 'station_assign', 'cargo_clear')}
        if len({calls['clone%d' % i] for i in range(6)}) != 1 or len({calls['install%d' % i] for i in range(7)}) != 1:
            raise ValueError('Inconsistent equipment declarations')
        clone = region('item_clone', calls['clone0'], MAC_CLONE if mac else ARM_CLONE)
        stack = region('stack_clone', calls['stack_clone'], MAC_STACK if mac else ARM_STACK)
        if target(clone, calls['clone0'], 'inner') != target(stack, calls['stack_clone'], 'inner'):
            raise ValueError('Different item constructors')
        if mac and (number(clone, 'count') != 0x40 or number(stack, 'count') != 0x40):
            raise ValueError('Unknown item count field')
        install_address = calls['install0'] + (0 if mac else 28)
        install = region('install_category', install_address, MAC_INSTALL if mac else ARM_INSTALL)
        getter = target(install, install_address, 'category0')
        if mac and getter != target(install, install_address, 'category1'): raise ValueError('Inconsistent slot category')
        region('category_getter', getter, '554889e58b47045dc3' if mac else '40687047')
        if not mac:
            loop = region('slot_offsets', calls['install0'] + 0x5e,
                'd8f8680050f824000134cdf820a006442846 {category:4} 8442f2db')
            if target(loop, calls['install0'] + 0x5e, 'category') != getter: raise ValueError('Different slot category')
        if mac:
            region('ship_clone', calls['ship_clone'], '554889e5535089f3e8 {inner:4} 85db78038958144883c4085b5dc3')
        else:
            region('ship_clone', calls['ship_clone'], '90b501af0c46 {inner:4} 002ca8bf446190bd')
        # Every additional link must point into file-backed code, including calls
        # whose full semantics (price/cargo/scene state) are not exported here.
        if any(section_bytes(mach, address, 4, b'__text') is None for address in calls.values()):
            raise ValueError('Unbacked declaration call')
        if not mac:
            for key, mnemonic in [('player_low', 'movw'), ('player_high', 'movt')]:
                ins = list(decoder.disasm(seed[key], base + seed.start(key)))
                if len(ins) != 1 or ins[0].mnemonic != mnemonic or len(ins[0].operands) != 2 or ins[0].operands[0].reg != capstone.arm.ARM_REG_R0:
                    raise ValueError('Unsupported player reference')
        entries = []
        for i in range(7):
            slot = number(seed, 'slot%d' % i) if 'slot%d' % i in seed.groupdict() else 0
            qty = number(seed, 'quantity') if i == 6 else number(clone, 'quantity')
            item_id = load_index('item%d' % i)
            if not (0 <= item_id < 4096 and 0 <= slot < 256 and 1 <= qty <= 2147483647):
                raise ValueError('Unsupported equipment record')
            entries.append({'item_id': item_id, 'slot': slot, 'quantity': qty})
        ship = load_index('ship'); station = number(seed, 'station')
        if not 0 <= ship < 4096 or not 0 <= station < 4096: raise ValueError('Invalid opening location/ship')
        return {'ship_id': ship, 'station_id': station, 'equipment': entries,
                'item_category_value_index': 3, 'provenance': provenance}
    except (ValueError, IndexError, struct.error):
        return {}
