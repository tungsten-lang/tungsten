from __future__ import annotations

import itertools
import random
import tempfile
import unittest
from pathlib import Path

from audit_225_union_subset_sat import column, expected_counter, read_model, target


ROOT = Path(__file__).resolve().parent


def clause_value(row: str, assignment: dict[int, bool]) -> bool:
    literals = [int(token) for token in row.split() if token != "0"]
    return any(assignment[abs(literal)] == (literal > 0) for literal in literals)


class UnionSubsetSat225Test(unittest.TestCase):
    def test_five_production_doors_reconstruct_exactly(self) -> None:
        paths = [
            "matmul_2x2x5_rank18_d84_gf2.txt",
            "matmul_2x2x5_rank18_d88_gf2.txt",
            "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt",
            "matmul_2x2x5_rank18_d84_block_splice_gf2.txt",
            "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt",
        ]
        for name in paths:
            terms = []
            for raw in (ROOT / name).read_text().splitlines():
                fields = raw.split()
                if len(fields) == 4 and fields[0] == "R":
                    terms.append(tuple(map(int, fields[1:4])))
                elif len(fields) == 3:
                    terms.append(tuple(map(int, fields)))
            self.assertEqual(len(terms), 18, name)
            made = 0
            for term in terms:
                made ^= column(term)
            self.assertEqual(made, target(), name)

    def test_sinz_counter_is_at_most_not_exact(self) -> None:
        n, k = 5, 2
        clauses = expected_counter(n, k)
        auxiliary = list(range(n + 1, n + 1 + (n - 1) * k))
        for primary_bits in itertools.product((False, True), repeat=n):
            satisfiable = False
            for auxiliary_bits in itertools.product((False, True), repeat=len(auxiliary)):
                assignment = {i + 1: primary_bits[i] for i in range(n)}
                assignment.update(dict(zip(auxiliary, auxiliary_bits)))
                if all(clause_value(row, assignment) for row in clauses):
                    satisfiable = True
                    break
            self.assertEqual(satisfiable, sum(primary_bits) <= k, primary_bits)

    def test_solver_status_is_classified_exactly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model"
            path.write_text("s INDETERMINATE\nc timeout\n")
            self.assertEqual(read_model(path), ("indeterminate", None))
            path.write_text("s UNSATISFIABLE\n")
            self.assertEqual(read_model(path), ("unsat-reported", None))
            path.write_text("s SATISFIABLE\nv 1 -2 0\n")
            self.assertEqual(read_model(path), ("sat", {1: True, 2: False}))

    def test_odd_rank18_triple_filter_is_complete(self) -> None:
        # A planted weight-16 triple meets the boundary exactly:
        # sum(pair intersections) - 2*triple intersection = 19.
        core = set(range(10))
        ab = set(range(10, 13))
        ac = set(range(13, 16))
        bc = set(range(16, 19))
        a = core | ab | ac | {19, 20}
        b = core | ab | bc | {21, 22}
        c = core | ac | bc | {23, 24}
        self._check_triple(a, b, c, expect_low=True)

        rng = random.Random(22517001)
        for _ in range(2_000):
            sets = [set(rng.sample(range(96), 18)) for _ in range(3)]
            self._check_triple(*sets, expect_low=False)

    def _check_triple(self, a: set[int], b: set[int], c: set[int], expect_low: bool) -> None:
        self.assertEqual((len(a), len(b), len(c)), (18, 18, 18))
        weight = len(a ^ b ^ c)
        pair_sum = len(a & b) + len(a & c) + len(b & c)
        triple = len(a & b & c)
        self.assertEqual(weight, 54 - 2 * pair_sum + 4 * triple)
        self.assertEqual(weight % 2, 0)
        if expect_low:
            self.assertLessEqual(weight, 17)
        if weight <= 17:
            self.assertGreaterEqual(pair_sum - 2 * triple, 19)
            self.assertGreaterEqual(max(len(a & b), len(a & c), len(b & c)), 7)


if __name__ == "__main__":
    unittest.main()
