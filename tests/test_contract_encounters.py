"""Contract construction is an optional, independently verified Mac capability."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import declaration_fixture
from gof2_content import contract_encounters as reader


class ContractEncounterTests(unittest.TestCase):
    def test_relocated_declarations_have_detached_data(self):
        for shift in (0, 0x800000):
            mach, arrival, layouts = declaration_fixture(reader.LAYOUTS, shift)
            with patch.object(reader, 'LAYOUTS', layouts):
                values, proof = reader.extract_contract_encounters(mach, arrival)
                self.assertEqual(values, reader.VALUES)
                self.assertEqual(len(proof), len(layouts))
                for key, span in layouts.items():
                    self.assertEqual(proof[key]['offset'], arrival['provenance']['actor']['offset'] + span[0])
                values['junk']['model_ids'].clear()
                self.assertEqual(len(reader.extract_contract_encounters(mach, arrival)[0]['junk']['model_ids']), 3)

    def test_changed_source_cannot_enable_any_encounter(self):
        mach, arrival, layouts = declaration_fixture(reader.LAYOUTS)
        with patch.object(reader, 'LAYOUTS', layouts):
            for key, (delta, _, _, _) in layouts.items():
                changed = copy.copy(mach)
                raw = bytearray(mach.data)
                raw[arrival['provenance']['actor']['offset'] - mach.slice_offset + delta] ^= 255
                changed.data = bytes(raw)
                self.assertEqual(reader.extract_contract_encounters(changed, arrival), ({}, {}), key)

    def test_other_architecture_stays_unsupported(self):
        mach, arrival, _ = declaration_fixture(reader.LAYOUTS)
        mach.architecture = 'armv7'
        self.assertEqual(reader.extract_contract_encounters(mach, arrival), ({}, {}))
