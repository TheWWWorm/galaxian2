"""Relocated synthetic rescue declarations, independent content and bad links."""
import importlib.util
import struct
import unittest
from test_opening_dialogue import fixture as opening_fixture
from test_ship_models import branch
from test_materials import arm_wide
from gof2_content.opening_dialogue import extract_opening_dialogue, extract_arrival_dialogue


def fixture(mac, shift=0):
    mach, _ = opening_fixture(mac, shift)
    code = bytearray(mach.data[256:])
    base = mach.text['address']
    pos = 4000
    marks = {}

    def raw(value):
        nonlocal pos
        value = bytes.fromhex(value) if isinstance(value, str) else value
        code[pos:pos + len(value)] = value
        pos += len(value)

    def jump(target, kind='call'):
        if mac:
            raw('e8' if kind == 'call' else 'e9')
            raw(struct.pack('<i', target - pos - 4))
        else:
            data = bytearray(branch(base + pos - (pos % 4 if kind == 'blx' else 0), base + target))
            if kind == 'blx': data[3] &= ~0x10
            if kind == 'jump': data[3] &= ~0x40
            raw(data)

    def mov(reg, value):
        if mac:
            raw({'edi': 'bf', 'esi': 'be', 'edx': 'ba', 'ecx': 'b9', 'r8d': '41b8'}[reg])
            raw(struct.pack('<I', value))
        else:
            number = int(reg[1:])
            raw(struct.pack('<H', 0x2000 | number << 8 | value) if value < 256 else arm_wide(value, reg=number))

    if mac:
        code[7004:7008] = struct.pack('<i', pos - 7000)
        mov('edi', 24); jump(11000); raw('4889c3'); mov('edi', 8); jump(11004)
        raw('48894308c743100100000048c70000000000c7030000000049899fb0010000')
        marks['count'] = pos; mov('edi', 3); raw('4889de'); jump(11008)
    else:
        code[268:270] = struct.pack('<H', (pos - 266) // 2)
        raw('4ff0ff30cdf8f0050c20'); jump(11000, 'blx')
        raw('1e901920cdf8f00504200595'); jump(11004, 'blx')
        raw('1e9901231e9a50601e9a9360002202601e9802600598c0f81411')
        marks['count'] = pos; mov('r0', 3); jump(11008)
    for i in range(3):
        marks['record' + str(i)] = pos
        text, speaker, condition, value = 3000 + i, 40 + i, 5 if i == 0 else 6, 4321 if i == 0 else i - 1
        if mac:
            mov('edi', 56); jump(11000); raw('4889c34889df')
            mov('esi', text); mov('edx', speaker); mov('ecx', condition); mov('r8d', value)
            marks['constructor' + str(i)] = pos; jump(8000)
            raw('498b87b0010000488b4008')
            raw('488918' if i == 0 else '488958' + bytes([i * 8]).hex())
        else:
            raw('4ff0ff30cdf8f0052820'); jump(11000, 'blx'); mov('r1', i + 26)
            raw(bytes([31 + i, 0x90, 31 + i, 0x98])); raw('cdf8f015')
            mov('r1', value); mov('r2', speaker); raw('0091'); mov('r1', text); mov('r3', condition)
            marks['constructor' + str(i)] = pos; jump(8000)
            raw(bytes([31 + i, 0x98]))
            if i < 2:
                raw('0599d1f814114968'); raw(struct.pack('<H', 0x6008 | i << 6))
    marks['tail'] = pos
    jump(12000 if mac else 6000, 'jump')
    if not mac:
        pos = 6000; marks['shared_store'] = pos
        raw('059ad2f8141149688860'); marks['shared_exit'] = pos; jump(12000, 'jump')
    mach.data = bytes(256) + code
    return mach, marks


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class ArrivalDialogueTests(unittest.TestCase):
    def test_relocated_changed_content_and_shared_owner(self):
        for mac in (False, True):
            for shift in (0, 0x22000):
                mach, _ = fixture(mac, shift)
                opening = extract_opening_dialogue(mach)
                arrival = extract_arrival_dialogue(mach, opening)
                self.assertTrue(arrival, (mac, shift))
                self.assertEqual(arrival['campaign_cursor'], 1)
                self.assertEqual([r['text_id'] for r in arrival['events']], [3000, 3001, 3002])
                self.assertEqual([r['speaker_id'] for r in arrival['events']], [40, 41, 42])
                self.assertEqual([r['values'] for r in arrival['events']], [[4321], [0], [1]])
                self.assertEqual(arrival['timing'], opening['timing'])
                self.assertEqual('shared_store' in arrival['provenance'], not mac)
                self.assertEqual(extract_arrival_dialogue(mach, {}), {})

    def test_corrupt_record_store_dispatch_and_epilogue(self):
        for mac in (False, True):
            scenarios = ['count', 'record1', 'constructor2', 'tail', 'dispatch', 'owner']
            if not mac: scenarios += ['shared_store', 'shared_exit']
            for key in scenarios:
                mach, marks = fixture(mac)
                opening = extract_opening_dialogue(mach)
                code = bytearray(mach.data)
                if key == 'owner':
                    opening['provenance']['single_constructor']['offset'] += 2
                else:
                    offset = (7004 if mac else 268) if key == 'dispatch' else marks[key]
                    code[256 + offset] ^= 0x80
                    mach.data = bytes(code)
                self.assertEqual(extract_arrival_dialogue(mach, opening), {}, (mac, key))

    def test_valid_branch_to_wrong_epilogue_is_rejected(self):
        for mac in (False, True):
            mach, marks = fixture(mac)
            opening = extract_opening_dialogue(mach)
            code = bytearray(mach.data)
            pos = marks['tail'] if mac else marks['shared_exit']
            raw = b'\xe9' + struct.pack('<i', 12100 - pos - 5) if mac else bytearray(branch(mach.text['address'] + pos, mach.text['address'] + 12100))
            if not mac: raw[3] &= ~0x40
            code[256 + pos:256 + pos + len(raw)] = raw
            mach.data = bytes(code)
            self.assertEqual(extract_arrival_dialogue(mach, opening), {})
