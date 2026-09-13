"""Synthetic source quality pairs; no original textures or executable data."""
import copy
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

from test_aei import raw_texture, compressed
from test_materials import with_code
from gof2_content.aei import Texture
from gof2_content.formats import ContentError
from gof2_content.registrations import extract
from gof2_content.texture_variants import compatible, verify_variants

HIGH = 'resources/data/assets/main/3d/textures/high/dx5/hangars/example.aei'
LOW = HIGH.replace('/high/', '/low/')


class VariantTests(unittest.TestCase):
    def test_quality_requires_matching_uv_layout_and_scale(self):
        low = Texture(raw_texture(width=2, height=2))
        self.assertTrue(compatible(Texture(raw_texture(width=4, height=4)), low))
        self.assertTrue(compatible(Texture(raw_texture(fmt=3, width=4, height=4)), low))
        self.assertTrue(compatible(Texture(compressed(34, 8, 8, bytes(56))), Texture(compressed(36, 4, 4, bytes(16)))))
        for high in [Texture(raw_texture(width=4, height=2)), Texture(raw_texture(width=3, height=3)),
                     Texture(raw_texture(width=4, height=4, regions=[(1, 0, 3, 4)])),
                     Texture(raw_texture(fmt=129, width=4, height=24, regions=[]))]:
            self.assertFalse(compatible(high, low))

    def test_verified_pair_preserves_hashes_and_rejects_unrelated_alternatives(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            manifest = {'profile': {'edition': 'mac-full-hd'}, 'files': {}}
            rows = []
            for path, size in [(HIGH, 4), (LOW, 2)]:
                data = raw_texture(width=size, height=size)
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                manifest['files'][path] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                rows.append({'id': 17, 'resource': path, 'kind': 'texture', 'registration_type': 2, 'texture_parameter_bits': 0})
            result = verify_variants(rows, root, manifest)
            self.assertEqual(len(result), 1)
            self.assertEqual(result[0]['high_sha256'], manifest['files'][HIGH]['sha256'])
            self.assertEqual(result[0]['low_size'], [2, 2])
            for key, value in [('kind', 'mesh'), ('registration_type', 4), ('texture_parameter_bits', 1),
                               ('resource', LOW.replace('example', 'different'))]:
                changed = copy.deepcopy(rows)
                changed[1][key] = value
                self.assertEqual(verify_variants(changed, root, manifest), [])
            self.assertEqual(verify_variants(rows + [dict(rows[0], resource=HIGH.replace('example', 'third'))], root, manifest), [])
            broken = bytearray((root / HIGH).read_bytes())
            broken[-3] ^= 1
            (root / HIGH).write_bytes(broken)
            with self.assertRaisesRegex(ContentError, 'checksum'):
                verify_variants(rows, root, manifest)

    def test_second_mac_initializer_has_exact_pointer_and_path_linkage(self):
        path = 'data/variant.aei'
        code = (bytes.fromhex('48 8d 3d') + struct.pack('<i', 0x1000 - 7)
                + bytes.fromhex('e8 00 00 00 00 89 c3 ff c3 48 89 df e8 00 00 00 00 49 89 07 48 8d 35')
                + struct.pack('<i', 0x1000 - 34)
                + bytes.fromhex('48 89 c7 48 89 da e8 00 00 00 00 41 c7 47 08 00 00 00 00 66 41 c7 06')
                + struct.pack('<H', 17)
                + bytes.fromhex('41 c7 46 04 02 00 00 00 41 c7 46 08 ff ff ff ff 4d 89 7e 10'))
        def source(value):
            data = bytearray(with_code(value, 'mac-full-hd'))
            struct.pack_into('<Q', data, 32 + 72 + 80 + 40, len(path) + 1)
            data[1024:] = path.encode() + b'\0'
            return bytes(data)
        row = extract(source(code), 'mac-full-hd')['registrations'][0]
        self.assertEqual((row['id'], row['texture_parameter_bits']), (17, 0))
        for changed in [code[:-1], code[:-1] + b'\x18', code[:3] + struct.pack('<i', 0x1000 - 6) + code[7:]]:
            with self.assertRaisesRegex(ContentError, 'No supported'):
                extract(source(changed), 'mac-full-hd')


if __name__ == '__main__':
    unittest.main()
