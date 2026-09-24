"""Relocated compiler-layout fixtures with synthetic glyph values and switch data."""
import struct
from types import SimpleNamespace
import unittest
from gof2_content.text_aliases import MAC, MAC_ALTERNATE, ARM, MAC_CASES, MAC_ALTERNATE_CASES, ARM_CASES, extract_text_aliases


def fixture(mac, relocation=0, alternate=False):
    code = bytearray(4096)
    start = 128
    marks = {}
    cursor = start
    for token in ((MAC_ALTERNATE if alternate else MAC) if mac else ARM).split():
        if token.startswith('{'):
            name, size = token[1:-1].split(':'); size = int(size)
            marks[name] = cursor
            value = 0 if name == 'table' else 65 + int(name[5:])
            code[cursor:cursor + size] = value.to_bytes(size, 'little')
            cursor += size
        else:
            data = bytes.fromhex(token); code[cursor:cursor+len(data)] = data; cursor += len(data)
    cases = (MAC_ALTERNATE_CASES if alternate else MAC_CASES) if mac else ARM_CASES
    table = 2048 if mac else marks['table']
    if mac:
        struct.pack_into('<i', code, marks['table'], table - marks['table'] - 4)
    for i in range(22):
        target = start + cases[1 + i // 2] if i % 2 == 0 else cursor
        if mac: struct.pack_into('<i', code, table + 4*i, target-table)
        else: code[table+i] = (target-table)//2
    section = {'segment': b'__TEXT', 'name': b'__text', 'address': 0x10000 + relocation, 'offset': 64, 'length': len(code)}
    mach = SimpleNamespace(data=bytes(64)+code, text=section, sections=[section], slice_offset=4096, architecture='x86_64' if mac else 'armv7')
    return mach, marks, table


class TextAliases(unittest.TestCase):
    def test_alternate_mac_aliases_keep_cases_and_merge_distinct(self):
        for relocation in (0, 0x2000):
            mach, marks, table = fixture(True, relocation, alternate=True)
            result = extract_text_aliases(mach)
            self.assertEqual(result['aliases'], extract_text_aliases(fixture(True, relocation)[0])['aliases'])
            self.assertEqual(result['provenance']['declaration']['bytes'], 543)
            data = bytearray(mach.data)
            data[64 + table] ^= 1
            mach.data = bytes(data)
            self.assertEqual(extract_text_aliases(mach), {})

    def test_relocated_declarations(self):
        for mac in [False, True]:
            for relocation in [0, 0x2000]:
                mach, marks, table = fixture(mac, relocation)
                result = extract_text_aliases(mach)
                self.assertEqual(len(result['aliases']), 20)
                rows = dict(result['aliases'])
                self.assertEqual(rows[0x60], 65)
                self.assertEqual(rows[0x410], 66)
                self.assertNotIn(0x411, rows)
                self.assertEqual(rows[0x430], 77)
                self.assertEqual(result['provenance']['declaration']['offset'], 4288)
                self.assertEqual(result['provenance']['switch_table']['offset'], 4160 + table)

    def test_corrupt_and_ambiguous_declarations(self):
        for mac in [False, True]:
            for mutation in ['shape', 'target', 'control', 'duplicate', 'truncated']:
                mach, marks, table = fixture(mac)
                data = bytearray(mach.data)
                if mutation == 'shape': data[64+128] ^= 1
                elif mutation == 'target': data[64+table] ^= 1
                elif mutation == 'control': data[64+marks['value0']] = 10
                elif mutation == 'duplicate':
                    size = 602 if mac else 438
                    data[64+1024:64+1024+size] = data[64+128:64+128+size]
                elif mutation == 'truncated': data = data[:64+128+400]
                mach.data = bytes(data)
                self.assertEqual(extract_text_aliases(mach), {}, (mac, mutation))


if __name__ == '__main__': unittest.main()
