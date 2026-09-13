"""Relocated synthetic effect declarations and bounded layout rejection."""
import copy
import struct
from types import SimpleNamespace
import unittest
from gof2_content import scenery_effects as reader
from test_font_selection import expand
from test_ship_models import branch
from test_materials import arm_wide


def fixture(mac, relocation=0):
    base = 0x4000 + relocation
    offset, slice_offset = 512, 4096 if mac else 0
    data = bytearray(24576)
    sites = {'outer': 2000, 'actor_wrapper': 4000, 'effect_wrapper': 4500,
             'constructor': 5000, 'actor': 8000, 'scale': 10000,
             'speed_setter': 11000, 'threshold': 20000, 'speed_scale': 20004}
    relative = {'switch': 1414, 'default': 1118, 'ordinary': 1230, 'void': 318, 'ice': 411, 'magma': 498} if mac else {'switch': 136, 'default': 290, 'ordinary': 390, 'void': 454, 'ice': 546, 'magma': 638}
    sites.update({key: sites['constructor'] + delta for key, delta in relative.items()})
    links = {
        'outer': {'call_39' if mac else 'bl_26': 'actor_wrapper'},
        'actor_wrapper': {'branch_5' if mac else 'bl_26': 'actor'},
        'actor': {'call_19b' if mac else 'bl_1ba': 'effect_wrapper', 'call_1b0' if mac else 'bl_1d0': 'scale'},
        'effect_wrapper': {'branch_5' if mac else 'bl_6': 'constructor'},
        'constructor': {'branch_94' if mac else 'branch_bhi_82': 'default', 'ref_9d': 'switch'},
        'default': {'branch_1b' if mac else 'branch_bne_22': 'ordinary'},
        'scale': {key: 'speed_setter' for key in (('call_d7', 'call_ff', 'call_136') if mac else ('bl_c4', 'bl_d8', 'bl_fc'))},
    }
    links['scale'].update({'ref_45': 'threshold', 'ref_53': 'threshold', 'ref_63': 'speed_scale', 'blx_110': 21000, 'blx_120': 21016})
    blocks = {}
    model_ids = [[600, 601], [600, 603], [604, 605], [606, 607]]
    for key in ('outer', 'actor_wrapper', 'actor', 'effect_wrapper', 'constructor', 'default', 'ordinary', 'void', 'ice', 'magma', 'scale', 'speed_setter'):
        at = sites[key]
        raw, fields = expand(getattr(reader, ('MAC_' if mac else 'ARM_') + key.upper()))
        for name, (position, size) in fields.items():
            site = base + at + position
            if name.startswith('model'):
                identifier = model_ids[('ordinary', 'void', 'ice', 'magma').index(key)][int(name[-1])]
                value = identifier.to_bytes(size, 'little') if mac else arm_wide(identifier, 1)
            elif name in ('threshold', 'speed_base', 'speed_scale'):
                value = bytes.fromhex({'threshold': '87ef108f', 'speed_base': 'c7ef100f', 'speed_scale': 'c0ef182f'}[name])
            elif name.startswith(('movw_', 'movt_')):
                mnemonic, register, _ = name.split('_')
                value = arm_wide(0, int(register[1:]), mnemonic == 'movt')
            else:
                dest = links.get(key, {}).get(name, 15000)
                dest = sites[dest] if isinstance(dest, str) else dest
                if key in ('ordinary', 'ice', 'magma') and mac and name.startswith('branch_'):
                    dest = sites['void'] + 80
                elif key in ('void', 'ice', 'magma') and not mac and name.startswith('branch_'):
                    dest = sites['ordinary'] + 58
                elif not mac and name.startswith('branch_') and key == 'ordinary':
                    dest = 6000
                if mac:
                    value = (base + dest - site - size).to_bytes(size, 'little', signed=True)
                elif name.startswith('branch_'):
                    kind = name[7:].rsplit('_', 1)[0]
                    delta = (base + dest - site - 4) // 2
                    if kind == 'b': value = struct.pack('<H', 0xe000 | (delta & 2047))
                    else: value = struct.pack('<H', 0xd000 | ({'bhi': 8, 'bne': 1}[kind] << 8) | (delta & 255))
                else:
                    blx = name.startswith('blx_')
                    value = bytearray(branch(((site + 4) & ~3) - 4 if blx else site, base + dest))
                    if blx: value[3] &= ~0x10
            raw[position:position + size] = value
        data[offset + at:offset + at + len(raw)] = raw
        blocks[key] = (at, raw, fields)
    targets = [sites['default'], sites['void'], sites['ice'], sites['magma']]
    table = [0] * 13
    for index, target in enumerate(targets, 2): table[index] = (target - sites['switch']) // (1 if mac else 2)
    struct.pack_into('<13i' if mac else '<13H', data, offset + sites['switch'], *table)
    struct.pack_into('<2f', data, offset + sites['threshold'], 1.0, 3.0)
    sections = [{'name': b'__text', 'segment': b'__TEXT', 'address': base, 'offset': offset, 'length': 18000},
                {'name': b'__const', 'segment': b'__TEXT', 'address': base + 20000, 'offset': offset + 20000, 'length': 8}]
    if not mac:
        # Only symbol-table metadata: no imported implementation is present.
        struct.pack_into('<7I', data, 0, 0xfeedface, 12, 0, 2, 3, 228, 0)
        struct.pack_into('<2I', data, 28, 1, 124)
        struct.pack_into('<I', data, 28 + 48, 1)
        section = 28 + 56
        struct.pack_into('<3I', data, section + 32, base + 21000, 32, offset + 21000)
        struct.pack_into('<3I', data, section + 56, 8, 0, 16)
        strings = b'\0___floatdisf\0___fixsfdi\0'
        struct.pack_into('<6I', data, 152, 2, 24, 23000, 2, 23100, len(strings))
        struct.pack_into('<2I', data, 176, 11, 80)
        struct.pack_into('<2I', data, 176 + 56, 23200, 2)
        struct.pack_into('<IB', data, 23000, 1, 1)
        struct.pack_into('<IB', data, 23012, 14, 1)
        data[23100:23100 + len(strings)] = strings
        struct.pack_into('<2I', data, 23200, 0, 1)
    mach = SimpleNamespace(data=bytes(data), architecture='x86_64' if mac else 'armv7', text=sections[0], sections=sections, slice_offset=slice_offset)
    resources = {'model_ids': [100, 200, 300, 400], 'provenance': {'models': {'offset': slice_offset + offset + 1000, 'bytes': 91 if mac else 36}}}
    return mach, resources, blocks


