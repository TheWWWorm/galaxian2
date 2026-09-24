"""Relocated synthetic opening declarations with changed content selections."""
import importlib.util
import struct
from types import SimpleNamespace
import unittest
from test_ship_models import branch
from test_materials import arm_wide
from gof2_content.opening_loadout import (MAC, ARM, MAC_CLONE, MAC_STACK, ARM_CLONE, ARM_STACK,
                                         MAC_INSTALL, ARM_INSTALL, extract_opening_loadout, template)


class DeclarationTemplates(unittest.TestCase):
    def test_alternatives_are_complete_unique_layouts(self):
        patterns = template(('aabb {value:1} ccdd', 'eeff {value:1} 1122'))
        self.assertEqual(patterns.fullmatch(bytes.fromhex('aabb07ccdd'))['value'], b'\x07')
        self.assertEqual(patterns.match(bytes.fromhex('eeff08112200'))['value'], b'\x08')
        self.assertIsNone(patterns.fullmatch(bytes.fromhex('aabb071122')))
        self.assertIsNone(patterns.match(bytes.fromhex('eeff08ccdd')))
        self.assertIsNone(template(('aa {a:1}', 'aa {b:1}')).fullmatch(b'\xaa\x07'))
        self.assertEqual([m.start() for m in patterns.finditer(bytes.fromhex('eeff081122aabb07ccdd'))], [0, 5])
        data = bytes.fromhex('00aabb07ccdd00eeff081122')
        self.assertEqual(patterns.match(data, 1, 6)['value'], b'\x07')
        self.assertEqual(patterns.fullmatch(data, 7, 12)['value'], b'\x08')
        self.assertEqual([m.start() for m in patterns.finditer(data, 2, 12)], [7])


def fixture(mac, relocation=0):
    base = (0x100002000 if mac else 0x2000) + relocation
    code = bytearray(8192)
    places = {}
    def build(at, spec, values, label):
        raw = bytearray()
        for token in spec.split():
            if not token.startswith('{'):
                raw.extend(bytes.fromhex(token)); continue
            key, width = token[1:-1].split(':'); width = int(width)
            places[label + '.' + key] = at + len(raw)
            value = values.get(key, 0)
            if isinstance(value, tuple):
                target = base + value[0]
                value = struct.pack('<i', target - (base + at + len(raw) + 4)) if mac else branch(base + at + len(raw), target)
            raw.extend(value if isinstance(value, bytes) else value.to_bytes(width, 'little'))
        code[at:at + len(raw)] = raw
        return len(raw)
    clone, stack, install, category, ship, inner = 2048, 2304, 2560, 3000, 3300, 4000
    values = {k:(inner,) for k in ['ship_assign','ship_price','station_lookup','station_assign','cargo_clear']}
    values.update(ship_clone=(ship,), stack_clone=(stack,), station=9, quantity=11)
    for i in range(7):
        values['install%d'%i] = (install,)
        if i < 6: values['clone%d'%i] = (clone,)
        index = 5+i if i < 2 else 40+i
        values['item%d'%i] = index * 8 if mac else (struct.pack('<H', 0x6800 | index << 6) if i < 2 else bytes.fromhex('d0f8') + struct.pack('<H',index*4))
        values['slot%d'%i] = i % 4
    values['ship'] = 7*8 if mac else struct.pack('<H',0x6800 | 7 << 6)
    values['player_low'] = arm_wide(123, reg=0)
    values['player_high'] = arm_wide(0, reg=0, top=True)
    size = build(256, MAC if mac else ARM, values, 'seed')
    build(clone, MAC_CLONE if mac else ARM_CLONE, {'inner':(inner,), 'quantity':2, 'count':64}, 'clone')
    build(stack, MAC_STACK if mac else ARM_STACK, {'inner':(inner,), 'count':64}, 'stack')
    build(install + (0 if mac else 28), MAC_INSTALL if mac else ARM_INSTALL, {'category0':(category,), 'category1':(category,)}, 'install')
    if not mac:
        build(install+94, 'd8f8680050f824000134cdf820a006442846 {category:4} 8442f2db', {'category':(category,)}, 'loop')
    build(category, '554889e58b47045dc3' if mac else '40687047', {}, 'getter')
    build(ship, '554889e5535089f3e8 {inner:4} 85db78038958144883c4085b5dc3' if mac else '90b501af0c46 {inner:4} 002ca8bf446190bd', {'inner':(inner,)}, 'ship')
    text = dict(offset=256, address=base, length=len(code), segment=b'__TEXT', name=b'__text')
    return SimpleNamespace(data=bytes(256)+code, text=text, sections=[text], architecture='x86_64' if mac else 'armv7', slice_offset=4096), places, size


@unittest.skipUnless(importlib.util.find_spec('capstone'), 'Optional Capstone dependency not installed')
class OpeningLoadoutTests(unittest.TestCase):
    def test_changed_selections_and_relocation(self):
        for mac in (True, False):
            for relocation in (0, 0x8400):
                m, _, size = fixture(mac, relocation)
                value = extract_opening_loadout(m, {'item_type_value_index':5})
                self.assertEqual(value['ship_id'],7)
                self.assertEqual(value['station_id'],9)
                self.assertEqual([r['item_id'] for r in value['equipment']],[5,6,42,43,44,45,46])
                self.assertEqual([r['quantity'] for r in value['equipment']],[2]*6+[11])
                self.assertEqual(value['equipment'][5]['slot'],1)
                self.assertEqual(value['provenance']['declaration'],{'offset':4608,'bytes':size})
                self.assertEqual(extract_opening_loadout(m,{}),{})

    def test_broken_links_fields_and_ambiguity_rejected(self):
        for mac in (True, False):
            for case in ('clone_link','install_link','quantity','getter','stack_inner','ship','duplicate','extent','unaligned_index'):
                m, p, size = fixture(mac)
                data=bytearray(m.data)
                if case in ('clone_link','install_link','stack_inner'):
                    key={'clone_link':'seed.clone1','install_link':'seed.install6','stack_inner':'stack.inner'}[case]
                    at=p[key]; data[256+at:256+at+4]=struct.pack('<i',7000-at-4) if mac else branch(m.text['address']+at,m.text['address']+7000)
                elif case=='quantity':
                    at=p['seed.quantity']; data[256+at:256+at+(4 if mac else 1)]=bytes(4 if mac else 1)
                elif case=='getter': data[256+3000] ^= 1
                elif case=='ship': data[256+3300] ^= 1
                elif case=='duplicate': data[256+5000:256+5000+size]=data[512:512+size]
                elif case=='extent': m.text['length']=3000
                else:
                    at=p['seed.item0']; data[256+at] ^= 1  # Mac unaligned pointer; ARM wrong destination register.
                m.data=bytes(data)
                self.assertEqual(extract_opening_loadout(m,{'item_type_value_index':5}),{},(mac,case))
