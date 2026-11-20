import tempfile
import unittest
from pathlib import Path

from check_circuit import read_certificate, verify


class CircuitCertificateTest(unittest.TestCase):
    # Variables 2 and 3 copy input 1. Output 4 asserts that they differ.
    clauses = [
        [-2, 1], [2, -1], [-3, 1], [3, -1],
        [-4, 2, 3], [-4, -2, -3], [4],
    ]
    proof = """wassat-circuit 1
inputs 1
assert 4
gate 2 2 1 1 1 2
gate 3 2 1 1 3 4
gate 4 6 2 2 3 5 6
"""

    def replay(self, proof, clauses):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / "cert"
            p.write_text(proof)
            verify(*read_certificate(p, 4, clauses))

    def test_partial_output_relation(self):
        self.replay(self.proof, self.clauses)

    def test_bad_witnesses(self):
        for old, new in [
            ("gate 2 2", "gate 2 1"),
            ("1 1 1 2", "1 1 1"),
            ("assert 4", "assert -4"),
            (" 5 6", " 5 8"),
            ("gate 3 2 1 1", "gate 3 2 1 4"),
        ]:
            with self.subTest(new=new), self.assertRaises(ValueError):
                self.replay(self.proof.replace(old, new), self.clauses)

    def test_permitting_a_real_assignment(self):
        weakened = self.clauses.copy()
        weakened[5] = [-4, 2, -3]
        # This is the correct local output table for the changed CNF.
        # The global check must reject it since input 1=true satisfies it.
        with self.assertRaisesRegex(ValueError, "an assignment permits"):
            self.replay(self.proof.replace("gate 4 6", "gate 4 10"), weakened)

    def test_low_and_high_input_coverage(self):
        # A conjunction on 17 inputs has a single accepting assignment.
        # Whichever 16 inputs are packed, the high loop must check both values.
        gates = [(18, (1, 2), 8)]
        for v in range(3, 18):
            gates.append((v + 16, (v + 15, v), 8))
        with self.assertRaisesRegex(ValueError, "an assignment permits"):
            verify(list(range(1, 18)), {}, gates, 33)
        verify(list(range(1, 18)), {}, gates + [(34, (33,), 0)], 34)


if __name__ == "__main__":
    unittest.main()
