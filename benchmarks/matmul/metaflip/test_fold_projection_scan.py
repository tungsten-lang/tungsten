from collections import defaultdict
import hashlib
from itertools import combinations, product
import json
from pathlib import Path
import random
import tempfile
import unittest

from fold_projection_scan import EDGES, FoldCache
from verify_fold_projections import project_fold_grid, verify
from projection_composition_scan import text
from test_projection_variant_portfolio import naive, expansion


def walked(shape, seed):
    rng = random.Random(seed)
    terms = naive(shape)
    for _ in range(40):
        axis = rng.randrange(3)
        buckets = defaultdict(list)
        for i, term in enumerate(terms):
            buckets[term[axis]].append(i)
        pairs = [indices for indices in buckets.values() if len(indices) >= 2]
        if not pairs:
            continue
        i, j = rng.sample(rng.choice(pairs), 2)
        a, b = (axis+1) % 3, (axis+2) % 3
        left, right = list(terms[i]), list(terms[j])
        left[a] ^= right[a]
        right[b] ^= left[b]
        terms[i], terms[j] = tuple(left), tuple(right)
        parity = set()
        for term in terms:
            if all(term):
                if term in parity:
                    parity.remove(term)
                else:
                    parity.add(term)
        terms = sorted(parity)
    return terms


class FoldProjectionTest(unittest.TestCase):
    def test_full_file_audit_and_changed_fold_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            terms = walked((3, 3, 3), 12)
            keep = [[0, 1], [0, 1, 2], [0, 1, 2]]
            cache = FoldCache((3, 3, 3), terms)
            children = [cache.restrict(keep, 0, 0, mask) for mask in range(4)]
            original, changed = next((a, b) for a in range(4) for b in range(4) if children[a] != children[b])
            source, child = text(terms), text(children[original])
            (root / 'parent.txt').write_bytes(source)
            (root / 'child.txt').write_bytes(child)
            row = dict(parent_shape=[3, 3, 3], shape=[2, 3, 3], keep=keep,
                parent_path='parent.txt', parent_sha256=hashlib.sha256(source).hexdigest(),
                path='child.txt', sha256=hashlib.sha256(child).hexdigest(),
                rank=len(children[original]), baseline=len(children[original]), improves_local=False,
                fold=dict(dimension=0, factor=0, mask=original))
            report = dict(complete=True, field='GF(2)', record_claim=False,
                projection_kind='coordinate_or_one_sided_fold', selected_parents=1,
                parents_done=1, rows=[dict(views=1)], views=1, outputs=[row])
            (root / 'report.json').write_text(json.dumps(report))
            self.assertEqual(verify(root, 1)['tensors'], 2)
            row['fold']['mask'] = changed
            (root / 'report.json').write_text(json.dumps(report))
            with self.assertRaises(AssertionError):
                verify(root, 1)

    def test_all_fold_sides_and_masks_on_exact_small_tensors(self):
        shape = (2, 3, 2)
        for seed in range(4):
            terms = walked(shape, seed)
            self.assertEqual(expansion(terms), expansion(naive(shape)))
            cache = FoldCache(shape, terms)
            for dimension, extent in enumerate(shape):
                for keep_dim in combinations(range(extent), extent-1):
                    keep = [list(range(n)) for n in shape]
                    keep[dimension] = list(keep_dim)
                    expected = expansion(naive(tuple(map(len, keep))))
                    for factor in range(3):
                        if dimension not in EDGES[factor]:
                            continue
                        for mask in range(1 << len(keep_dim)):
                            row = dict(parent_shape=shape, keep=keep,
                                fold=dict(dimension=dimension, factor=factor, mask=mask))
                            fast = cache.restrict(keep, dimension, factor, mask)
                            self.assertEqual(fast, project_fold_grid(row, terms))
                            self.assertEqual(expansion(fast), expected)
                            self.assertEqual(len(fast), cache.restrict(keep, dimension, factor, mask, False))

    def test_additional_coordinate_restrictions_and_zero_mask(self):
        shape = (3, 3, 3)
        terms = walked(shape, 12)
        cache = FoldCache(shape, terms)
        keep = [[0, 2], [1], [0, 1]]
        for dimension in (0, 2):
            for factor in range(3):
                if dimension not in EDGES[factor]:
                    continue
                self.assertEqual(cache.base.restrict(keep, True), cache.restrict(keep, dimension, factor, 0))
                for mask in range(4):
                    child = cache.restrict(keep, dimension, factor, mask)
                    self.assertEqual(expansion(child), expansion(naive((2, 1, 2))))

    def test_rejects_invalid_fold_metadata(self):
        cache = FoldCache((2, 3, 2), naive((2, 3, 2)))
        keep = [[0, 1], [0, 1], [0, 1]]
        for dimension, factor, mask in ((0, 0, 0), (1, 2, 1), (1, 0, 4), (1, 0, True), (True, 0, 1)):
            with self.assertRaises(ValueError):
                cache.restrict(keep, dimension, factor, mask)
            row = dict(parent_shape=(2, 3, 2), keep=keep,
                fold=dict(dimension=dimension, factor=factor, mask=mask))
            with self.assertRaises(AssertionError):
                project_fold_grid(row, naive((2, 3, 2)))


if __name__ == '__main__':
    unittest.main()
