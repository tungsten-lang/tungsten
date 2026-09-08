import random
import unittest
from unittest.mock import patch
from verify_cofactor_mergers import cartesian_minimum, cofactor, materialize, mapped, orient, matrix_factors, compress_shared, replay_compression, compression_assessment, refactor_shared
from verify_matrix_pockets import signature


class CofactorChecks(unittest.TestCase):
    def test_all_pairs_match_direct_tensor_fusion(self):
        randomizer = random.Random(2026090672)
        for _ in range(1000):
            pools = [[cofactor([tuple(randomizer.randrange(1, 8) for _ in range(3))
                                for _ in range(randomizer.randrange(9))], 2)
                      for _ in range(randomizer.randrange(1, 9))] for _ in range(2)]
            expected = min((len(cofactor(materialize(a, 2)+materialize(b, 2), 2)), i, j)
                           for i, a in enumerate(pools[0]) for j, b in enumerate(pools[1]))
            self.assertEqual(cartesian_minimum(*pools)[0], expected)

    def test_fusion_is_not_just_parity(self):
        terms = [(1, 2, 4), (1, 2, 8)]
        fused = materialize(cofactor(terms, 2), 2)
        self.assertEqual(fused, [(1, 2, 12)])
        self.assertEqual(signature(terms), signature(fused))
        self.assertEqual(cofactor(terms+terms, 1), {})
        self.assertRaises(AssertionError, cofactor, [(0, 1, 1)], 0)
        self.assertRaises(AssertionError, cofactor, [(1, 1, 1 << 256)], 0)
        details = {}
        cartesian_minimum([{(1, 2): 4}], [{(1, 2): 8}], details=details)
        self.assertEqual(details['best_colliding_pair'], (1, 0, 0))
        cartesian_minimum([{(1, 2): 4}], [{(2, 1): 8}], details=details)
        self.assertIsNone(details['best_colliding_pair'])

    def test_rank_strata_match_direct_enumeration(self):
        rng = random.Random(202609073)
        for _ in range(200):
            pools = [[cofactor([tuple(rng.randrange(1,8) for _ in range(3)) for _ in range(rng.randrange(8))], 2)
                      for _ in range(rng.randrange(1,9))] for _ in range(2)]
            all_pairs = sorted((len(cofactor(materialize(a,2)+materialize(b,2),2)),i,j)
                               for i,a in enumerate(pools[0]) for j,b in enumerate(pools[1]))
            width, slack = rng.randrange(1,6), rng.randrange(4)
            details = {}
            best, _ = cartesian_minimum(*pools, details=details, width=width, slack=slack)
            self.assertEqual(best, all_pairs[0])
            strata = [[v for v in all_pairs if v[0] == best[0]+s] for s in range(slack+1)]
            self.assertEqual(details['ranked_candidates'], [v for group in strata for v in group[:width]])
            self.assertEqual(details['eligible_by_rank'], list(map(len,strata)))
        self.assertRaises(AssertionError, cartesian_minimum, [{}], [{}], details={}, width=0)

    def test_postcompression_exact_assessment(self):
        pools = [[{(1,1):1}], [{(1,2):1}]]
        row = compression_assessment(pools, [], 2, (2,0,0))
        self.assertEqual((row['bound'], row['rank'], row['density']), (2,1,4))
        self.assertEqual(row['compression'], [dict(axis=0, fixed=1, before=2, after=1)])
        self.assertRaises(AssertionError, compression_assessment, pools, [], 2, (1,0,0))

    def test_coordinate_embedding_and_orientation(self):
        terms = [(1, 1, 1)]
        self.assertEqual(mapped([2, 1, 1], (2, 1, 2), [[1, 1], [1], [1]], [1, 1, 1], terms), [(2, 1, 2)])
        self.assertEqual(mapped([1, 1, 1], (1, 1, 1), [[1], [1], [1]], [2, 1, 1], [(2, 1, 2)]), [])
        shape = (2, 3, 4)
        terms = [(1 << (i*3+j), 1 << (j*4+k), 1 << (i*4+k))
                 for i in range(2) for j in range(3) for k in range(4)]
        flipped = orient(shape, terms, (4, 3, 2))
        expected = [(1 << (i*3+j), 1 << (j*2+k), 1 << (i*2+k))
                    for i in range(4) for j in range(3) for k in range(2)]
        self.assertEqual(signature(flipped), signature(expected))

    def test_matrix_factorization_matches_exhaustive_small_column_spans(self):
        rng = random.Random(202609071)
        for _ in range(500):
            pairs = [(rng.randrange(32), rng.randrange(32)) for _ in range(rng.randrange(11))]
            factors = matrix_factors(pairs)
            def columns(rows):
                values = [0] * 5
                for left, right in rows:
                    for i in range(5):
                        if right >> i & 1:
                            values[i] ^= left
                return values
            self.assertEqual(columns(pairs), columns(factors))
            span = {0}
            for column in columns(pairs):
                span |= {v ^ column for v in list(span)}
            self.assertEqual(len(factors), len(span).bit_length() - 1)
        self.assertEqual(matrix_factors([(3,1),(2,2),(1,3)]), [(2,1),(3,2)])
        self.assertRaises(AssertionError, matrix_factors, [(1 << 256,1)])

    def test_nonempty_compression_history_and_corruption_rejection(self):
        terms = [(1,1,1),(1,1,2)]
        expected = [dict(axis=0, fixed=1, before=2, after=1)]
        self.assertEqual(replay_compression(terms, expected), [(1,1,3)])
        self.assertRaises(AssertionError, replay_compression, terms, [])
        self.assertRaises(AssertionError, replay_compression, terms, [dict(expected[0],after=0)])
        rng = random.Random(202609072)
        for _ in range(200):
            terms = [tuple(rng.randrange(1,8) for _ in range(3)) for _ in range(rng.randrange(12))]
            compressed, history = compress_shared(terms)
            self.assertEqual(signature(terms), signature(compressed))
            self.assertLessEqual(len(compressed), len(terms))
            again, further = compress_shared(compressed)
            self.assertEqual(sorted(again), sorted(compressed))
            self.assertEqual(further, [])

    def test_sparse_row_equations_match_exhaustive_span_coefficients(self):
        def oracle(pairs,width,reverse):
            columns=[0]*width
            for left,right in pairs:
                for j in range(width):
                    if right>>j&1:columns[j]^=left
            basis=[];span={0:0}
            for j in sorted(range(width),reverse=reverse):
                value=columns[j]
                if value not in span:
                    bit=1<<len(basis);basis.append(value)
                    span.update((v^value,c|bit) for v,c in list(span.items()))
            right=[0]*len(basis)
            for j,value in enumerate(columns):
                for i in range(len(basis)):
                    if span[value]>>i&1:right[i]|=1<<j
            return list(zip(basis,right))
        rng=random.Random(202609085)
        for width in (1,3,16,32,257,1024,4096):
            coordinates=sorted({0,width//3,width//2,width-1})
            for _ in range(30):
                pairs=[tuple(sum(rng.randrange(2)<<j for j in coordinates) for _ in range(2))
                       for _ in range(rng.randrange(9))]
                for reverse in (False,True):
                    self.assertEqual(matrix_factors(pairs,max_bits=width,reverse_columns=reverse),
                                     oracle(pairs,width,reverse))
        for _ in range(50):
            pairs=[(rng.getrandbits(32),rng.getrandbits(32)) for _ in range(8)]
            for reverse in (False,True):
                self.assertEqual(matrix_factors(pairs,max_bits=32,reverse_columns=reverse),
                                 oracle(pairs,32,reverse))
        self.assertEqual(matrix_factors([(1<<4095,1<<4095)]*2,max_bits=4096),[])

    def test_rhs_only_coordinate_is_not_silently_dropped(self):
        # Even an incorrect upstream rank oracle must fail the independent
        # row system rather than silently ignoring nonzero RHS coordinates.
        with patch('verify_cofactor_mergers.rank',return_value=0):
            with self.assertRaisesRegex(AssertionError,'inconsistent matrix coordinate system'):
                matrix_factors([(1<<1000,1)],max_bits=1024)

    def test_explicit_wide_compression_preserves_default_domain_and_tensor(self):
        for width in (257, 1024, 4096):
            a, b = 1 << 255, 1 << (width-1)
            terms = [(1,a,a), (1,b,b), (1,a^b,a^b)]
            self.assertRaises(AssertionError, matrix_factors, [(a,a),(b,b)])
            self.assertRaises(AssertionError, compress_shared, terms)
            out, history = compress_shared(terms, max_bits=width)
            self.assertEqual(len(out), 2)
            self.assertEqual(signature(out), signature(terms))
            self.assertEqual(history, [dict(axis=0, fixed=1, before=3, after=2)])
            again, further = compress_shared(out, max_bits=width)
            self.assertEqual(sorted(again), sorted(out))
            self.assertEqual(further, [])
            self.assertRaises(AssertionError, compress_shared, terms, max_bits=width-1)
        for width in (0, 4097, None, 1.5, True):
            self.assertRaises(AssertionError, matrix_factors, [], max_bits=width)
        self.assertRaises(AssertionError, compress_shared, [(1,0,1)], max_bits=1024)

    def test_neutral_refactor_moves_preserve_sparse_wide_tensor(self):
        rng=random.Random(202609074)
        for _ in range(100):
            terms=[tuple(sum(((v>>i)&1)<<j for i,j in enumerate((17,256,512,1000)))
                         for v in (rng.randrange(1,16) for _ in range(3))) for _ in range(8)]
            for axis in range(3):
                for reverse in (False,True):
                    out,_=refactor_shared(terms,axis,max_bits=1024,reverse_columns=reverse)
                    self.assertEqual(signature(terms),signature(out))
                    self.assertLessEqual(len(out),len(terms))
        terms=[(1,3,1),(1,2,3)]
        out,changed=refactor_shared(terms,0,reverse_columns=True)
        self.assertNotEqual(sorted(out),sorted(terms))
        self.assertTrue(changed)
        self.assertEqual(signature(terms),signature(out))


if __name__ == '__main__':
    unittest.main()
