from itertools import permutations, product
import random
import unittest

from packing_incidence import find_permutation, profile, transport, verify_permutation
from test_extend_composition_parents import alternate
from test_verify_composition_recipes import naive
from verify_bud_renewal import factor_maps


class PackingIncidenceTest(unittest.TestCase):
    def test_valid_tensor_pair_and_transported_groups(self):
        left, right = naive((2, 2, 2)), alternate()
        result = find_permutation(left, right)
        self.assertEqual(result['status'], 'matched')
        self.assertTrue(verify_permutation(left, right, result['permutation']))
        groups = [dict(axis=0, indices=[i, i+1]) for i in range(0, 8, 2)]
        for group in transport(groups, result['permutation']):
            factor_maps(right, group)

    def test_equal_bucket_histograms_do_not_imply_equivalence(self):
        left = [(1,1,1),(1,1,2),(2,2,1),(2,2,2)]
        right = [(1,1,1),(1,2,2),(2,1,2),(2,2,1)]
        self.assertEqual(profile(left)['signature'][0], profile(right)['signature'][0])
        self.assertEqual(find_permutation(left, right)['status'], 'different')
        with self.assertRaises(ValueError):
            verify_permutation(left, right, list(range(4)))

    def test_bruteforce_small_relations_and_relabelled_words(self):
        rng = random.Random(72)
        universe = list(product(range(1, 4), repeat=3))
        for _ in range(12):
            left, right = rng.sample(universe, 5), rng.sample(universe, 5)
            brute = False
            for p in permutations(range(5)):
                try:
                    verify_permutation(left, right, p)
                    brute = True; break
                except ValueError:
                    pass
            result = find_permutation(left, right)
            self.assertTrue(result['complete'])
            self.assertEqual(result['status'] == 'matched', brute)
            shuffled = list(left); rng.shuffle(shuffled)
            renamed = [tuple((13, 25, 39)[v-1]+100*a for a, v in enumerate(t)) for t in shuffled]
            self.assertEqual(find_permutation(left, renamed)['status'], 'matched')

    def test_explicit_limits_are_not_nonexistence_claims(self):
        terms = naive((2, 2, 2))
        for options in (dict(max_states=1), dict(max_terms=2)):
            result = find_permutation(terms, terms, **options)
            self.assertFalse(result['complete'])
            self.assertIn(result['status'], ('state_limit', 'term_limit'))
        for bad in ([0]*8, list(range(7))+[True]):
            with self.assertRaises(ValueError):
                verify_permutation(terms, terms, bad)


if __name__ == '__main__':
    unittest.main()
