"""Optional contact declarations require complete, source-specific proof."""
import copy
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import persistent_contacts as reader


class PersistentContactTests(unittest.TestCase):
    def test_relocated_variants_are_detached_and_every_span_is_required(self):
        for name in ('LAYOUTS', 'MAC_ALTERNATE'):
            for relocation in (0, 0x800000):
                mach, arrival, layouts = declaration_fixture(getattr(reader, name), relocation)
                with patch.object(reader, name, layouts):
                    result = reader.extract_persistent_contacts(mach, arrival, reader.ORDINARY_VALUES)
                    self.assertEqual({k: v for k, v in result.items() if k != 'provenance'}, reader.VALUES)
                    self.assertEqual(set(result['provenance']), set(layouts))
                    result['supported_contact_ids'].clear()
                    result['provenance'].clear()
                    self.assertEqual(reader.extract_persistent_contacts(mach, arrival, reader.ORDINARY_VALUES)['supported_contact_ids'], [5])
                    for key, (delta, size, _, _) in layouts.items():
                        for endpoint in (0, size - 1):
                            damaged = copy.copy(mach)
                            raw = bytearray(mach.data)
                            raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta + endpoint] ^= 255
                            damaged.data = bytes(raw)
                            self.assertEqual(reader.extract_persistent_contacts(damaged, arrival, reader.ORDINARY_VALUES), {}, (name, key, endpoint))
                    missing = copy.copy(mach);missing.sections = []
                    self.assertEqual(reader.extract_persistent_contacts(missing, arrival, reader.ORDINARY_VALUES), {})

    def test_unrelated_generation_missing_anchor_and_ambiguity_refuse(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts):
            for ordinary in ({}, {'scope': reader.ORDINARY_VALUES['scope']}):
                self.assertEqual(reader.extract_persistent_contacts(mach, arrival, ordinary), {})
            for invalid in ({}, {'provenance': {}}, {'provenance': {'actor': {'bytes': 314}}}):
                self.assertEqual(reader.extract_persistent_contacts(mach, invalid, reader.ORDINARY_VALUES), {})
            changed = copy.copy(mach);changed.architecture = 'armv7'
            self.assertEqual(reader.extract_persistent_contacts(changed, arrival, reader.ORDINARY_VALUES), {})
        with patch.object(reader, 'LAYOUTS', layouts), patch.object(reader, 'MAC_ALTERNATE', layouts):
            self.assertEqual(reader.extract_persistent_contacts(mach, arrival, reader.ORDINARY_VALUES), {})

    def test_native_declarations_match_and_keep_services_separate(self):
        native = (Path(__file__).resolve().parents[1] / 'game/src/content/persistent_contact_definitions.gd').read_text()
        for name, value in [('VALUES', reader.VALUES), ('SPANS', {k: v[:2] for k, v in reader.LAYOUTS.items()}),
                            ('MAC_SPANS', {k: v[:2] for k, v in reader.MAC_ALTERNATE.items()})]:
            found = re.findall(r'^const ' + name + r' = (.+)$', native, re.MULTILINE)
            self.assertEqual(len(found), 1, name)
            self.assertEqual(json.loads(found[0]), value, name)
        self.assertEqual(reader.VALUES['supported_contact_ids'], [5])
        self.assertEqual(reader.VALUES['fields']['blueprint'], 6)
        self.assertNotIn('purchase', reader.VALUES)
        self.assertNotIn('reward', reader.VALUES)
        self.assertTrue(reader.VALUES['hostile_replacement_requires_generated'])


if __name__ == '__main__':
    unittest.main()
