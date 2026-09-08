import hashlib
import json
from pathlib import Path
import random
import tempfile
import unittest

from dual_projection_scan import DualProjectionCache, WordMap, dual_maps
from projection_composition_scan import text
from test_fold_projection_scan import walked
from test_projection_variant_portfolio import naive, expansion
from verify_dual_projections import project_dual_grid, verify


class DualProjectionTest(unittest.TestCase):
    def test_dense_and_lazy_word_maps_match_direct_grid(self):
        rng=random.Random(57)
        for n in (3,8,9,32):
            other=3; words=[rng.randrange(1 << (n*other)) for _ in range(8)]
            ids=(0,1,2,3,4,5,6,7,0,1,0)
            rows=[rng.randrange(1 << n) for _ in range(n-1)]
            for row_coordinate in (False,True):
                mapper=WordMap(ids,words,n,other,row_coordinate)
                expected=[]
                for index in ids:
                    word=words[index]; value=0
                    for i,row in enumerate(rows):
                        for j in range(other):
                            parity=sum(((row >> k)&1)*((word >> (k*other+j if row_coordinate else j*n+k))&1)
                                       for k in range(n))%2
                            value |= parity << (i*other+j if row_coordinate else j*len(rows)+i)
                    expected.append(value)
                self.assertEqual(mapper.transform(rows),tuple(expected))
                for coordinates in (tuple(range(n-1)),tuple(reversed(range(1,n)))):
                    self.assertEqual(mapper.transform(rows,coordinates),tuple(expected))
                    self.assertEqual(mapper.transform(rows,coordinates),tuple(expected))
                if row_coordinate:
                    self.assertEqual(mapper.combinations is None,n>8)
                    self.assertEqual(len(mapper.row_chunks),len(words))
                else:
                    self.assertEqual(mapper.needed_chunks is None,n<=8)
                    if n>8:self.assertLessEqual(len(mapper.needed_chunks),len(words)*other)

    def test_large_sparse_duals_on_all_shared_dimensions(self):
        for dimension in range(3):
            shape=[2,2,2]; shape[dimension]=32
            terms=walked(shape,19); cache=DualProjectionCache(shape,terms)
            for u,v in (((1<<31)|1,(1<<31)|8),
                        (1<<31,(1<<31)|(1<<2)|(1<<13)),
                        (1|(1<<10),1|(1<<17))):
                keep=[list(range(n)) for n in shape]
                keep[dimension]=list(dual_maps(32,u,v)[0])
                row=dict(parent_shape=shape,keep=keep,dual=dict(dimension=dimension,u=u,v=v))
                child=cache.restrict(keep,dimension,u,v)
                self.assertEqual(child,project_dual_grid(row,terms))
                self.assertEqual(expansion(child),expansion(naive(tuple(map(len,keep)))))

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
