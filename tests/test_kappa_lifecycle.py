"""Fighter combat lifecycle declarations fail closed when any source proof differs."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from declaration_fixture import verify_hashed_declarations
from gof2_content import kappa_lifecycle as reader


class KappaLifecycleTests(unittest.TestCase):
    def test_proofs_and_relocation(self):
        verify_hashed_declarations(self, reader, reader.extract_kappa_lifecycle, 'systems')
