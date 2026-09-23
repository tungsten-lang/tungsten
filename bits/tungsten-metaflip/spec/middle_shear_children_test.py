#!/usr/bin/env python3
"""Focused exact checks for middle-basis shear and projected children."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import screen_middle_shear_children as shear
import screen_top_two_projection_children as top
import screen_two_pass_basis_children as two_pass


class MiddleShearChildrenTest(unittest.TestCase):
    def test_descendant_baseline_includes_checked_rank(self):
        self.assertEqual(two_pass.baseline_seeds('composed-descendants')[(16, 23, 31)],
                         6376)

    def test_all_elementary_shears_of_naive_tensor(self):
        shape = 2, 3, 2
        n, m, p = shape
        terms = [(1 << (i*m+k), 1 << (k*p+j), 1 << (i*p+j))
                 for i in range(n) for k in range(m) for j in range(p)]
        top.exact(shape, terms)
        for a in range(m):
            for mask in range(1 << m):
                if (mask >> a) & 1:
                    continue
                with self.subTest(shear=(a, mask)):
                    transformed = shear.shear_middle_mask(shape, terms, a, mask)
                    top.exact(shape, transformed)
                    target, raw, cleaned, history = shear.child_mask(
                        shape, terms, a, mask, independent=True)
                    self.assertEqual(target, (2, 2, 2))
                    self.assertGreaterEqual(len(raw), len(cleaned))
                    self.assertIsInstance(history, list)


if __name__ == '__main__':
    unittest.main()
