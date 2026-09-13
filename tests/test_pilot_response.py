"""Synthetic pilot declarations; fixture bytes are inspected, never executed."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from gof2_content.pilot_response import extract_pilot_response


def fixture(mac, relocation=0):
    base = (0x100002000 if mac else 0x2000) + relocation
    code = bytearray(2048)
    # Separate storage for every reference lets tests detect disagreement.
    values = [-630.0, 3.0, 16.0, 3.0, 16.0, -120.0, 120.0, -120.0, 120.0]
    constants = struct.pack('<9f', *values)
    address = base + (8192 if mac else 1100)
    def reference(at, index, register=4):
        target = address + index * 4
        if mac:
            return struct.pack('<i', target - base - at - 4)
        delta = target - ((base + at + 4) & ~3)
        assert delta % 4 == 0 and abs(delta) <= 1020
        return bytes([0x9f if delta >= 0 else 0x1f, 0xed, abs(delta) // 4, (register // 2 << 4) | 0xa])
    if mac:
        quantizer = bytes.fromhex('f30f100d') + reference(204, 0) + bytes.fromhex('f30f59c8f30f59cdf30f2cc14863c0f30f1183040300004869c88320088248c1e92001c889c1c1e91fc1f80501c8')
        for at, index in [(400, 1), (500, 3)]:
            ramp = bytes.fromhex('f30f1025') + reference(at + 4, index) + bytes.fromhex('f30f5c20f30f5925') + reference(at + 16, index + 1) + bytes.fromhex('f3410f2adef30f59ddf30f5edc')
            code[at:at + len(ramp)] = ramp
        for at, index in zip((600, 700, 800, 1200), range(5, 9)):
            neutral = bytes.fromhex('0f57c9f3410f2accf3410f598ea4010000f30f5e0d') + reference(at + 21, index) + bytes.fromhex('0f57d2f30f58c1')
            code[at:at + len(neutral)] = neutral
    else:
        quantizer = reference(200, 0) + bytes.fromhex('42f28301c8f20821b9ff811748ff120d40ff900d84ed961a84ed998abbff202712ee100a94ed9e2a51fb0000411101ebd070')
        ramp = reference(400, 1, 6) + bytes(4) + bytes.fromhex('45ec305b7844fbff2006') + bytes.fromhex('c3ef142f') + bytes.fromhex('006800f1180200ff900d417c002918bf00f1140292ed004a63ef044d04ffb23d80ee030a')
        code[400:400 + len(ramp)] = ramp
        for at, index in zip((600, 700, 800, 1200), range(5, 9)):
            neutral = bytes.fromhex('46ec306b9bed541afbff2006') + reference(at + 12, index) + bytes.fromhex('00ff911d81ee021a00ef010d')
            code[at:at + len(neutral)] = neutral
        code[1100:1136] = constants
    code[200:200 + len(quantizer)] = quantizer
    text = dict(offset=256, address=base, length=len(code), segment=b'__TEXT', name=b'__text')
    sections = [text]
    if mac:
        sections.append(dict(offset=2304, address=address, length=len(constants), segment=b'__TEXT', name=b'__literal4'))
    return SimpleNamespace(data=bytes(256) + code + (constants if mac else b''), text=text,
                           sections=sections, architecture='x86_64' if mac else 'armv7', slice_offset=4096)


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class PilotResponseTests(unittest.TestCase):
    def test_relocated_and_alternative_constants(self):
        for mac in (True, False):
            for relocation in (0, 0x3200):
                m = fixture(mac, relocation)
                result = extract_pilot_response(m, {'available': True})
                self.assertEqual(result['target_gain'], 630)
                self.assertEqual(result['target_divisor'], 63)
                self.assertEqual(result['ramp_bias'], 3)
                self.assertEqual(result['ramp_scale'], 16 if mac else 20)
                self.assertEqual(result['neutral_divisor'], 120)
                self.assertEqual(result['command_curve'], 'signed_square')
                sizes = ([54, 33, 33, 32, 32, 32, 32] + [4] * 9 if mac else [54, 58, 28, 28, 28, 28] + [4] * 7)
                self.assertEqual([p['bytes'] for p in result['provenance']], sizes)
                self.assertEqual(result['provenance'][0]['offset'], 4096 + 256 + 200)
                self.assertTrue(all(4096 <= p['offset'] < 4096 + len(m.data) for p in result['provenance']))
                self.assertEqual(extract_pilot_response(m, {}), {})

    def test_ambiguous_corrupt_and_disagreeing_data_is_unsupported(self):
        cases = ['duplicate', 'quantizer', 'ramp', 'neutral', 'nan', 'positive_gain', 'zero_bias', 'neutral_signs', 'neutral_mismatch', 'extent', 'target', 'load']
        for mac in (True, False):
            for corruption in cases + (['ramp_mismatch', 'scale_mismatch'] if mac else ['immediate']):
                m = fixture(mac); data = bytearray(m.data)
                constant = 2304 if mac else 1356
                if corruption == 'duplicate': data[256 + 1600:256 + 1654] = data[456:510]
                elif corruption == 'extent':
                    if mac: m.sections[-1]['length'] -= 1
                    else: m.data = m.data[:constant + 35]; data = bytearray(m.data)
                elif corruption == 'target': data[256 + 200 + (4 if mac else 2)] ^= 0x80
                elif corruption == 'load': data[256 + 200 + (0 if mac else 3)] ^= 0x10
                elif corruption == 'immediate': data[256 + 418:256 + 422] = bytes(4)
                elif corruption in ('quantizer', 'ramp', 'neutral'):
                    at = {'quantizer': 220, 'ramp': 424, 'neutral': 600}[corruption]
                    data[256 + at] ^= 1
                else:
                    changes = {'nan': [(0, float('nan'))], 'positive_gain': [(0, 630)], 'zero_bias': [(1, 0)],
                               'neutral_signs': [(5, 120), (7, 120)], 'neutral_mismatch': [(6, 121)],
                               'ramp_mismatch': [(3, 2)], 'scale_mismatch': [(4, 15)]}[corruption]
                    for index, value in changes: struct.pack_into('<f', data, constant + index * 4, value)
                m.data = bytes(data)
                self.assertEqual(extract_pilot_response(m, {'available': True}), {}, (mac, corruption))
