"""Import-only Fast Forward recognition and native declaration contract."""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from gof2_content import fast_forward
from declaration_fixture import declaration_fixture


def fixture(rows, shift=0):
    mach, arrival, layouts = declaration_fixture(rows, shift, hash_prefix='sha256:')
    # Exercise the same section reader as initialized data and Objective-C metadata.
    for name, section in zip(rows, mach.sections):
        if section['name'] in (b'__data', b'__objc_const') or name == 'flight_vtable':
            section['segment'] = b'__DATA'
    return mach, arrival, layouts


class FastForwardTests(unittest.TestCase):
    def variants(self):
        return [('LAYOUTS', fast_forward.LAYOUTS), ('MAC_ALTERNATE', fast_forward.MAC_ALTERNATE)]

    def test_both_complete_layouts_and_relocated_virtual_addresses(self):
        for name, rows in self.variants():
            for relocation in (0, 0x800000):
                with self.subTest(layout=name, relocation=relocation):
                    mach, arrival, layouts = fixture(rows, relocation)
                    with patch.object(fast_forward, name, layouts):
                        result = fast_forward.extract_fast_forward(mach, arrival)
                    expected = copy.deepcopy(fast_forward.VALUES)
                    expected['provenance'] = {
                        key: {'offset': arrival['provenance']['actor']['offset'] + row[0], 'bytes': row[1]}
                        for key, row in layouts.items()}
                    self.assertEqual(result, expected)
                    self.assertEqual(len(result['provenance']), 82)

    def test_nested_output_is_detached(self):
        for name, rows in self.variants():
            mach, arrival, layouts = fixture(rows)
            with patch.object(fast_forward, name, layouts):
                first = fast_forward.extract_fast_forward(mach, arrival)
                first['activation']['navigation_any'].clear()
                first['camera']['initial_cached_handling'] = 1
                first['provenance']['arrival_actor']['offset'] = 0
                second = fast_forward.extract_fast_forward(mach, arrival)
                self.assertEqual(second['activation'], fast_forward.VALUES['activation'])
                self.assertEqual(second['camera'], fast_forward.VALUES['camera'])
                self.assertEqual(second['provenance']['arrival_actor'], arrival['provenance']['actor'])

    def test_optional_radar_uses_the_matching_core_layout(self):
        for core_name, radar_name in [('LAYOUTS', 'RADAR_LAYOUTS'),
                                      ('MAC_ALTERNATE', 'RADAR_MAC_ALTERNATE')]:
            core = getattr(fast_forward, core_name)
            radar = getattr(fast_forward, radar_name)
            combined = dict(core, **{'radar.' + key: row for key, row in radar.items()})
            for shift in (0, 0x800000):
                mach, arrival, rows = fixture(combined, shift)
                core_rows = {key: rows[key] for key in core}
                radar_rows = {key: rows['radar.' + key] for key in radar}
                with patch.object(fast_forward, core_name, core_rows), patch.object(fast_forward, radar_name, radar_rows):
                    result = fast_forward.extract_fast_forward(mach, arrival)
                    expected = copy.deepcopy(fast_forward.RADAR_VALUES)
                    expected['provenance'] = {key: {'offset': arrival['provenance']['actor']['offset'] + row[0], 'bytes': row[1]}
                                              for key, row in radar_rows.items()}
                    self.assertEqual(result.get('radar'), expected)
                    result['radar']['inactive_modes'].clear()
                    self.assertEqual(fast_forward.extract_fast_forward(mach, arrival)['radar'], expected)
                    origin = arrival['provenance']['actor']['offset'] - mach.slice_offset
                    for key, (delta, size, _, _) in radar_rows.items():
                        for endpoint in (0, size - 1):
                            with self.subTest(layout=core_name, guard=key, endpoint=endpoint):
                                changed = copy.copy(mach)
                                raw = bytearray(mach.data)
                                raw[origin + delta + endpoint] ^= 1
                                changed.data = bytes(raw)
                                self.assertNotIn('radar', fast_forward.extract_fast_forward(changed, arrival))
                    foreign = fast_forward.RADAR_MAC_ALTERNATE if radar_name == 'RADAR_LAYOUTS' else fast_forward.RADAR_LAYOUTS
                    with patch.object(fast_forward, radar_name, foreign):
                        self.assertNotIn('radar', fast_forward.extract_fast_forward(mach, arrival))

    def test_every_span_endpoint_must_match(self):
        for name, rows in self.variants():
            mach, arrival, layouts = fixture(rows)
            origin = arrival['provenance']['actor']['offset'] - mach.slice_offset
            with patch.object(fast_forward, name, layouts):
                for key, (delta, size, _, _) in layouts.items():
                    for endpoint in (0, size - 1):
                        with self.subTest(layout=name, span=key, endpoint=endpoint):
                            changed = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[origin + delta + endpoint] ^= 1
                            changed.data = bytes(raw)
                            self.assertEqual(fast_forward.extract_fast_forward(changed, arrival), {})

    def test_no_foreign_hybrid_or_ambiguous_variant(self):
        for name, rows in self.variants():
            other_name = 'MAC_ALTERNATE' if name == 'LAYOUTS' else 'LAYOUTS'
            _, _, foreign = fixture(getattr(fast_forward, other_name))
            mach, arrival, layouts = fixture(rows)
            hybrid = copy.deepcopy(layouts)
            hybrid['frame_cancel_and_scale'] = foreign['frame_cancel_and_scale']
            for rejected in (foreign, hybrid):
                with self.subTest(layout=name, kind='foreign_or_hybrid'):
                    with patch.object(fast_forward, name, rejected):
                        self.assertEqual(fast_forward.extract_fast_forward(mach, arrival), {})
            with patch.object(fast_forward, name, layouts), patch.object(fast_forward, other_name, layouts):
                self.assertEqual(fast_forward.extract_fast_forward(mach, arrival), {})

    def test_validated_arrival_anchor_and_architecture_are_required(self):
        mach, arrival, layouts = fixture(fast_forward.LAYOUTS)
        invalid = [None, {}, {'provenance': None}, {'provenance': {}}, {'provenance': {'actor': {}}}]
        for field, bad_values in [('bytes', [314, 316, True, 315.0, '315']),
                                  ('offset', [None, True, -1, 0.0, '0', len(mach.data) + mach.slice_offset])]:
            for value in bad_values:
                item = copy.deepcopy(arrival)
                item['provenance']['actor'][field] = value
                invalid.append(item)
        shifted = copy.deepcopy(arrival)
        shifted['provenance']['actor']['offset'] += 1
        invalid.append(shifted)
        with patch.object(fast_forward, 'LAYOUTS', layouts):
            for item in invalid:
                with self.subTest(arrival=item):
                    self.assertEqual(fast_forward.extract_fast_forward(mach, item), {})
            for arch in ('armv7', 'arm64', '', None):
                changed = copy.copy(mach)
                changed.architecture = arch
                self.assertEqual(fast_forward.extract_fast_forward(changed, arrival), {})

    def test_actual_arrival_bytes_and_section_are_required(self):
        mach, arrival, layouts = fixture(fast_forward.LAYOUTS)
        with patch.object(fast_forward, 'LAYOUTS', layouts):
            changed = copy.deepcopy(mach)
            changed.sections[0]['name'] = b'__const'
            self.assertEqual(fast_forward.extract_fast_forward(changed, arrival), {})
            changed = copy.copy(mach)
            raw = bytearray(mach.data)
            offset = arrival['provenance']['actor']['offset'] - mach.slice_offset
            raw[offset:offset + 315] = bytes(315)
            changed.data = bytes(raw)
            self.assertEqual(fast_forward.extract_fast_forward(changed, arrival), {})

    def test_bounded_sections_truncation_and_file_offsets(self):
        mach, arrival, layouts = fixture(fast_forward.LAYOUTS)
        with patch.object(fast_forward, 'LAYOUTS', layouts):
            changed = copy.copy(mach)
            changed.data = mach.data[:-17]
            self.assertEqual(fast_forward.extract_fast_forward(changed, arrival), {})
            changed = copy.deepcopy(mach)
            changed.sections[0]['length'] -= 1
            self.assertEqual(fast_forward.extract_fast_forward(changed, arrival), {})
            changed = copy.deepcopy(mach)
            changed.sections[0]['offset'] += 1
            self.assertEqual(fast_forward.extract_fast_forward(changed, arrival), {})

    def test_unrelated_bytes_are_not_an_archive_fingerprint(self):
        mach, arrival, layouts = fixture(fast_forward.LAYOUTS)
        raw = bytearray(mach.data)
        raw[0] ^= 255
        mach.data = bytes(raw)
        with patch.object(fast_forward, 'LAYOUTS', layouts):
            self.assertTrue(fast_forward.extract_fast_forward(mach, arrival))

    def test_native_constants_and_span_variants_match_import_contract(self):
        path = Path(__file__).resolve().parents[1] / 'game/src/content/fast_forward_definitions.gd'
        text = path.read_text()
        decoder = json.JSONDecoder()
        for native_name, expected in [('VALUES', fast_forward.VALUES),
                                      ('SPANS', {key: row[:2] for key, row in fast_forward.LAYOUTS.items()}),
                                      ('MAC_ALTERNATE', {key: row[:2] for key, row in fast_forward.MAC_ALTERNATE.items()}),
                                      ('RADAR_VALUES', fast_forward.RADAR_VALUES),
                                      ('RADAR_SPANS', {key: row[:2] for key, row in fast_forward.RADAR_LAYOUTS.items()}),
                                      ('RADAR_MAC_ALTERNATE', {key: row[:2] for key, row in fast_forward.RADAR_MAC_ALTERNATE.items()})]:
            declared, _ = decoder.raw_decode(text.split('const ' + native_name + ' := ', 1)[1])
            self.assertEqual(declared, expected)

    def test_timing_edges_camera_cache_and_scope_are_explicit(self):
        values = fast_forward.VALUES
        self.assertEqual(values['input']['delivery'], 'hold_until_release')
        self.assertFalse(values['input']['automatic_reset_rearms_held_key'])
        self.assertEqual(values['timing']['simulation_frame_max_ms'], 750)
        self.assertEqual(values['timing']['real_frame_max_ms'], 150)
        self.assertEqual(values['timing']['simulation_passes'], 1)
        self.assertEqual(values['timing']['fast_camera_passes'], 5)
        self.assertFalse(values['activation']['training_waypoint_grants_eligibility'])
        self.assertEqual(values['cancellation']['near_target_sample'], 'previous_player_update')
        self.assertEqual(values['camera']['input_policy'], 'relative_mouse_capture')
        self.assertTrue(values['camera']['fixed_refresh_preserves_cache'])
        self.assertTrue(values['camera']['fast_suppresses_normal_refresh'])
        self.assertFalse(values['supported_scope']['later_approach'])
        self.assertFalse(values['supported_scope']['slow_motion_combination'])
        self.assertNotIn('provenance', values)
        self.assertNotIn('default_key', values['input'])


if __name__ == '__main__':
    unittest.main()
