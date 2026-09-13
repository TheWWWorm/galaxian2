"""Synthetic compiler layouts with relocated tables and altered source values."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest

from gof2_content.hangars import extract_hangars
from test_materials import arm_wide
from test_ship_models import branch


def fixture(mac):
    base = 0x100002000 if mac else 0x2000
    const = base + 4096
    code = bytearray(1024)
    root = 640
    ids = [4100, 4101, 4102]
    def put(at, data):
        code[at:at + len(data)] = data
    def call(at, target):
        return b'\xe8' + struct.pack('<i', target - at - 5)
    if mac:
        put(16, bytes.fromhex('554889e58b47105dc3'))
        put(32, bytes.fromhex('554889e58b47285dc3'))
        selector = 320
        data = bytearray(call(selector, 16) + b'\xb9' + struct.pack('<I', 8) + b'\x83\xf8\x05\x74\x3a')
        at = selector + len(data)
        data += bytes.fromhex('488d05') + bytes(4) + bytes.fromhex('488b38') + call(at + 10, 48) + bytes.fromhex('4889c7') + call(at + 18, 16)
        data += b'\xb9' + struct.pack('<I', 7) + bytes.fromhex('83f8047419')
        at = selector + len(data)
        data += bytes.fromhex('488d05') + bytes(4) + bytes.fromhex('488b38') + call(at + 10, 48) + bytes.fromhex('4889c7') + call(at + 18, 32) + bytes.fromhex('89c14189cc')
        put(selector, data)
        put(root - 40, bytes.fromhex('4489e3895db04c63f3'))
        put(root, bytes.fromhex('4c89f048c1e004488d0d') + struct.pack('<i', const - base - root - 14) + bytes.fromhex('4801c8428b1ca8'))
        put(root + 64, bytes.fromhex('c745c800000000c745cc') + struct.pack('<f', 1.25) + bytes.fromhex('c745d0000000004c89ef488d75c8') + call(root + 92, 48))
        at = root + 112
        put(at, bytes.fromhex('488d05') + struct.pack('<i', const + 160 - base - at - 7) + bytes.fromhex('468b3cb04531e4'))
        at = root + 144
        put(at, bytes.fromhex('488d05') + struct.pack('<i', const + 176 - base - at - 7) + bytes.fromhex('428b04b04401e00fb7f0'))
        corrupt_getter = 20
        corrupt_join = selector + 14
    else:
        put(16, bytes.fromhex('80687047'))
        put(32, bytes.fromhex('c0697047'))
        first, second = 128, 160
        fallback = bytes.fromhex('28680b954ff0ff352895') + branch(base + second + 20, base + 48) + bytes.fromhex('2895') + branch(base + second + 26, base + 32)
        join = second + 10 + len(fallback)
        for at, station, row, fall in [(first, 5, 8, second - 14), (second, 4, 7, second + 10)]:
            put(at - 4, branch(base + at - 4, base + 16))
            put(at, bytes([station, 0x28, (fall - at - 6) // 2, 0xd1, 0x0b, 0x95, row, 0x20]) + struct.pack('<H', 0xe000 | ((join - at - 12) // 2)))
        put(second + 10, fallback)
        put(join, bytes.fromhex('1090'))
        disp = const - base - root - 16
        put(root, arm_wide(disp & 65535, 0) + bytes.fromhex('0021') + arm_wide(disp >> 16, 0, True) + bytes.fromhex('109c784400eb04100a90'))
        put(root + 34, bytes.fromhex('0a9850f82150'))
        at = root + 64
        bits = struct.unpack('<I', struct.pack('<f', 1.25))[0]
        put(at, arm_wide(bits & 65535, 0) + bytes.fromhex('0025') + arm_wide(bits >> 16, 0, True) + bytes.fromhex('12a9129513904ff0ff3620461495'))
        at = root + 128
        disp = const + 176 - base - at - 14
        put(at, arm_wide(disp & 65535, 0) + bytes.fromhex('0025') + arm_wide(disp >> 16, 0, True) + bytes.fromhex('784450f82400'))
        at = root + 176
        disp = const + 160 - base - at - 14
        put(at, arm_wide(disp & 65535, 0) + arm_wide(disp >> 16, 0, True) + bytes.fromhex('119d7844013550f824008542'))
        corrupt_getter, corrupt_join = 16, first + 8
    table = ids + [-1] * 37
    table[7 * 4] = 4900
    table[8 * 4] = 4901
    constants = struct.pack('<40i4i4i', *table, 2, 0, 0, 0, 7000, -1, -1, -1)
    data = bytes(256) + code + constants
    text = {'offset': 256, 'address': base, 'length': len(code), 'segment': b'__TEXT', 'name': b'__text'}
    mach = SimpleNamespace(data=data, architecture='x86_64' if mac else 'armv7', slice_offset=0,
        text=text, sections=[text, {'offset': 1280, 'address': const, 'length': len(constants), 'segment': b'__TEXT', 'name': b'__const'}])
    rows = [{'id': id, 'resource': 'resources/data/assets/main/3d/meshes/hangars/hangar_terran' + suffix + '.aem',
             'kind': 'mesh', 'registration_type': 4} for id, suffix in zip(ids, ('', '_add', '_alpha'))]
    return mach, rows, (256 + corrupt_getter, 256 + corrupt_join)


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class HangarTests(unittest.TestCase):
    def test_relocated_editions_recover_constants_not_hardcoded_game_values(self):
        for mac in (True, False):
            mach, rows, _ = fixture(mac)
            value = extract_hangars(mach, rows)
            self.assertTrue(value, mac)
            self.assertEqual(value['rows'][0], {'resource_ids': [4100, 4101, 4102, -1], 'extra_resource_ids': [7000, 7001]})
            self.assertEqual(value['rotation_y'], 1.25)
            self.assertEqual(value['station_overrides'], [{'station_id': 5, 'row': 8}, {'station_id': 4, 'row': 7}])
            self.assertEqual(value['provenance'][0], {'offset': 1280, 'bytes': 160})

    def test_wrong_getters_joins_extents_and_anchors_fail_closed(self):
        for mac in (True, False):
            for corruption in ('getter', 'join', 'truncated', 'anchor', 'extra_count', 'extra_range', 'duplicate_anchor'):
                mach, rows, sites = fixture(mac)
                data = bytearray(mach.data)
                if corruption in ('getter', 'join'):
                    data[sites[0 if corruption == 'getter' else 1]] ^= 1
                elif corruption == 'truncated':
                    # The table read must respect the declared const section.
                    mach.sections[-1]['length'] = 159
                elif corruption == 'anchor':
                    rows.pop()
                elif corruption == 'duplicate_anchor':
                    rows.append(dict(rows[0], id=6000))
                elif corruption == 'extra_count':
                    struct.pack_into('<i', data, 1440, 129)
                elif corruption == 'extra_range':
                    struct.pack_into('<i', data, 1456, 65534)
                mach.data = bytes(data)
                self.assertEqual(extract_hangars(mach, rows), {}, (mac, corruption))
