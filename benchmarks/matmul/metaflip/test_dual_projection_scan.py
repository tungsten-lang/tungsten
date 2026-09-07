import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from dual_projection_scan import DualProjectionCache, dual_maps
from projection_composition_scan import text
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import naive, expansion
from verify_dual_projections import project_dual_grid, verify


class DualProjectionTest(unittest.TestCase):
    def test_complete_small_kernel_pairs_and_tensor_identities(self):
        shape = (3, 3, 3)
        for seed in range(3):
            terms = walked(shape, seed)
            self.assertEqual(expansion(terms), expansion(naive(shape)))
            cache = DualProjectionCache(shape, terms)
            for dimension in range(3):
                for u in range(1, 8):
                    for v in range(1, 8):
                        if not (u & v).bit_count() % 2:
                            continue
                        kept, left, right = dual_maps(3, u, v)
                        self.assertTrue(all((m & n).bit_count() % 2 == (i == j)
                            for i, m in enumerate(left) for j, n in enumerate(right)))
                        self.assertTrue(all((m & u).bit_count() % 2 == 0 for m in left))
                        self.assertTrue(all((n & v).bit_count() % 2 == 0 for n in right))
                        keep = [[0, 1, 2], [0, 1, 2], [0, 1, 2]]
                        keep[dimension] = list(kept)
                        # Exercise simultaneous ordinary cropping of another axis.
                        keep[(dimension+1) % 3] = [0, 2]
                        row = dict(parent_shape=shape, keep=keep, dual=dict(dimension=dimension, u=u, v=v))
                        child = cache.restrict(keep, dimension, u, v)
                        self.assertEqual(child, project_dual_grid(row, terms))
                        self.assertEqual(expansion(child), expansion(naive(tuple(map(len, keep)))))

    def test_coordinate_special_case(self):
        cache = DualProjectionCache((3, 3, 3), walked((3, 3, 3), 13))
        for dimension in range(3):
            for pivot in range(3):
                keep = [[0, 1, 2] for _ in range(3)]
                keep[dimension].remove(pivot)
                self.assertEqual(cache.base.restrict(keep, True), cache.restrict(keep, dimension, 1 << pivot, 1 << pivot))

    def test_invalid_and_altered_valid_metadata(self):
        for args in ((3, 0, 1), (3, 1, 2), (3, 8, 1), (3, True, 1), (1, 1, 1)):
            with self.assertRaises(ValueError):
                dual_maps(*args)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shape = (3, 3, 3)
            terms = walked(shape, 12)
            cache = DualProjectionCache(shape, terms)
            keep = [[1, 2], [0, 1, 2], [0, 1, 2]]
            children = {v: cache.restrict(keep, 0, 1, v) for v in (1, 3, 5, 7)}
            old, changed = next((a, b) for a in children for b in children if children[a] != children[b])
            source, child = text(terms), text(children[old])
            (root / 'parent.txt').write_bytes(source)
            (root / 'child.txt').write_bytes(child)
            row = dict(parent_shape=shape, shape=[2, 3, 3], keep=keep,
                parent_path='parent.txt', parent_sha256=hashlib.sha256(source).hexdigest(),
                path='child.txt', sha256=hashlib.sha256(child).hexdigest(),
                rank=len(children[old]), baseline=len(children[old]), improves_local=False,
                dual=dict(dimension=0, u=1, v=old))
            report = dict(complete=True, field='GF(2)', record_claim=False,
                projection_kind='canonical_dual_kernel', selected_parents=1,
                parents_done=1, rows=[dict(views=1)], views=1, outputs=[row])
            (root / 'report.json').write_text(json.dumps(report))
            self.assertEqual(verify(root, 1)['tensors'], 2)
            for bad in (changed, 0, 2, True):
                row['dual']['v'] = bad
                (root / 'report.json').write_text(json.dumps(report))
                with self.assertRaises(AssertionError):
                    verify(root, 1)


if __name__ == '__main__':
    unittest.main()
