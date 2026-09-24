"""Equipped EMP declarations require the complete original source proof."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import verify_hashed_declarations
from gof2_content import secondary_ownership as reader


class SecondaryOwnershipTests(unittest.TestCase):
    def test_proofs_and_relocation(self):
        verify_hashed_declarations(self, reader, reader.extract_secondary_ownership, 'launch_audio')
