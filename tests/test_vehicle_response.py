"""Synthetic linked vehicle declarations with relocated and altered constants."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from test_ship_models import branch
from gof2_content.vehicle_response import extract_vehicle_response


def fixture(mac, relocation=0):
    base = (0x100002000 if mac else 0x2000) + relocation
    code = bytearray(4096)
    def put(at, raw):
        code[at:at + len(raw)] = raw
    def hx(at, text): put(at, bytes.fromhex(text))
    def call(at, target):
        put(at, b'\xe8' + struct.pack('<i', target - at - 5) if mac else branch(base + at, base + target))
    def ref(at, target, reg=0):
        if mac: put(at, struct.pack('<i', target - at - 4))
        else:
            delta = target - ((at + 4) & ~3)
            assert delta % 4 == 0 and abs(delta) <= 1020
            put(at, bytes([0x9f if delta >= 0 else 0x1f, 0xed, abs(delta) // 4, reg // 2 * 16 + 0xa]))
    def val(at, value): put(at, struct.pack('<f', value))
    if mac:
        getter = bytearray.fromhex('554889e5488b8f880000000f57c94885c9742b8b010f57c985c07422488b49080f57c931d2f30f100500000000833c91077504f30f58c848ffc239c272eff30f104718f30f580500000000f30f5e0500000000f30f590500000000f30f580500000000f30f58c15dc3')
        put(512, getter)
        # Every reference is independently backed; no fixture uses original values.
        offsets = [getter.index(bytes.fromhex('f30f1005')) + 4]
        for opcode in ['f30f5805', 'f30f5e05', 'f30f5905']:
            offsets.append(getter.index(bytes.fromhex(opcode)) + 4)
        offsets.append(getter.rindex(bytes.fromhex('f30f5805')) + 4)
        for offset, target, value in zip(offsets, range(3000, 3020, 4), [0.25, -0.2, 2, 0.5, 0.8]):
            ref(512 + offset, target); val(target, value)
        hx(1024, 'e8000000000f57c0f30f2ac0f30f1183f0020000f30f5e0500000000f30f108ba4010000f30f59c1f30f58c1f30f590500000000f30f1183a4010000')
        call(1024, 2100); ref(1024 + code[1024:1084].index(bytes.fromhex('f30f5e05')) + 4, 3020); val(3020, 200)
        ref(1024 + code[1024:1084].index(bytes.fromhex('f30f5905')) + 4, 3024); val(3024, 30)
        call(880, 512); hx(885, 'f30f1183a4010000')
        hx(2100, '554889e58b47405dc3')
        hx(1800, '498b4770488b40084a8b3c30be21000000e80000000041894740')
        call(1817, 2200)
        hx(2200, '554889e5488b4f388b3931d2eb044883c202b8257899c539fa730d488b410839349075ea8b4490045dc3')
        hx(1600, 'e80000000083f81d0f870000000089c0486304834801d8ffe0'); call(1600, 2300)
        hx(2300, '554889e58b47085dc3')
        hx(1540, '488d1d00000000'); ref(1543, 2600)
        put(2600, struct.pack('<30i', *[(1800 if i == 12 else 2800) - 2600 for i in range(30)]))
        hx(2400, '554889e5488b47384885c0747d488b48088b4904890f488b48088b490c894f04488b48088b4914894f08')
    else:
        hx(512, '826f002a1cbfd2f80090b9f1000f02d1c0ef10000ee0c0ef1000526800000000002352f823100133072908bf40ef800d4b45f6d390ed060a00ef800d10ee100a7047')
        ref(540, 600); val(600, 0.25)
        # A structurally identical, unlinked getter must not cause ambiguity.
        put(640, code[512:578]); ref(668, 720); val(720, 0.75)
        hx(1024, '0000000040ec300bbbff2006c3ef1e2f80ee0a1a85ed940a95ed540a40ff110d40ef200d00ffb20d85ed540a')
        call(1024, 2100)
        ref(800, 1100, 20); val(1100, 200)
        call(880, 512); hx(884, 'c5f85001')
        hx(2100, '006c7047')
        hx(1800, 'e06e212140688059000000002064'); call(1808, 2200)
        hx(2200, '026bd2f80090b9f1000f08d05268002352f82300884207d002334b45f8d347f62500ccf29950704702eb830040687047')
        hx(1600, '000000001d2800f20000dfe800f0'); call(1600, 2300)
        put(1614, bytes([(1800 - 1614) // 2 if j == 12 else 0 for j in range(30)]))
        hx(2300, '80687047')
        hx(2400, '016b002908bf70474968c0ef50004a680260ca6842604a698260')
    text = dict(offset=256, address=base, length=len(code), segment=b'__TEXT', name=b'__text')
    return SimpleNamespace(data=bytes(256) + code, text=text, sections=[text],
                           architecture='x86_64' if mac else 'armv7', slice_offset=4096)


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class VehicleResponseTests(unittest.TestCase):
    def test_linked_readers_and_relocated_alternative_values(self):
        for mac in (True, False):
            for relocation in (0, 0x2400):
                m = fixture(mac, relocation)
                result = extract_vehicle_response(m, {'supported': True})
                self.assertEqual(result['upgrade_tag'], 7)
                self.assertEqual(result['upgrade_bonus'], 0.25)
                self.assertEqual(result['equipment_type'], 12)
                self.assertEqual(result['equipment_percent_property'], 33)
                self.assertEqual(result['item_type_value_index'], 5)
                self.assertEqual(result['percent_divisor'], 200)
                self.assertEqual(result['response_scale'], 30)
                self.assertEqual(result['equipment_rule'], 'last_matching')
                self.assertAlmostEqual(result['base_add'], -0.2 if mac else 0)
                self.assertEqual(result['base_divisor'], 2 if mac else 1)
                self.assertEqual(len(result['provenance']), 18 if mac else 14)
                self.assertEqual(result['provenance']['handling_getter']['offset'], 4096 + 256 + 512)
                self.assertEqual(extract_vehicle_response(m, {}), {})

    def test_corrupted_references_and_missing_content_are_rejected(self):
        for mac in (True, False):
            for case in ('handling_link', 'getter', 'equipment_getter', 'property_getter', 'type_getter', 'type_layout', 'table', 'bonus', 'divisor', 'extent', 'duplicate'):
                m=fixture(mac); data=bytearray(m.data)
                at={'handling_link':880, 'getter':512, 'equipment_getter':2100,
                    'property_getter':2200, 'type_getter':2300, 'type_layout':2400}.get(case)
                if at is not None: data[256 + at] ^= 1
                elif case == 'table':
                    at=2600 + 12 * 4 if mac else 1614 + 12
                    data[256+at] ^= 1
                elif case in ('bonus','divisor'):
                    at = (3000 if mac else 600) if case == 'bonus' else (3020 if mac else 1100)
                    struct.pack_into('<f',data,256+at,float('nan') if case=='bonus' else 0)
                elif case == 'extent': m.sections[0]['length']=2400
                elif case == 'duplicate':
                    size=60 if mac else 44
                    data[256+3200:256+3200+size]=data[256+1024:256+1024+size]
                m.data=bytes(data)
                self.assertEqual(extract_vehicle_response(m, {'supported':True}), {}, (mac,case))
