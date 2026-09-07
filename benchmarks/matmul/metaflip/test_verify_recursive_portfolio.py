import tempfile
from pathlib import Path
import unittest

import verify_recursive_portfolio as v


class RecursivePortfolioTest(unittest.TestCase):
    def test_naive_and_dimension_one(self):
        solve = v.solver({})
        self.assertEqual(120, solve((4, 5, 6)))
        self.assertEqual(30, solve((1, 5, 6)))

    def test_block_and_kronecker_recursion(self):
        old = v.solver({(2, 2, 2): 7})
        new = v.solver({(2, 2, 2): 7, (4, 4, 4): 47})
        self.assertEqual(49, old((4, 4, 4)))
        self.assertEqual(329, new((8, 8, 8)))
        self.assertEqual(63, new((4, 4, 5)))

    def test_catalog_filters_do_not_admit_other_fields(self):
        base = dict(verified=True, fields=['F2'], format=[4, 4, 4], rank=47)
        index = dict(schemes=[base, dict(base, rank=1, commutative=True),
                             dict(base, rank=2, fields_not=['F2']),
                             dict(base, rank=3, scheme_type='non_bilinear'),
                             dict(base, rank=4, verified=False), dict(base, rank=5, fields=['Q'])])
        self.assertEqual({(4, 4, 4): 47}, v.catalog_minima(index))

    def test_snapshot_paths_stay_inside_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(root.resolve() / 'a', v.safe(root, 'a'))
            with self.assertRaises(ValueError):
                v.safe(root, '../outside')


if __name__ == '__main__':
    unittest.main()
