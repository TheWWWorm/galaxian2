"""Bounded, declarative readers. No executable data or gameplay interpretation."""
import struct


class ContentError(ValueError):
    pass


MAX_LANGUAGE = 2 * 1024 * 1024


def language(data: bytes) -> list[str]:
    # Length-prefix layout also used by the Apache-2.0 GoF1 formats.gd reader.
    if not data or len(data) > MAX_LANGUAGE:
        raise ContentError('Empty or oversized language file')
    result, cursor = [], 0
    while cursor < len(data):
        if cursor + 2 > len(data):
            raise ContentError('Truncated language record')
        length = int.from_bytes(data[cursor:cursor + 2], 'big')
        cursor += 2
        if cursor + length > len(data):
            raise ContentError('Truncated language string')
        try:
            result.append(data[cursor:cursor + length].decode('utf-8', errors='strict'))
        except UnicodeDecodeError as error:
            raise ContentError('Invalid UTF-8 language string') from error
        cursor += length
        if len(result) > 10000:
            raise ContentError('Too many language records')
    return result


def envelope(name: str, header: bytes, size: int) -> dict:
    """Check known envelopes only; never claim geometry/texture/audio decoding."""
    executable_magic = {b'\xce\xfa\xed\xfe', b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xce',
                        b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\x7fELF'}
    if header[:4] in executable_magic or header[:2] == b'MZ':
        raise ContentError(f'Executable bytes are not importable resources: {name}')
    if size == 0:
        raise ContentError(f'Empty resource: {name}')
    if name.endswith('.aem'):
        if len(header) < 10 or header[:9] not in [f'V{v}AEMesh\0'.encode() for v in (2, 3, 4, 5)]:
            raise ContentError(f'Unsupported AEM envelope: {name}')
        return {'kind': 'mesh', 'version': int(chr(header[1])), 'validation': 'header_only'}
    if name.endswith('.aei'):
        if len(header) < 15 or header[:8] != b'AEimage\0':
            raise ContentError(f'Unsupported AEI envelope: {name}')
        fmt, width, height, regions = struct.unpack_from('<BHHH', header, 8)
        if fmt not in (1, 3, 13, 16, 18, 32, 34, 36, 38, 129, 166):
            raise ContentError(f'Unsupported AEI format {fmt}: {name}')
        if not (0 < width <= 8192 and 0 < height <= 8192):
            raise ContentError(f'Invalid AEI dimensions: {name}')
        return dict(kind='texture', format=fmt, width=width, height=height,
                    regions=regions, validation='header_only')
    return {'kind': {'.bin': 'catalogue', '.fsb': 'audio_bank', '.fev': 'audio_events',
                     '.lang': 'localization'}.get('.' + name.rsplit('.', 1)[-1], 'unknown'),
            'validation': 'opaque'}
