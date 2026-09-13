"""Synthetic scene caps and linked millisecond suppliers, never executed."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from test_ship_models import branch
from gof2_content.frame_clock import extract_frame_clock


def fixture(mac, relocation=0):
    base = (0x100002000 if mac else 0x2000) + relocation
    code = bytearray(2048)
    if mac:
        clamp = bytearray.fromhex('498b7d10e8000000003d780000007f12498b7d10e8000000004889c131c085c97822498b7d10e8000000004889c1b87800000081f9780000007f09498b7d10e80000000041894548')
        calls = (4, 20, 38, 63)
        helper = bytes.fromhex('554889e548897df8488b7df8488b87c0000000482b87c80000005dc3')
        for at in calls: struct.pack_into('<i', clamp, at + 1, 1200 - 300 - at - 5)
    else:
        clamp = bytearray.fromhex('782c08dcdbf808004ff0ff31b49100000000002810dbdbf808004ff0ff34b49400000000782801dd782006e0dbf80800b4940000000000e0002000ee900b')
        calls = (14, 32, 50)
        helper = bytes.fromhex('82b00190c16e026f436f806fc91a62eb000000900846009902b07047')
        for at in calls: clamp[at:at + 4] = branch(base + 300 + at, base + 1200)
    code[300:300 + len(clamp)] = clamp
    code[1200:1200 + len(helper)] = helper
    text = dict(offset=256, address=base, length=len(code), segment=b'__TEXT', name=b'__text')
    return SimpleNamespace(data=bytes(256) + code, text=text, sections=[text],
                           architecture='x86_64' if mac else 'armv7', slice_offset=4096)


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class FrameClockTests(unittest.TestCase):
    def test_both_relocated_clocks_and_alternate_cap(self):
        for mac in (True, False):
            for relocation in (0, 0x3400):
                m = fixture(mac, relocation)
                result = extract_frame_clock(m, {'supported': True})
                self.assertEqual(result['max_frame_milliseconds'], 120)
                self.assertEqual(result['time_unit'], 'milliseconds')
                self.assertEqual(result['provenance'], [{'offset': 4096 + 256 + 300, 'bytes': 72 if mac else 62},
                                                        {'offset': 4096 + 256 + 1200, 'bytes': 28}])
                self.assertEqual(extract_frame_clock(m, {}), {})

    def test_disagreement_bad_calls_and_invalid_suppliers(self):
        for mac in (True, False):
            for case in ('disagree', 'zero', 'call', 'helper', 'extent', 'duplicate'):
                m = fixture(mac); data = bytearray(m.data)
                if case == 'disagree': data[256 + 300 + (10 if mac else 0)] = 119
                elif case == 'zero':
                    for at in ((10, 47, 53) if mac else (0, 36, 40)):
                        data[256 + 300 + at] = 0
                elif case == 'call': data[256 + 300 + (5 if mac else 14)] ^= 1
                elif case == 'helper': data[256 + 1200] ^= 1
                elif case == 'extent': m.sections[0]['length'] = 1210
                elif case == 'duplicate':
                    count = 72 if mac else 62
                    data[256 + 1600:256 + 1600 + count] = data[256 + 300:256 + 300 + count]
                m.data = bytes(data)
                self.assertEqual(extract_frame_clock(m, {'supported': True}), {}, (mac, case))
