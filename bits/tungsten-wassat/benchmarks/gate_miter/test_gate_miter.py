import tempfile
import unittest
from pathlib import Path

from run import recognize, schedule


def and_rows(y, a, b):
    return [(y, -a, -b), (-y, a), (-y, b)]


def xor_rows(y, a, b):
    return [(-y, -a, -b), (-y, a, b), (y, -a, b), (y, a, -b)]


class GateMiterTest(unittest.TestCase):
    def recognize_rows(self, rows):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.cnf'
            with path.open('w') as f:
                print('p cnf', 8, len(rows), file=f)
                for row in rows:
                    print(*row, 0, file=f)
            return recognize(path, max_gates=32)

    def circuit(self, root=1, assertion=1):
        # Equivalent duplicated subcircuits feed the two comparator inputs.
        return (xor_rows(root, 2, 3) + and_rows(2, 4, 8) + and_rows(3, 5, 8)
                + and_rows(4, 6, 7) + and_rows(5, 7, 6) + [(assertion,)])

    def test_comparator_polarity(self):
        for root, assertion in [(1, 1), (-1, -1)]:
            _, _, gates, units, asserted = self.recognize_rows(self.circuit(root, assertion))
            queries = schedule(gates, units, asserted)
            self.assertIn((5, 4), queries[:-1])
            self.assertEqual(queries[-1], (2, 3))
            self.assertIsNone(schedule(gates, [-asserted], -asserted))

    def test_missing_gate_clause(self):
        rows = self.circuit()
        del rows[-2]
        self.assertIsNone(self.recognize_rows(rows))

    def test_only_same_side_candidates(self):
        rows = xor_rows(1, 2, 3) + and_rows(2, 6, 7) + and_rows(3, 7, 6) + [(1,)]
        _, _, gates, units, asserted = self.recognize_rows(rows)
        self.assertIsNone(schedule(gates, units, asserted))

    def test_cyclic_definition(self):
        rows = xor_rows(1, 2, 3) + and_rows(2, 4, 8) + and_rows(4, 2, 8) + [(1,)]
        _, _, gates, units, asserted = self.recognize_rows(rows)
        self.assertIsNone(schedule(gates, units, asserted))


if __name__ == '__main__':
    unittest.main()
