"""Synthetic format and conversion tests; no original assets."""
import importlib.util
import struct
from pathlib import Path
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from gof2_content.aei import Texture
from gof2_content.formats import ContentError
from gof2_content.visuals import convert_texture, prepare
from gof2_content import install
from test_content import archive, fixture


def raw_texture(fmt=1, width=2, height=2, regions=None, pixels=None, trailer=b'\0\0'):
    regions = [(0, 0, width, height)] if regions is None else regions
    pixels = bytes([255, 0, 64, 128]) * width * height if pixels is None else pixels
    return (b'AEimage\0' + struct.pack('<B3H', fmt, width, height, len(regions))
            + b''.join(struct.pack('<4H', *r) for r in regions) + pixels + trailer)


def compressed(fmt, width, height, data):
    return (b'AEimage\0' + struct.pack('<B3H', fmt, width, height, 0)
            + struct.pack('<I', len(data)) + data + b'\0\0')


class TextureTests(unittest.TestCase):
    def test_raw_pixels_and_font_provenance(self):
        trailer = struct.pack('<3H4H', 1, 1, 65, 0, 0, 1, 2)
        texture = Texture(raw_texture(trailer=trailer))
        self.assertEqual(texture.pixels(), bytes([255, 0, 64, 128]) * 4)
        self.assertEqual(texture.fonts, [{65: (0, 0, 1, 2)}])
        self.assertEqual(texture.regions, [(0, 0, 2, 2)])
        self.assertEqual(len(texture.levels), 1)

    def test_native_envelope_roundtrip_and_base_only_raw_mip_flag(self):
        source = Texture(raw_texture(fmt=3))
        native = convert_texture(source)
        self.assertEqual(struct.unpack('<4s5I', native[:24]), (b'G2TX', 1, 2, 2, 1, 16))
        self.assertEqual(zlib.decompress(native[24:]), source.pixels())
        self.assertTrue(source.mipmap_flag)
        self.assertEqual(len(source.levels), 1)

    def test_cube_strip_and_cross_regions(self):
        for fmt in (129, 166):
            texture = Texture(raw_texture(fmt, 2, 12, [(0, 0, 8, 6)]))
            self.assertTrue(texture.cube)
            self.assertEqual(texture.metadata()['region_space'], 'cube_cross')
            self.assertEqual(len(texture.pixels()), 96)
        with self.assertRaisesRegex(ContentError, 'cubemap'):
            Texture(raw_texture(129))

    def test_all_truncations_and_extra_bytes(self):
        data = raw_texture()
        for end in range(len(data)):
            with self.subTest(end=end), self.assertRaises(ContentError):
                Texture(data[:end])
        with self.assertRaisesRegex(ContentError, 'trailer'):
            Texture(data + b'\0')

    def test_atlas_and_dimension_bounds(self):
        with self.assertRaisesRegex(ContentError, 'bounds'):
            Texture(raw_texture(regions=[(1, 1, 2, 2)]))
        data = bytearray(raw_texture())
        struct.pack_into('<H', data, 9, 65535)
        with self.assertRaisesRegex(ContentError, 'dimensions'):
            Texture(data)

    def test_stored_mip_extent_validation(self):
        # BC1: 8x8=32 bytes, then 4x4, 2x2, 1x1=8 bytes each.
        texture = Texture(compressed(34, 8, 8, bytes(56)))
        self.assertEqual([(m.width, m.height) for m in texture.levels], [(8, 8), (4, 4), (2, 2), (1, 1)])
        for size in [0, 31, 32, 40, 48, 55, 57]:
            with self.subTest(size=size), self.assertRaises(ContentError):
                Texture(compressed(34, 8, 8, bytes(size)))
        # PVRTC mip tail maintains minimum 8x8 blocks down to logical 1x1.
        self.assertEqual(len(Texture(compressed(18, 8, 8, bytes(128))).levels), 4)

    @unittest.skipUnless(importlib.util.find_spec('texture2ddecoder'), 'Optional CPU decoder not installed')
    def test_bc_red_channel_alpha_and_mips(self):
        red = struct.pack('<HHI', 0xf800, 0, 0)
        for fmt, block in [(32, red), (36, b'\xff\xff' + bytes(6) + red)]:
            texture = Texture(compressed(fmt, 4, 4, block))
            self.assertEqual(texture.pixels(), bytes([255, 0, 0, 255]) * 16)
        texture = Texture(compressed(34, 4, 4, red * 3))
        self.assertEqual(zlib.decompress(convert_texture(texture)[24:]), bytes([255, 0, 0, 255]) * 21)

    @unittest.skipUnless(importlib.util.find_spec('texture2ddecoder'), 'Optional CPU decoder not installed')
    def test_pvrtc_minimum_surface_mip_dimensions(self):
        texture = Texture(compressed(18, 8, 8, b'\xff' * 128))
        for i, expected in enumerate([256, 64, 16, 4]):
            self.assertEqual(len(texture.pixels(i)), expected)

    def test_preparation_provenance_cancellation_and_base_immutability(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_files = fixture()
            source_files['data/textures/ui.aei'] = raw_texture()
            base, manifest = install(archive(root / 'input.zip', files=source_files), root / 'base')
            before = (base / 'manifest.json').read_bytes()
            resource = 'resources/data/textures/ui.aei'
            destination, visual = prepare(base, root / 'visuals', [resource])
            self.assertEqual(visual['recipe']['base_content_id'], manifest['content_id'])
            self.assertEqual(visual['textures'][resource]['source_sha256'], manifest['files'][resource]['sha256'])
            self.assertTrue((destination / 'visuals.json').is_file())
            def cancel(*_):
                raise InterruptedError('cancel')
            with self.assertRaises(InterruptedError):
                prepare(base, root / 'cancelled', [resource], cancel)
            self.assertEqual(list((root / 'cancelled').iterdir()), [])
            self.assertEqual((base / 'manifest.json').read_bytes(), before)
            with self.assertRaises(ContentError):
                prepare(base, base / 'visuals', [resource])
            with self.assertRaises(ContentError):
                prepare(base, root / 'other', ['resources/absent.aei'])


if __name__ == '__main__':
    unittest.main()
