"""Synthetic manual rotation declarations and independently relocated constants."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from test_ship_models import branch
from gof2_content.steering import extract_manual_rotation


def fixture(mac, relocation=0):
    base = (0x100002000 if mac else 0x2000) + relocation
    code = bytearray(2048)
    constants = struct.pack('<3f', 1 / 1024, 6.0, 0.025)
    address = base + (8192 if mac else 1400)
    if mac:
        loads = b''
        for i, (opcode, index) in enumerate([('f30f1015', 2), ('f30f101d', 1), ('f30f100d', 0)]):
            loads += bytes.fromhex(opcode) + struct.pack('<i', address + index * 4 - base - 300 - i * 8 - 8)
        code[300:324] = loads
        consumer = bytes.fromhex('f3410f10842414030000f30f59c1f30f59c3f30f59c4f30f59c2f3410f598c2418030000f30f59cbf30f59ccf30f59caf3410f10104c89f6e8') + struct.pack('<i', 1024 - 512 - 61)
        helper = bytes.fromhex('554889e54883ec504889f848ba3c00000000000000488975f8f30f1145f4f30f114df0f30f1155ecf30f5a45f4')
    else:
        def load(offset, index):
            delta = address + index * 4 - ((base + 512 + offset + 4) & ~3)
            return bytes([0x9f, 0xed, delta // 4, 0x0a])
        consumer = (load(0, 0) + bytes.fromhex('94ed9d1a94ed9e2a40f2000041ff104dc0f2000042ff102d')
                    + load(28, 1) + bytes.fromhex('784444ff900d006842ff902d') + load(44, 2)
                    + bytes.fromhex('48ff300d48ff322d00ff901d02ff900d11ee102a10ee103a90ed000a28a88ded000a20ef1001')
                    + branch(base + 512 + 86, base + 1024))
        helper = bytes.fromhex('80b56f468eb043ec103bb0ee402a42ec102bb0ee404a97ed026a3c22')
        code[1400:1412] = constants
    code[512:512 + len(consumer)] = consumer
    code[1024:1024 + len(helper)] = helper
    text = dict(offset=256, address=base, length=2048, segment=b'__TEXT', name=b'__text')
    sections = [text]
    if mac: sections.append(dict(offset=2304, address=address, length=12, segment=b'__TEXT', name=b'__literal4'))
    return SimpleNamespace(data=bytes(256) + code + (constants if mac else b''), text=text,
                           sections=sections, architecture='x86_64' if mac else 'armv7', slice_offset=4096)


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class SteeringTests(unittest.TestCase):
    def test_constants_relocation_and_profile_layout(self):
        for mac in (True, False):
            for relocation in (0, 0x3400):
                m = fixture(mac, relocation)
                result = extract_manual_rotation(m, {'available': True})
                self.assertEqual(result['angle_unit_scale'], 1 / 1024)
                self.assertEqual(result['radians_per_turn'], 6.0)
                self.assertAlmostEqual(result['time_scale'], 0.025)
                self.assertEqual(result['rotation_order'], 'local_x_y')
                self.assertEqual([p['bytes'] for p in result['provenance']],
                                 [24, 61, 4, 4, 4, 45] if mac else [90, 4, 4, 4, 28])
                self.assertEqual(result['provenance'][-1]['offset'], 4096 + 256 + 1024)
                self.assertEqual(extract_manual_rotation(m, {}), {})

    def test_invalid_constants_and_broken_links_remain_unsupported(self):
        for mac in (True, False):
            for corruption in ('duplicate', 'consumer', 'helper', 'target', 'zero', 'nan', 'negative', 'range', 'extent', 'load'):
                m = fixture(mac); data = bytearray(m.data)
                if corruption == 'duplicate':
                    count = 61 if mac else 90
                    data[256 + 1600:256 + 1600 + count] = data[256 + 512:256 + 512 + count]
                elif corruption == 'extent': m.sections[-1]['length'] -= (1 if mac else 650)
                elif corruption in ('zero', 'nan', 'negative', 'range'):
                    value = {'zero': 0, 'nan': float('nan'), 'negative': -1, 'range': 11}[corruption]
                    at = 2304 if mac else 256 + 1400
                    struct.pack_into('<f', data, at + 4, value)
                else:
                    at = {'consumer': 512 + (0 if mac else 4), 'helper': 1024,
                          'target': 512 + (57 if mac else 87), 'load': 300 if mac else 512}[corruption]
                    data[256 + at] ^= 1
                m.data = bytes(data)
                self.assertEqual(extract_manual_rotation(m, {'available': True}), {}, (mac, corruption))
