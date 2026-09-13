"""Synthetic FEV fixtures only; no original sounds or authored events."""
import struct
import unittest
from gof2_content.fev import read
from gof2_content.formats import ContentError


def u(*values):
    return struct.pack('<' + 'I' * len(values), *values)


def string(value):
    raw = value.encode() + b'\0'
    return u(len(raw)) + raw


def chunk(tag, payload):
    return tag + u(len(payload)) + payload + (b'\0' if len(payload) % 2 else b'')


def fixture(extra_composition=b''):
    strings = ['', 'group', 'tone', '/sample']
    pool = b''
    offsets = []
    for value in strings:
        offsets.append(len(pool))
        pool += value.encode() + b'\0'
    header = bytearray(144)
    struct.pack_into('<f', header, 0, 0.5)
    struct.pack_into('<I', header, 28, 0x180008)
    struct.pack_into('<I', header, 120, 800)
    sound = struct.pack('<HffIIiIffffffII', 0, 0, 1, 0, 1, -1, 0, 0, 0, 0, 1, 0, 0, 4, 4)
    event = u(16, 2) + bytes(16) + header + u(1) + sound + u(1) + string('sfx')
    setting = struct.pack('<IIIIfIffffIfffIffHHH', 8, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    legacy = (u(0, 0) + string('Synthetic') + u(1, 1) + u(0, 0) + bytes(8) + u(0) + string('FMOD_GOF2_TEST')
              + string('master') + struct.pack('<ffIII', 1, 0, 0, 0, 0)
              + u(1) + u(1, 0, 0, 1) + event + u(1) + setting
              + u(1, 3, 0, 1, 0, 100) + string('sample.wav') + u(0, 0, 100)
              + u(0) + u(8 + len(extra_composition)) + b'comp' + extra_composition)
    project = b'PROJ' + chunk(b'OBCT', b'') + chunk(b'PROP', b'') + chunk(b'LGCY', legacy)
    project += chunk(b'EPRP', u(0)) + chunk(b'STRR', u(len(strings)) + u(*offsets) + pool)
    project += chunk(b'LANG', u(1) + string('english') + u(0))
    body = b'FEV ' + chunk(b'FMT ', u(0x450000)) + chunk(b'LIST', project)
    return b'RIFF' + u(len(body)) + body


class FevTests(unittest.TestCase):
    def test_event_reference_and_stop_time(self):
        result = read(fixture())
        event = result['events'][0]
        self.assertEqual(event['path'], '/group/tone')
        self.assertEqual(event['properties']['fade_out_ms'], 800)
        self.assertEqual(event['properties']['volume'], 0.5)
        self.assertEqual(result['banks'][0]['variants'][0]['resource'], 'resources/FMOD_GOF2_TEST.fsb')
        self.assertEqual(result['sound_definitions'][event['sound']['sound_def']]['entries'][0]['index'], 0)
        self.assertEqual(result['sound_settings'][0]['volume_random'], 1)
        self.assertEqual(result['schema'], 2)
        self.assertEqual(result['sound_settings'][0]['maximum_polyphony'], 1)
        self.assertEqual(result['sound_settings'][0]['volume'], 1)

    def test_spawn_times_are_integer_milliseconds(self):
        data = bytearray(fixture())
        record = struct.pack('<IIIIfIffffIfffIffHHH', 8, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        offset = data.index(record)
        struct.pack_into('<II', data, offset + 4, 1000, 1500)
        setting = read(data)['sound_settings'][0]
        self.assertEqual((setting['spawn_min_ms'], setting['spawn_max_ms']), (1000, 1500))

    def test_truncation_is_a_content_error(self):
        data = fixture()
        for position in (0, 12, 59, len(data) - 1):
            with self.subTest(position=position), self.assertRaises(ContentError):
                read(data[:position])

    def test_future_version_rejected(self):
        data = bytearray(fixture()); struct.pack_into('<I', data, 20, 0x460000)
        with self.assertRaisesRegex(ContentError, 'version'):
            read(data)

    def test_nonfinite_event_is_not_serialized(self):
        data = bytearray(fixture()); offset = read(data)['events'][0]['source_offset']
        struct.pack_into('<f', data, offset + 24, float('nan'))
        with self.assertRaisesRegex(ContentError, 'Non-finite'):
            read(data)

    def test_invalid_sound_reference_rejected(self):
        data = bytearray(fixture()); offset = read(data)['events'][0]['sound']['source_offset']
        struct.pack_into('<H', data, offset, 1)
        with self.assertRaisesRegex(ContentError, 'sound definition reference'):
            read(data)

    def test_string_offset_and_allocation_budget(self):
        for value in (0xffffffff, 20001):
            data = bytearray(fixture()); offset = data.index(b'STRR') + 8
            struct.pack_into('<I', data, offset if value == 20001 else offset + 4, value)
            with self.assertRaises(ContentError):
                read(data)

    def test_nonempty_music_composition_not_guessed(self):
        with self.assertRaisesRegex(ContentError, 'composition'):
            read(fixture(b'ABCD'))

    def test_bank_name_cannot_become_a_path(self):
        data = fixture().replace(b'FMOD_GOF2_TEST\0', b'../D_GOF2_TEST\0')
        with self.assertRaisesRegex(ContentError, 'bank name'):
            read(data)


if __name__ == '__main__':
    unittest.main()
