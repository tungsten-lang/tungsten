import copy
import unittest
import verify_projection_filters as verify


class ProjectionFilterAuditTest(unittest.TestCase):
    def test_embedding_clips_and_copies_into_disjoint_blocks(self):
        # One full 2x2 local factor, in block (0,0) clipped to 1x1 and
        # block (1,1) retained at 2x2, giving a 3x3 result.
        self.assertEqual(sum(1 << i for i in (0, 4, 5, 7, 8)),
                         verify.embed(15, 9, 2, [1, 2], [1, 2], 2))
        self.assertEqual(0, verify.embed(8, 1, 2, [1, 2], [1, 2], 2))

    def test_disjunction_and_empty_clause_semantics(self):
        conditions = [[], [[]], [[[0, 'u', 1]], [[1, 'v', 2]]]]
        self.assertEqual(2, verify.evaluate(conditions, {(0, 'u'): 1, (1, 'v'): 1}))
        self.assertEqual(1, verify.evaluate(conditions, {(0, 'u'): 2, (1, 'v'): 1}))

    def test_sample_catches_corrupt_score_and_noncomplementary_pair(self):
        sample = dict(assignment=[[0, 'u', 2], [0, 'v', 2]], word=[], zeros=1)
        args = ((2, 2, 2), (1, 1, 1), [[1, 2]] * 3, (2, 2, 2), [(4, 1, 1)], [0], [[[[0, 'u', 2]]]])
        self.assertEqual(1, verify.check_sample(*args, sample))
        bad = copy.deepcopy(sample)
        bad['zeros'] = 0
        with self.assertRaises(AssertionError):
            verify.check_sample(*args, bad)
        bad = copy.deepcopy(sample)
        bad['assignment'][1][2] = 1
        with self.assertRaises(AssertionError):
            verify.check_sample(*args, bad)

    def test_formula_uses_both_incident_edges(self):
        self.assertEqual(1, verify.formula((2, 2, 2), [(1, 1, 1)], [[1, 2]] * 3, lambda s: s[0] * s[1] * s[2]))
        self.assertEqual(8, verify.formula((2, 2, 2), [(8, 8, 8)], [[1, 2]] * 3, lambda s: s[0] * s[1] * s[2]))


if __name__ == '__main__':
    unittest.main()