class SceneryEffects(unittest.TestCase):
    def test_relocated_variant_links_and_only_declarations(self):
        for mac in (True, False):
            for relocation in (0, 0x800000):
                mach, resources, _ = fixture(mac, relocation)
                result = reader.extract_scenery_effects(mach, resources)
                self.assertTrue(result, (mac, relocation))
                self.assertEqual([r['base_model_id'] for r in result['variants']], resources['model_ids'])
                self.assertEqual([r['effect_type'] for r in result['variants']], [2, 3, 4, 5])
                self.assertEqual([r['model_ids'] for r in result['variants']], [[600, 601], [600, 603], [604, 605], [606, 607]])
                self.assertEqual([result[k] for k in ('speed_threshold', 'speed_base', 'speed_scale')], [1.0, 1.0, 3.0])
                self.assertEqual(set(result), {'variants', 'speed_threshold', 'speed_base', 'speed_scale', 'provenance'})
                self.assertEqual(len(result['provenance']), 15 if mac else 13)

    def test_each_proof_region_rejects_changed_layout(self):
        for mac in (True, False):
            mach, resources, _ = fixture(mac)
            result = reader.extract_scenery_effects(mach, resources)
            self.assertTrue(result, mac)
            for key, span in result['provenance'].items():
                bad = copy.copy(mach)
                data = bytearray(mach.data)
                at = span['offset'] - mach.slice_offset
                if key == 'switch': at += 8 if mac else 4
                data[at] ^= 255
                bad.data = bytes(data)
                self.assertFalse(reader.extract_scenery_effects(bad, resources), (mac, key))

    def test_disconnected_calls_and_ambiguous_outer(self):
        for mac in (True, False):
            mach, resources, blocks = fixture(mac)
            for key, field in [('outer', 'call_39' if mac else 'bl_26'), ('actor_wrapper', 'branch_5' if mac else 'bl_26'), ('actor', 'call_19b' if mac else 'bl_1ba'), ('scale', 'call_ff' if mac else 'bl_d8'), ('ice', 'call_21' if mac else 'bl_2c')]:
                bad = copy.copy(mach)
                data = bytearray(mach.data)
                at, _, fields = blocks[key]
                p, size = fields[field]
                data[512 + at + p:512 + at + p + size] = bytes(size)
                bad.data = bytes(data)
                self.assertFalse(reader.extract_scenery_effects(bad, resources), (mac, key))
            bad = copy.copy(mach)
            data = bytearray(mach.data)
            raw = blocks['outer'][1]
            data[512 + 3000:512 + 3000 + len(raw)] = raw
            bad.data = bytes(data)
            self.assertFalse(reader.extract_scenery_effects(bad, resources))
            self.assertFalse(reader.extract_scenery_effects(mach, {}))
            for ids in ([100, 100, 300, 400], [1, 2, 3], [True, 2, 3, 4], [-1, 2, 3, 4]):
                malformed = copy.deepcopy(resources); malformed['model_ids'] = ids
                self.assertFalse(reader.extract_scenery_effects(mach, malformed))
            truncated = copy.copy(mach); truncated.data = mach.data[:8500]
            self.assertFalse(reader.extract_scenery_effects(truncated, resources))

    def test_arm_conversion_symbols_and_model_operands(self):
        mach, resources, blocks = fixture(False)
        for at in (23102, 23116, 23004, 23204, 28 + 56 + 64):
            bad = copy.copy(mach); data = bytearray(mach.data); data[at] ^= 255; bad.data = bytes(data)
            self.assertFalse(reader.extract_scenery_effects(bad, resources), at)
        at, _, fields = blocks['ordinary']; position, _ = fields['model0']
        bad = copy.copy(mach); data = bytearray(mach.data)
        data[512 + at + position:512 + at + position + 4] = arm_wide(600, 2)
        bad.data = bytes(data)
        self.assertFalse(reader.extract_scenery_effects(bad, resources))
