"""Bounded AEI texture/atlas parsing and optional CPU decompression.

The parser preserves stored mip levels, raw cube strips and glyph metadata.
Pixel conversion is an import-time dependency, never original game code.
"""
from dataclasses import dataclass
import struct

from .formats import ContentError

MAX_PIXELS = 32 * 1024 * 1024
MAX_BYTES = 192 * 1024 * 1024
FORMATS = {1: 'rgba8', 3: 'rgba8', 13: 'pvrtc2', 16: 'pvrtc4', 18: 'pvrtc4',
           32: 'bc1', 34: 'bc1', 36: 'bc3', 38: 'bc3', 129: 'rgba8', 166: 'rgba8'}


@dataclass(frozen=True)
class Level:
    width: int
    height: int
    offset: int
    length: int


class Texture:
    def __init__(self, data):
        if not 17 <= len(data) <= MAX_BYTES or data[:8] != b'AEimage\0':
            raise ContentError('Invalid or oversized AEI envelope')
        self.data = data
        self.format, self.width, self.height, regions = struct.unpack_from('<BHHH', data, 8)
        if self.format not in FORMATS:
            raise ContentError(f'Unsupported AEI format {self.format}')
        if not (0 < self.width <= 8192 and 0 < self.height <= 8192 and self.width * self.height <= MAX_PIXELS):
            raise ContentError('Invalid or oversized AEI dimensions')
        self.codec = FORMATS[self.format]
        self.cube = bool(self.format & 128)
        self.mipmap_flag = bool(self.format & 2)
        if self.cube and self.height != self.width * 6:
            raise ContentError('Unsupported cubemap arrangement; expected six square faces in a vertical strip')
        self.regions, self.fonts = [], []
        pos = 15
        for _ in range(regions):
            rect = self.unpack('4H', pos)
            pos += 8
            self.check_rect(rect, allow_empty=True)
            self.regions.append(rect)
        if self.codec == 'rgba8':
            # Both 0x81 and observed Mac 0xa6 cubes store one raw RGBA strip.
            length = self.width * self.height * 4
        else:
            length = self.unpack('I', pos)[0]
            pos += 4
        self.require(pos, length)
        end = pos + length
        self.levels = []
        width, height = self.width, self.height
        while True:
            size = level_size(self.codec, width, height)
            if pos + size > end:
                raise ContentError('Truncated AEI mip level')
            self.levels.append(Level(width, height, pos, size))
            pos += size
            if pos == end:
                break
            if self.codec == 'rgba8' or not self.mipmap_flag or (width == 1 and height == 1):
                raise ContentError('Unexpected AEI pixel payload extent')
            width, height = max(1, width // 2), max(1, height // 2)
        if self.codec != 'rgba8' and self.mipmap_flag and (width != 1 or height != 1):
            raise ContentError('Incomplete AEI mip chain')
        font_count = self.unpack('H', pos)[0]
        pos += 2
        if font_count > 32:
            raise ContentError('Too many AEI fonts')
        for _ in range(font_count):
            count = self.unpack('H', pos)[0]
            pos += 2
            if not 1 <= count <= 65535:
                raise ContentError('Invalid AEI glyph count')
            self.require(pos, count * 10)
            codes = self.unpack('H' * count, pos)
            pos += count * 2
            glyphs = {}
            for code in codes:
                rect = self.unpack('4H', pos)
                pos += 8
                self.check_rect(rect, allow_empty=False)
                if code in glyphs:
                    raise ContentError('Duplicate AEI glyph code')
                glyphs[code] = rect
            self.fonts.append(glyphs)
        if pos != len(data):
            raise ContentError('Unrecognized AEI trailer')

    def require(self, offset, length):
        if offset < 0 or length < 0 or offset + length > len(self.data):
            raise ContentError('Truncated AEI data')

    def unpack(self, fmt, offset):
        self.require(offset, struct.calcsize('<' + fmt))
        return struct.unpack_from('<' + fmt, self.data, offset)

    def check_rect(self, rect, allow_empty):
        x, y, w, h = rect
        # Cube pixels use a vertical strip, while their retained atlas rectangles
        # refer to the original four-by-three face cross.
        width = self.width * 4 if self.cube else self.width
        height = self.width * 3 if self.cube else self.height
        if x + w > width or y + h > height or (not allow_empty and (w == 0 or h == 0)):
            raise ContentError('AEI atlas region is outside image bounds')

    def pixels(self, level=0):
        row = self.levels[level]
        payload = self.data[row.offset:row.offset + row.length]
        if self.codec == 'rgba8':
            return payload
        try:
            import texture2ddecoder as decoder
            from importlib.metadata import version
        except ImportError as error:
            raise ContentError('Install texture2ddecoder==1.0.6 to decode PVRTC/BC textures') from error
        if version('texture2ddecoder') != '1.0.6':
            raise ContentError('This visual schema requires texture2ddecoder==1.0.6')
        if self.codec.startswith('pvrtc'):
            # PVRTC's minimum stored surface is larger than the last logical mips.
            block_w, block_h = (16, 8) if self.codec == 'pvrtc2' else (8, 8)
            decode_w, decode_h = max(block_w, row.width), max(block_h, row.height)
            pixels = decoder.decode_pvrtc(payload, decode_w, decode_h, self.codec == 'pvrtc2')
        else:
            decode_w, decode_h = row.width, row.height
            decode = decoder.decode_bc1 if self.codec == 'bc1' else decoder.decode_bc3
            pixels = decode(payload, decode_w, decode_h)
        if len(pixels) != decode_w * decode_h * 4:
            raise ContentError('Decoder returned an unexpected pixel count')
        # Dependency returns BGRA; normalized pixels are RGBA on every platform.
        rgba = bytearray(row.width * row.height * 4)
        for y in range(row.height):
            src = pixels[y * decode_w * 4:(y * decode_w + row.width) * 4]
            dst = y * row.width * 4
            rgba[dst:dst + row.width * 4:4] = src[2::4]
            rgba[dst + 1:dst + row.width * 4:4] = src[1::4]
            rgba[dst + 2:dst + row.width * 4:4] = src[0::4]
            rgba[dst + 3:dst + row.width * 4:4] = src[3::4]
        return bytes(rgba)

    def metadata(self):
        return {'format': self.format, 'codec': self.codec, 'width': self.width, 'height': self.height,
                'cube_strip': self.cube, 'mipmap_flag': self.mipmap_flag,
                'stored_levels': [{'width': r.width, 'height': r.height, 'bytes': r.length} for r in self.levels],
                'regions': self.regions, 'fonts': self.fonts,
                'region_space': 'cube_cross' if self.cube else 'image',
                'cube_orientation': 'unverified' if self.cube else None}


def level_size(codec, width, height):
    if codec == 'rgba8':
        return width * height * 4
    if codec.startswith('pvrtc'):
        if width & (width - 1) or height & (height - 1):
            raise ContentError('Unsupported non-power-of-two PVRTC surface')
        if codec == 'pvrtc2':
            return max(width, 16) * max(height, 8) // 4
        return max(width, 8) * max(height, 8) // 2
    return max(1, (width + 3) // 4) * max(1, (height + 3) // 4) * (8 if codec == 'bc1' else 16)
