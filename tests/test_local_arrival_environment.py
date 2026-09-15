"""Original planet/arrival declarations require every proof and detached values."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from declaration_fixture import verify_hashed_declarations
from gof2_content import local_arrival_environment as reader

class LocalArrivalEnvironmentTests(unittest.TestCase):
    def test_proofs_and_relocation(self):
        verify_hashed_declarations(self,reader,reader.extract_local_arrival_environment,'arrival')
