"""Synthetic indexed light layers: masks, sentinels, relocations and call identity."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from test_materials import arm_wide
from test_ship_models import branch
from gof2_content.ship_lights import extract_ship_lights


def fixture(mac):
    count = 61 if mac else 64
    base = 0x100002000 if mac else 0x2000
    address = base + 8192
    hulls = list(range(1000, 1000 + count))
    layers = [[10000 + i if i % 3 == 0 else 65535 for i in range(count)],
              [12000 + i if i % 2 == 0 else 65535 for i in range(count)]]
    layers[1][6] = layers[0][6]
    code = bytearray(1024)
    def call(at, target=800):
        return b'\xe8' + struct.pack('<i', target - at - 5) if mac else branch(base + at, base + target)
    def pc_pair(at, target, reg=0, gap=b'', after=0):
        disp = target - base - at - 8 - len(gap) - after - 4
        return arm_wide(disp & 65535, reg) + gap + arm_wide(disp >> 16, reg, True)
    root_at = 64
    if mac:
        root = bytes.fromhex('4d63f4488d05') + struct.pack('<i', address - base - root_at - 10) + bytes.fromhex('420fb73470488b15') + bytes(4) + bytes.fromhex('4c89ffb901000000') + call(root_at + 30)
    else:
        root = pc_pair(root_at, address, 1, bytes.fromhex('0623'), 8) + bytes(8) + bytes.fromhex('79447a44499031f81610499812684b9301230596') + call(root_at + 38)
    code[root_at:root_at + len(root)] = root
    sites = []
    for layer in range(2):
        at = root_at + len(root) + 16 + layer * 160
        target = address + count * 2 * (layer + 1)
        if mac:
            mask = sum(1 << i for i, id in enumerate(layers[layer]) if id != 65535)
            b = bytearray(bytes.fromhex('48b8') + struct.pack('<Q', mask) + bytes.fromhex('4c0fa3f073') + bytes([103 if layer == 0 else 75]))
            if layer == 0:
                b += bytes.fromhex('488d05') + struct.pack('<i', target - base - at - len(b) - 7)
                b += bytes.fromhex('420fb73470488b3d') + bytes(4) + bytes.fromhex('488d95d0feffffb901000000'); b += call(at + len(b))
                b += bytes.fromhex('488b3d') + bytes(4) + bytes.fromhex('488db5d4feffff'); b += call(at + len(b))
                b += bytes.fromhex('8b95d0feffff8bb5d4feffff488b3d') + bytes(4); b += call(at + len(b))
                b += bytes.fromhex('8bb5d4feffff4c89ff'); sites.append(256 + at + len(b)); b += call(at + len(b))
                b += bytes.fromhex('8b85d0feffff41894728')
            else:
                b += bytes.fromhex('c785c8feffffffffffff488b3d') + bytes(4) + bytes.fromhex('488db5c8feffff'); b += call(at + len(b))
                b += bytes.fromhex('488d05') + struct.pack('<i', target - base - at - len(b) - 7)
                b += bytes.fromhex('420fb714708bb5c8feffff488b3d') + bytes(4) + bytes.fromhex('31c9'); b += call(at + len(b))
                b += bytes.fromhex('8bb5c8feffff4c89ff'); sites.append(256 + at + len(b)); b += call(at + len(b))
        else:
            b = bytearray(pc_pair(at, target, after=2 if layer == 0 else 0))
            if layer == 0:
                b += bytes.fromhex('059a784430f812104ff0ff30924610900f904ff6ff70814221d0499c') + bytes(8) + bytes.fromhex('0faa78444ff0ff350123064630684b95'); b += call(at + len(b))
                b += bytes.fromhex('306810a94b95'); b += call(at + len(b))
                b += bytes.fromhex('30680f9a10994b95'); b += call(at + len(b))
                b += bytes.fromhex('109920464b95'); sites.append(256 + at + len(b)); b += call(at + len(b))
                b += bytes.fromhex('0f9849990862')
            else:
                b += bytes.fromhex('784430f81a404ff6ff7084421bd04ff0ff36ddf824810d96') + bytes(8) + bytes.fromhex('0da97844054628684b96'); b += call(at + len(b))
                b += bytes.fromhex('286822460d9900234b96'); b += call(at + len(b))
                b += bytes.fromhex('0d9940464b96'); sites.append(256 + at + len(b)); b += call(at + len(b))
        code[at:at + len(b)] = b
    constants = struct.pack('<' + str(count * 3) + 'H', *(hulls + layers[0] + layers[1]))
    text = {'offset': 256, 'length': len(code), 'address': base, 'segment': b'__TEXT', 'name': b'__text'}
    const = {'offset': 1280, 'length': len(constants), 'address': address, 'segment': b'__TEXT', 'name': b'__const'}
    mach = SimpleNamespace(data=bytes(256) + code + constants, text=text, sections=[text, const], slice_offset=0, architecture='x86_64' if mac else 'armv7')
    return mach, {'resource_ids': hulls, 'table_offsets': [1280]}, list(map(list, zip(*layers))), sites


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class LightTests(unittest.TestCase):
    def test_both_architectures_preserve_empty_and_duplicate_layers(self):
        for mac in (True, False):
            mach, models, expected, _ = fixture(mac)
            result = extract_ship_lights(mach, models)
            self.assertEqual(result['resource_ids'], expected)
            self.assertEqual(result['resource_ids'][6], [10006, 10006])
            self.assertEqual(result['provenance'][0]['offset'], 320)

    def test_wrong_hull_reference_calls_and_table_extent_fail(self):
        for mac in (True, False):
            for corruption in ('hull', 'offset', 'extent', 'attach', 'selection'):
                mach, models, _, sites = fixture(mac)
                data = bytearray(mach.data)
                if corruption == 'hull': models['resource_ids'][0] = 3000
                elif corruption == 'offset': models['table_offsets'] = [1282]
                elif corruption == 'extent': mach.sections[-1]['length'] -= 1
                elif corruption == 'attach': data[sites[1] + 2] ^= 1
                elif corruption == 'selection':
                    # An altered x86 mask or ARM sentinel-test branch must not
                    # silently change the interpretation of the same tables.
                    at = 256 + 64 + (35 if mac else 42) + 16
                    data[at + (2 if mac else 33)] ^= 1
                mach.data = bytes(data)
                self.assertEqual(extract_ship_lights(mach, models), {}, (mac, corruption))
