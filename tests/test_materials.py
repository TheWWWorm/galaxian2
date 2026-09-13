"""Synthetic constant declarations and adversarial linkage, no original content."""
import importlib.util
import json
import struct
import unittest

from test_bindings import executable, wide, PATH
from gof2_content.registrations import MachO, extract
from gof2_content.materials import extract_materials


def arm_wide(value, reg=1, top=False):
    first, second = struct.unpack('<2H', wide(value, top))
    return struct.pack('<2H', first, (second & ~0xf00) | (reg << 8))


def with_code(code, edition):
    data = bytearray(executable(edition))
    at = 32 + 72 + 40 if edition == 'mac-full-hd' else 28 + 56 + 36
    struct.pack_into('<Q' if edition == 'mac-full-hd' else '<I', data, at, len(code))
    assert len(code) <= 512
    data[512:512 + len(code)] = code
    return bytes(data)


def mac_material():
    return (bytes.fromhex('bf 30 00 00 00 e8 00 00 00 00 c7 40 10') + struct.pack('<I', 28)
            + bytes.fromhex('48 c7 40 18 00 00 00 00 c7 40 20') + struct.pack('<I', 0)
            + bytes.fromhex('c7 40 24') + struct.pack('<I', 0xc1200000)
            + bytes.fromhex('c7 40 28 00 00 00 00 c7 40 2c 00 00 00 00')
            + bytes.fromhex('48 c7 40 08 ff ff ff ff 48 c7 00 ff ff ff ff')
            + bytes.fromhex('66 c7 00') + struct.pack('<H', 71)
            + bytes.fromhex('66 c7 40 02') + struct.pack('<H', 72)
            + bytes.fromhex('66 c7 03') + struct.pack('<H', 99)
            + bytes.fromhex('c7 43 04 06 00 00 00 c7 43 08 ff ff ff ff 48 89 43 10'))


def ios_material():
    load = bytes.fromhex('d5 f8 40 20')
    return (bytes.fromhex('28 20 00 f0 00 e8 0b ad 1c 22 00 23 4f f0 ff 36 d5 f8 40 10 02 61 00 22')
            + arm_wide(0xc120, 2, True) + bytes.fromhex('43 61 83 61 c2 61')
            + arm_wide(71, 2) + arm_wide(72, 2, True)
            + bytes.fromhex('03 62 43 62') + arm_wide(99, 3)
            + bytes.fromhex('c6 60 86 60 46 60 06 60 02 60') + load
            + bytes.fromhex('13 80 06 23') + load + bytes.fromhex('53 60')
            + load + bytes.fromhex('96 60') + load + bytes.fromhex('d0 60'))


def ios_mesh(changed_slot=False):
    code = bytes.fromhex('08 20 00 f0 00 e8 6e 46 70 60 70 68') + arm_wide(99)
    code += bytes.fromhex('81 80 71 68 00 22 8a 71')
    displacement = 0x3000 - (0x2000 + len(code) + 12)
    code += arm_wide(displacement, 0) + arm_wide(0, 0, True) + bytes.fromhex('78 44')
    code += bytes.fromhex('00 f0 00 f8 01 30 00 f0 00 e8 6e 46')
    prefix_length = len(code)
    original = executable('ios-hd')
    length = struct.unpack_from('<I', original, 28 + 56 + 36)[0]
    tail = bytearray(original[512:512 + length])
    displacement = 0x3000 - 0x2000 - prefix_length - 8 - 12
    tail[8:16] = wide(displacement) + wide(0, True)
    if changed_slot:
        tail[4:8] = bytes.fromhex('d6 f8 08 20')
        # Keep registration footer coherent so only metadata aliasing fails.
        at = tail.rfind(bytes.fromhex('d6 f8 04 20'))
        tail[at:at + 4] = bytes.fromhex('d6 f8 08 20')
    return with_code(code + tail, 'ios-hd')


class MaterialTests(unittest.TestCase):
    def test_mac_mesh_metadata_repeats_the_same_resource_path(self):
        prefix = (bytes.fromhex('66 41 c7 44 24 08') + struct.pack('<H', 99)
                  + bytes.fromhex('41 c6 44 24 0a 00 48 8d 3d') + struct.pack('<i', 0x1000 - 21)
                  + bytes.fromhex('e8 00 00 00 00 89 c3 ff c3 48 89 df e8 00 00 00 00'))
        original = executable()
        length = struct.unpack_from('<Q', original, 32 + 72 + 40)[0]
        tail = bytearray(original[512:512 + length])
        struct.pack_into('<i', tail, 7, 0x1000 - len(prefix) - 11)
        row = extract(with_code(prefix + tail, 'mac-full-hd'), 'mac-full-hd')['registrations'][0]
        self.assertEqual((row['material_id'], row['mesh_flags']), (99, 0))
        bad = bytearray(prefix)
        bad[17] += 1
        row = extract(with_code(bad + tail, 'mac-full-hd'), 'mac-full-hd')['registrations'][0]
        self.assertNotIn('material_id', row)

    def test_mac_complete_descriptor_and_payload_identity(self):
        code = mac_material()
        rows = extract_materials(MachO(with_code(code, 'mac-full-hd'), 'mac-full-hd'))
        self.assertEqual(rows[0]['texture_ids'], [71, 72] + [65535] * 6)
        self.assertEqual(rows[0]['parameter_bits'], [0, 0xc1200000, 0, 0])
        for changed in (code[:-1], code[:-1] + b'\x18', code.replace(b'\xc7\x43\x04\x06', b'\xc7\x43\x04\x07')):
            self.assertEqual(extract_materials(MachO(with_code(changed, 'mac-full-hd'), 'mac-full-hd')), [])

    @unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
    def test_cross_architecture_constant_data_and_rejection(self):
        mac = extract_materials(MachO(with_code(mac_material(), 'mac-full-hd'), 'mac-full-hd'))[0]
        code = ios_material()
        ios = extract_materials(MachO(with_code(code, 'ios-hd'), 'ios-hd'))[0]
        self.assertEqual(mac, ios)
        json.dumps(ios)  # No instruction bytes, pointers or decoder objects escape.
        alternate = code.replace(bytes.fromhex('4f f0 ff 36'), bytes.fromhex('4f f0 ff 34'))
        for old, new in [('c660', 'c460'), ('8660', '8460'), ('4660', '4460'), ('0660', '0460'), ('9660', '9460')]:
            alternate = alternate.replace(bytes.fromhex(old), bytes.fromhex(new))
        self.assertEqual(extract_materials(MachO(with_code(alternate, 'ios-hd'), 'ios-hd'))[0], ios)
        for changed in (code[:-2], code.replace(b'\x03\x62', b'\x00\xbf'),
                        code.replace(b'\x03\x62', b'\x00\xe0'),
                        code[:-2] + bytes.fromhex('d1 60'),
                        code.replace(b'\x43\x61', b'\x42\x61')):
            self.assertEqual(extract_materials(MachO(with_code(changed, 'ios-hd'), 'ios-hd')), [])

    @unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
    def test_mesh_metadata_requires_same_allocated_payload(self):
        row = extract(ios_mesh(), 'ios-hd')['registrations'][0]
        self.assertEqual((row['material_id'], row['mesh_flags']), (99, 0))
        self.assertEqual(row['resource'], 'resources/' + PATH)
        broken = extract(ios_mesh(True), 'ios-hd')['registrations'][0]
        self.assertNotIn('material_id', broken)


if __name__ == '__main__':
    unittest.main()
