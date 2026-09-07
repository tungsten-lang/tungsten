import copy
import hashlib
from pathlib import Path
import tempfile
import unittest

import verify_block_composition_records as tensor
from verify_composition_targets import block, kronecker, naive, replay
from verify_representation_portfolio import identity, parse_terms


class CompositionTargetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        name = 'matmul_2x2_rank7_strassen_gf2.txt'
        fixture = Path(__file__).resolve().parent/'fixtures'/name
        if not fixture.exists():
            fixture = Path(__file__).resolve().parents[3]/'bits/tungsten-metaflip/lib/metaflip/seeds/gf2'/name
        raw = fixture.read_bytes()
        cls.terms = parse_terms(raw, 7)
        cls.digest = hashlib.sha256(raw).hexdigest()
        cls.source_id = identity((2, 2, 2), cls.terms)
        cls.seeds = {cls.source_id: ((2, 2, 2), cls.digest, cls.terms)}
        cls.leaf = dict(shape=[2, 2, 2], canonical_shape=[2, 2, 2], rank=7, kind='seed',
                        source_shape=[2, 2, 2], source_sha256=cls.digest, source_id=cls.source_id)
        cls.plan = dict(shape=[4, 4, 4], canonical_shape=[4, 4, 4], rank=49, kind='product',
                        left=cls.leaf, right=cls.leaf)

    def tensor_check(self, shape, terms):
        with tempfile.TemporaryDirectory() as d:
            body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
            (Path(d)/'t.txt').write_bytes(body)
            record = tensor.Record('x'.join(map(str, shape)), shape, len(terms), 't.txt',
                                   hashlib.sha256(body).hexdigest())
            return tensor._verify_one((Path(d), record))

    @staticmethod
    def costs(shape):
        return {(2, 2, 2): 7, (4, 4, 4): 49}[shape]

    def test_product_ancestry_and_tensor(self):
        terms = replay(self.plan, self.seeds, self.costs)
        self.assertEqual(49, self.tensor_check((4, 4, 4), terms).terms)
        self.assertEqual(terms, kronecker((2, 2, 2), self.terms, (2, 2, 2), self.terms))

    def test_rectangular_product(self):
        terms = kronecker((2, 2, 2), self.terms, (2, 1, 3), naive((2, 1, 3)))
        self.assertEqual(42, self.tensor_check((4, 2, 6), terms).terms)

    def test_block_offset(self):
        terms = block((2, 2, 2), self.terms, (2, 3, 2), (0, 0, 0))
        terms += block((2, 1, 2), naive((2, 1, 2)), (2, 3, 2), (0, 2, 0))
        self.assertEqual(11, self.tensor_check((2, 3, 2), terms).terms)

    def test_permuted_split(self):
        leaf = dict(shape=[2, 1, 2], canonical_shape=[1, 2, 2], rank=4, kind='naive')
        plan = dict(shape=[3, 2, 2], canonical_shape=[2, 2, 3], rank=11, kind='split', axis=2,
                    left=self.leaf, right=dict(leaf, shape=[2, 2, 1]))
        costs = lambda s: {(2, 2, 2): 7, (1, 2, 2): 4, (2, 2, 3): 11}[s]
        terms = replay(plan, self.seeds, costs)
        self.assertEqual(11, self.tensor_check((3, 2, 2), terms).terms)

    def test_corrupt_plan_rejected(self):
        for field, value in [('rank', 48), ('canonical_shape', [4, 4, 5]), ('kind', 'unknown')]:
            plan = copy.deepcopy(self.plan)
            plan[field] = value
            with self.assertRaises((AssertionError, KeyError)):
                replay(plan, self.seeds, self.costs)

    def test_corrupt_source_rejected(self):
        plan = copy.deepcopy(self.plan)
        plan['left']['source_sha256'] = '0'*64
        with self.assertRaises(AssertionError):
            replay(plan, self.seeds, self.costs)

    def test_term_mutation_rejected(self):
        terms = replay(self.plan, self.seeds, self.costs)
        terms[0] = (terms[0][0] ^ (1 << 15), *terms[0][1:])
        with self.assertRaises((ValueError, AssertionError)):
            self.tensor_check((4, 4, 4), terms)


if __name__ == '__main__':
    unittest.main()
