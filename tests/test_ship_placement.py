"""Synthetic position tables with relocated indexed access and malformed variants."""
import importlib.util
import struct
import unittest
from test_hangars import fixture as hangar_fixture
from test_materials import arm_wide
from test_ship_models import branch
from gof2_content.hangars import extract_hangars
from gof2_content.ship_placement import extract_ship_placement


def fixture(mac):
    mach, rows, _ = hangar_fixture(mac)
    count = 61 if mac else 64
    start = 400 if mac else 300
    base = mach.text['address']
    table = mach.sections[-1]['address'] + mach.sections[-1]['length']
    data = bytearray(mach.data)
    values = [-35, 712] + list(range(count - 2))
    data.extend(struct.pack('<' + str(count) + 'i', *values))
    mach.sections[-1]['length'] += count * 4
    code = bytearray()
    def call(target=48):
        at = start + len(code)
        code.extend(b'\xe8' + struct.pack('<i', target - at - 5) if mac else branch(base + at, base + target))
    call()
    if mac:
        code += bytes.fromhex('89c3498b3e'); call()
        code += bytes.fromhex('4889c7'); call()
        code += bytes.fromhex('4531ed4183bf14010000170f95c1c7042400000000440fb6c94c89ff89c631d289d94531c0'); call()
        code += bytes.fromhex('488d0d')
        code += struct.pack('<i', table - base - start - len(code) - 4)
        code += bytes.fromhex('4863d3f30f2a0c91498b8f78010000488b4908488901498b8778010000488b4008488b38488b070f57c00f57d2ff9090000000')
        getter = bytes.fromhex('554889e58b075dc3')
    else:
        code += bytes.fromhex('824620682896'); call()
        code += bytes.fromhex('2896'); call()
        code += bytes.fromhex('0146d5f8c0002896002217284ff0000018bf0120cdf80080019028465346cdf80880'); call()
        disp = table - base - start - len(code) - 18
        code += arm_wide(disp & 65535, 2) + bytes.fromhex('0023') + arm_wide(disp >> 16, 2, True)
        code += bytes.fromhex('d5f8f8107a4402eb8a02496892ed000abbff00060860d5f8f800406810ee102a006801688c6c00212896a047')
        getter = bytes.fromhex('00687047')
    data[256 + start:256 + start + len(code)] = code
    data[256 + 48:256 + 48 + len(getter)] = getter
    mach.data = bytes(data)
    return mach, extract_hangars(mach, rows), values, start


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class PlacementTests(unittest.TestCase):
    def test_profiles_read_full_signed_positions_with_provenance(self):
        for mac in (True, False):
            mach, hangars, values, start = fixture(mac)
            self.assertTrue(hangars)
            value = extract_ship_placement(mach, hangars, len(values))
            self.assertEqual(value['y_positions'], values)
            self.assertEqual(value['provenance'][0], {'offset': 1472, 'bytes': len(values) * 4})
            self.assertEqual(value['provenance'][1], {'offset': 256 + start, 'bytes': 123 if mac else 112})

    def test_invalid_index_getter_bounds_position_and_missing_context_fail(self):
        for mac in (True, False):
            for corruption in ('getter', 'reader', 'table', 'position', 'context'):
                mach, hangars, values, start = fixture(mac)
                data = bytearray(mach.data)
                if corruption == 'getter': data[304] ^= 1
                elif corruption == 'reader': data[256 + start + (78 if mac else 92)] ^= 1
                elif corruption == 'table': mach.sections[-1]['length'] -= 1
                elif corruption == 'position': struct.pack_into('<i', data, 1472, 1000001)
                elif corruption == 'context': hangars = {}
                mach.data = bytes(data)
                self.assertEqual(extract_ship_placement(mach, hangars, len(values)), {}, (mac, corruption))
