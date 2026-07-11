import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from bench_decomp import naive_scheme, verify  # noqa: E402
from mitm_surgery import (  # noqa: E402
    candidate_terms,
    find_xor_decomposition,
    guided_subsets,
    search_scheme,
    tensor_xor,
    xor_fingerprint,
)


class MitmSurgeryTest(unittest.TestCase):
    def test_fingerprint_is_linear(self):
        left = (1 << 513) | (1 << 129) | 7
        right = (1 << 777) | (1 << 129) | 11
        self.assertEqual(
            xor_fingerprint(left) ^ xor_fingerprint(right),
            xor_fingerprint(left ^ right),
        )

    def test_four_way_xor_join_recovers_planted_terms(self):
        terms = [(1, 1, 1), (2, 2, 2), (4, 4, 4), (8, 8, 8),
                 (3, 1, 1), (1, 3, 1)]
        target = tensor_xor(terms[:4], 4, 4, 4)
        found = find_xor_decomposition(target, terms, 4, 4, 4, 4)
        self.assertIsNotNone(found)
        self.assertEqual(target, tensor_xor(found, 4, 4, 4))

    def test_exact_split_scheme_is_repaired(self):
        base = naive_scheme(2, 2, 2)
        original = base[0]
        part = 3
        left = (part, original[1], original[2])
        right = (original[0] ^ part, original[1], original[2])
        escaped = sorted(base[1:] + [left, right])
        self.assertEqual(9, len(escaped))
        self.assertTrue(verify(escaped, 2, 2, 2))
        subset = (escaped.index(left), escaped.index(right))
        with tempfile.NamedTemporaryFile("w", suffix=".txt") as stream:
            stream.write(f"{len(escaped)}\n")
            for term in escaped:
                stream.write("%d %d %d\n" % term)
            stream.flush()
            repaired = search_scheme(
                stream.name, 2, 2, 2, k=2, subset_count=1,
                pool=64, nearby=0, explicit_subset=subset, log=lambda *_: None)
        self.assertIsNotNone(repaired)
        self.assertEqual(8, len(repaired))
        self.assertTrue(verify(repaired, 2, 2, 2))

    def test_candidate_pool_and_guided_subsets_are_deterministic(self):
        terms = naive_scheme(2, 2, 2)
        subset = (0, 1, 2)
        first = candidate_terms(terms, subset, 4, 4, 4, limit=50, nearby=1)
        second = candidate_terms(terms, subset, 4, 4, 4, limit=50, nearby=1)
        self.assertEqual(first, second)
        self.assertEqual(guided_subsets(terms, 4, 5),
                         guided_subsets(terms, 4, 5))

    def test_search_rejects_factor_bits_outside_declared_format(self):
        terms = naive_scheme(2, 2, 2)
        u, v, w = terms[0]
        terms[0] = (u | (1 << 4), v, w)
        # bench_decomp.verify intentionally ignores bits outside the format;
        # the surgery boundary must reject them before tensor expansion.
        self.assertTrue(verify(terms, 2, 2, 2))
        with tempfile.NamedTemporaryFile("w", suffix=".txt") as stream:
            stream.write(f"{len(terms)}\n")
            for term in terms:
                stream.write("%d %d %d\n" % term)
            stream.flush()
            with self.assertRaisesRegex(ValueError, "out-of-range"):
                search_scheme(stream.name, 2, 2, 2, subset_count=1,
                              log=lambda *_: None)


if __name__ == "__main__":
    unittest.main()
