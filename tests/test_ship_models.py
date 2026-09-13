"""Synthetic packed tables, structural anchors and indexed-read provenance."""
import importlib.util
import struct
import unittest

from test_bindings import executable
from test_materials import arm_wide
from gof2_content.registrations import MachO
from gof2_content.ship_models import extract_ship_models


def branch(address, target):
    value = (target - address - 4) & 0x1ffffff
    s, i1, i2 = [(value >> bit) & 1 for bit in (24, 23, 22)]
    return struct.pack('<HH', 0xf000 | (s << 10) | ((value >> 12) & 1023),
                       0xd000 | (((1 ^ i1) ^ s) << 13) | (((1 ^ i2) ^ s) << 11) | ((value >> 1) & 2047))


def fixture(edition, conflict=False, wrong_getter=False):
    mac = edition == 'mac-full-hd'
    data = bytearray(executable(edition))
    header, command_header, stride = (32, 72, 80) if mac else (28, 56, 68)
    struct.pack_into('<I', data, 20, command_header + 3 * stride)
    struct.pack_into('<I', data, header + 4, command_header + 3 * stride)
    struct.pack_into('<I', data, header + (64 if mac else 48), 3)
    text, const = (0x100002000, 0x100004000) if mac else (0x2000, 0x4000)
    getter = bytes.fromhex('55 48 89 e5 8b 07 5d c3' if mac else '00 68 70 47')
    if wrong_getter:
        getter = getter[:-1] + b'\x00'
    code = getter.ljust(16, b'\x00')
    if mac:
        code += (b'\xe8' + struct.pack('<i', -21) + bytes.fromhex('48 8d 0d')
                 + struct.pack('<i', const - text - 28) + bytes.fromhex('48 63 c0 0f b7 14 41'))
    else:
        displacement = const - text - 16 - 22
        code += (branch(text + 16, text) + arm_wide(displacement & 65535) + bytes.fromhex('00 23')
                 + arm_wide(displacement >> 16, top=True) + bytes.fromhex('cd f8 20 a0 79 44 31 f8 10 20'))
    struct.pack_into('<Q' if mac else '<I', data, header + command_header + (40 if mac else 36), len(code))
    data[512:512 + len(code)] = code
    ids = list(range(100, 108)) + [500, 901]
    table = struct.pack('<10H', *ids)
    if conflict:
        table += struct.pack('<10H', *(ids[:-1] + [902]))
    data.extend(bytes(2048 - len(data)))
    data.extend(table)
    at = header + command_header + 2 * stride
    data[at:at + 7] = b'__const'
    data[at + 16:at + 22] = b'__TEXT'
    struct.pack_into('<QQI' if mac else '<III', data, at + 32, const, len(table), 2048)
    rows = [{'id': 100 + i, 'kind': 'mesh', 'registration_type': 4,
             'resource': f'resources/data/assets/main/3d/meshes/ships/ship_{i:03d}_fixture.aem'} for i in range(8)]
    return MachO(bytes(data), edition), rows, ids


class ShipModelTests(unittest.TestCase):
    @unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
    def test_both_architectures_use_full_table_and_provenance(self):
        for edition in ['mac-full-hd', 'ios-hd']:
            mach, rows, ids = fixture(edition)
            result = extract_ship_models(mach, rows, 10)
            self.assertEqual(result['resource_ids'], ids)
            self.assertEqual(result['table_offsets'], [2048])
            self.assertEqual(result['index_reader_offsets'], [528])

    @unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
    def test_anchors_alone_and_conflicting_tables_do_not_prove_mapping(self):
        for edition in ['mac-full-hd', 'ios-hd']:
            for options in [{'conflict': True}, {'wrong_getter': True}]:
                mach, rows, _ = fixture(edition, **options)
                self.assertEqual(extract_ship_models(mach, rows, 10), {})
            mach, rows, _ = fixture(edition)
            self.assertEqual(extract_ship_models(mach, rows, 11), {})
            self.assertEqual(extract_ship_models(mach, rows[:-1], 10), {})
            self.assertEqual(extract_ship_models(mach, rows + [dict(rows[0], id=999)], 10), {})


if __name__ == '__main__':
    unittest.main()
