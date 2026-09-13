"""Synthetic Mach-O declarations, never executed and containing no original assets."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from gof2_content.registrations import extract, MachO, thumb_immediate, READER
from gof2_content.bindings import prepare, binding_id
from gof2_content.formats import ContentError
from gof2_content.importer import install
from test_content import fixture, archive
from test_fev import fixture as audio_fixture

PATH = 'data/assets/main/3d/meshes/ship.aem'


def wide(value, top=False):
    first = (0xf2c0 if top else 0xf240) | ((value >> 12) & 15) | ((value >> 1) & 0x400)
    second = 0x100 | ((value << 4) & 0x7000) | (value & 255)
    return struct.pack('<2H', first, second)


def executable(edition='mac-full-hd', identifier=17, gap=b''):
    mac = edition == 'mac-full-hd'
    text_address, string_address = (0x100002000, 0x100003000) if mac else (0x2000, 0x3000)
    if mac:
        code = (bytes.fromhex('49 89 04 24 48 8d 35') + struct.pack('<i', string_address - text_address - 11)
                + bytes.fromhex('48 89 c7 48 89 da e8 00 00 00 00 66 41 c7 07') + struct.pack('<H', identifier)
                + bytes.fromhex('41 c7 47 04 04 00 00 00 41 c7 47 08 ff ff ff ff 4d 89 67 10'))
    else:
        displacement = string_address - text_address - 8 - 12
        code = (bytes.fromhex('d6 f8 00 50 d6 f8 04 20') + wide(displacement & 65535) + wide(displacement >> 16, True)
                + bytes.fromhex('79 44 10 60 07 9a 00 f0 00 e8 d6 f8 00 00') + wide(identifier) + gap
                + bytes.fromhex('01 80 04 21 d6 f8 00 00 41 60 4f f0 ff 31 d6 f8 00 00 81 60 d6 f8 00 00 d6 f8 04 20 c2 60'))
    header_size, command_header, stride = (32, 72, 80) if mac else (28, 56, 68)
    command_size = command_header + stride * 2
    data = bytearray(1024 + len(PATH) + 1)
    struct.pack_into('<7I', data, 0, 0xfeedfacf if mac else 0xfeedface, 0x1000007 if mac else 12,
                     0, 2, 1, command_size, 0)
    struct.pack_into('<II', data, header_size, 0x19 if mac else 1, command_size)
    struct.pack_into('<I', data, header_size + (64 if mac else 48), 2)
    for i, (name, address, length, offset) in enumerate([
            (b'__text', text_address, len(code), 512), (b'__cstring', string_address, len(PATH) + 1, 1024)]):
        at = header_size + command_header + i * stride
        data[at:at + len(name)] = name
        data[at + 16:at + 22] = b'__TEXT'
        struct.pack_into('<QQI' if mac else '<3I', data, at + 32, address, length, offset)
    data[512:512 + len(code)] = code
    data[1024:] = PATH.encode() + b'\0'
    return bytes(data)


class BindingTests(unittest.TestCase):
    @unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
    def test_both_architectures_extract_only_declarations(self):
        for edition in ('ios-hd', 'mac-full-hd'):
            source = executable(edition)
            result = extract(source, edition)
            self.assertEqual(result['source_executable_sha256'], hashlib.sha256(source).hexdigest())
            self.assertEqual(len(result['registrations']), 1)
            row = result['registrations'][0]
            self.assertEqual((row['id'], row['resource'], row['registration_type']), (17, 'resources/' + PATH, 4))
            self.assertFalse(any(isinstance(value, bytes) for value in result.values()))

    def test_command_and_section_extents_and_encryption(self):
        for edition in ('ios-hd', 'mac-full-hd'):
            original = executable(edition)
            for length in range(260):
                with self.assertRaises(ContentError):
                    MachO(original[:length], edition)
            truncated = original[:-1]
            with self.assertRaises(ContentError):
                extract(truncated, edition)
            encrypted = bytearray(original)
            size = struct.unpack_from('<I', encrypted, 20)[0]
            header = 32 if edition == 'mac-full-hd' else 28
            struct.pack_into('<II', encrypted, 16, 2, size + 20)
            struct.pack_into('<5I', encrypted, header + size, 0x21, 20, 512, 16, 1)
            with self.assertRaisesRegex(ContentError, 'Encrypted'):
                extract(encrypted, edition)

    @unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
    def test_thumb_constants_and_nonmatching_payload(self):
        for value in (0, 1, 0x4321, 65535):
            self.assertEqual(thumb_immediate(wide(value), 0, 0xf240), value)
            self.assertEqual(thumb_immediate(wide(value, True), 0, 0xf2c0), value)
        source = executable('ios-hd')
        # Change only the footer payload pointer; nearby ID is not sufficient.
        at = source.rfind(bytes.fromhex('d6 f8 04 20'))
        broken = source[:at] + bytes.fromhex('d6 f8 08 20') + source[at + 4:]
        with self.assertRaisesRegex(ContentError, 'No supported'):
            extract(broken, 'ios-hd')
        # Compiler scratch-address setup may intervene; a write to the ID may not.
        self.assertEqual(len(extract(executable('ios-hd', gap=bytes.fromhex('0d f1 2c 08')),
                                     'ios-hd')['registrations']), 1)
        with self.assertRaisesRegex(ContentError, 'No supported'):
            extract(executable('ios-hd', gap=bytes.fromhex('01 31')), 'ios-hd')

    def test_wrong_architecture_and_unknown_template(self):
        with self.assertRaises(ContentError):
            extract(executable(), 'ios-hd')
        source = bytearray(executable())
        source[512] ^= 1
        with self.assertRaisesRegex(ContentError, 'No supported'):
            extract(source, 'mac-full-hd')

    def test_pack_identity_source_matching_and_cancellation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = fixture('mac')
            files['Contents/Resources/FMOD_GOF2.fev'] = audio_fixture()
            files['Contents/MacOS/DoNotRun'] = executable()
            source = archive(root / 'source.zip', 'mac', files)
            base, manifest = install(source, root / 'base')
            pack, header, diagnostics = prepare(source, base, root / 'bindings')
            self.assertEqual(set(p.name for p in pack.iterdir()), {'bindings.json', 'registrations.json'})
            self.assertEqual(header['binding_id'], binding_id(manifest['content_id'], header['source_executable_sha256'],
                                                            'x86_64', hashlib.sha256((pack / 'registrations.json').read_bytes()).hexdigest()))
            self.assertEqual(diagnostics['missing_resources'], [])
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['damage_particles'], {})
            self.assertNotIn('damage_particles', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['scenery_population'], {})
            self.assertNotIn('scenery_population', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['scenery_resources'], {})
            self.assertNotIn('scenery_resources', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['scenery_effects'], {})
            self.assertNotIn('scenery_effects', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['arrival_actor_construction'], {})
            self.assertNotIn('arrival_actor_construction', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['arrival_world_initialization'], {})
            self.assertNotIn('arrival_world_initialization', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['opening_handoff'], {})
            self.assertNotIn('opening_handoff', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['arrival_session'], {})
            self.assertNotIn('arrival_session', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['station_entry'], {})
            self.assertNotIn('station_entry', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['station_presentation'], {})
            self.assertNotIn('station_presentation', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['desktop_text'], {})
            self.assertNotIn('desktop_text', header)
            self.assertEqual(header['reader'], READER)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['station_departure'], {})
            self.assertNotIn('station_departure', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['first_flight'], {})
            self.assertNotIn('first_flight', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['mining_briefing'], {})
            self.assertNotIn('mining_briefing', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['mining_drill'], {})
            self.assertNotIn('mining_drill', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['mining_targeting'], {})
            self.assertNotIn('mining_targeting', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['mining_approach'], {})
            self.assertNotIn('mining_approach', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['mining_session'], {})
            self.assertNotIn('mining_session', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['flight_notices'], {})
            self.assertNotIn('flight_notices', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['mining_objective'], {})
            self.assertNotIn('mining_objective', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['station_exterior'], {})
            self.assertNotIn('station_exterior', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['station_autopilot'], {})
            self.assertNotIn('station_autopilot', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['station_flight'], {})
            self.assertNotIn('station_flight', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['station_return'], {})
            self.assertNotIn('station_return', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_departure'], {})
            self.assertNotIn('full_hold_departure', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_flight'], {})
            self.assertNotIn('full_hold_flight', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_pirate'], {})
            self.assertNotIn('full_hold_pirate', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_control'], {})
            self.assertNotIn('full_hold_control', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_destruction'], {})
            self.assertNotIn('full_hold_destruction', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_story'], {})
            self.assertNotIn('full_hold_story', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_appearance'], {})
            self.assertNotIn('full_hold_appearance', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['full_hold_return'], {})
            self.assertNotIn('full_hold_return', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['player_destruction'], {})
            self.assertNotIn('player_destruction', header)
            self.assertEqual(json.loads((pack / 'registrations.json').read_text())['game_over_presentation'], {})
            self.assertNotIn('game_over_presentation', header)
            before = (pack / 'registrations.json').read_bytes()
            # Same content assets, different executable declarations: different identity.
            files['Contents/MacOS/DoNotRun'] = executable(identifier=18)
            changed = archive(root / 'changed.zip', 'mac', files)
            second, second_header, _ = prepare(changed, base, root / 'bindings')
            self.assertNotEqual(header['binding_id'], second_header['binding_id'])
            self.assertEqual(before, (pack / 'registrations.json').read_bytes())
            def cancel(message, _):
                if message == 'Activating resource declarations':
                    raise InterruptedError('cancelled')
            with self.assertRaises(InterruptedError):
                prepare(changed, base, root / 'cancelled', cancel)
            self.assertEqual(list((root / 'cancelled').iterdir()), [])
            self.assertTrue(second.is_dir())
            files['Contents/Resources/data/bin/items.bin'] = b'change'
            mismatch = archive(root / 'mismatch.zip', 'mac', files)
            with self.assertRaisesRegex(ContentError, 'checksum differs'):
                prepare(mismatch, base, root / 'bad')
            self.assertFalse((root / 'bad').exists())
            self.assertFalse(any('DoNotRun' in name for name in manifest['files']))


if __name__ == '__main__':
    unittest.main()
