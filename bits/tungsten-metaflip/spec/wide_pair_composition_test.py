#!/usr/bin/env python3
"""Focused exact tests for the cold multiword pair constructor."""
from pathlib import Path
import sys
import unittest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import screen_top_two_projection_children as tensor  # noqa: E402
import wide_pair_composition as pair  # noqa: E402


def naive(shape):
    n, m, p = shape
    return [(1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k))
            for i in range(n) for j in range(m) for k in range(p)]


class WidePairCompositionTest(unittest.TestCase):
    def test_catalog_leaf_is_exact(self):
        leaf = pair.leaf_three()
        self.assertEqual(len(leaf), 15)
        tensor.exact((3, 2, 3), leaf)

    def test_every_shared_axis(self):
        controls = (((1, 1, 2), 0, (3, 3, 2)),
                    ((2, 1, 1), 1, (2, 3, 3)),
                    ((1, 2, 1), 2, (3, 2, 3)))
        for shape, axis, target in controls:
            with self.subTest(shape=shape, axis=axis):
                result = pair.compose_pairs(shape, naive(shape), axis)
                self.assertEqual(result[0], target)
                self.assertEqual((len(result[1]), result[2], result[3]),
                                 (15, 1, 15))
                tensor.exact(target, result[1])

    def test_rank_limit_and_equal_dimension_permutation(self):
        shape = (2, 2, 2)
        terms = naive(shape)
        for axis in range(3):
            rotated, values = pair.permute(shape, terms, pair.TO_OUTPUT_EDGE[axis])
            inverse = tuple(pair.TO_OUTPUT_EDGE[axis].index(i) for i in range(3))
            self.assertEqual(pair.permute(rotated, values, inverse),
                             (shape, terms))
        self.assertIsNone(pair.compose_pairs((1, 2, 1), naive((1, 2, 1)),
                                             2, max_rank=14))


if __name__ == "__main__":
    unittest.main()
