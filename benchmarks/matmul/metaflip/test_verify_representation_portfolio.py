import copy
from pathlib import Path
import unittest
import verify_representation_portfolio as verify


class RepresentationAuditTest(unittest.TestCase):
    def report(self):
        parts = [dict(kind='kernel', axis=0, word=[[0, 0, 1]]),
                 dict(kind='kernel', axis=1, word=[[1, 1, 0]])]
        return dict(complete=True, record_claim=False, field='GF(2)', targets=1,
            rows=[dict(target=[2, 2, 2], initial_rank=8, initial_density=30, rank=8, density=24,
                rounds=1, round_limit=2, history_replayed=True, checks=20, pair_checks=4,
                verification='winner', verified_neighbors=1, history=[dict(kind='kernel_pair',
                    word=[[0, 0, 1], [1, 1, 0]], components=parts, rank=8, density=24)])])

    def test_valid_and_corrupt_admission_metadata(self):
        original = self.report()
        verify.check_walk(original)
        for field, value in [('density', 25), ('verified_neighbors', 0), ('rounds', 3), ('pair_checks', 21)]:
            bad = copy.deepcopy(original)
            bad['rows'][0][field] = value
            with self.assertRaises(AssertionError):
                verify.check_walk(bad)

    def test_mismatched_pair_and_nonmonotone_history_are_rejected(self):
        bad = self.report()
        bad['rows'][0]['history'][0]['word'].reverse()
        with self.assertRaises(AssertionError):
            verify.check_walk(bad)
        bad = self.report()
        bad['rows'][0]['initial_density'] = 23
        with self.assertRaises(AssertionError):
            verify.check_walk(bad)

    def test_snapshot_formats_and_path_boundary(self):
        self.assertEqual([(1, 1, 1)], verify.parse_terms(b'1\n1 1 1\n', 1))
        self.assertEqual([(1, 1, 1)], verify.parse_terms(b'R 1 1 1\n', 1))
        with self.assertRaises(AssertionError):
            verify.parse_terms(b'2\n1 1 1\n', 1)
        with self.assertRaises(ValueError):
            verify.contained(Path('/private/tmp/artifact'), '../outside.txt')

    def test_independent_word_action_and_identity(self):
        terms = [(1 << (i * 2 + j), 1 << (j * 2 + k), 1 << (i * 2 + k))
                 for i in range(2) for j in range(2) for k in range(2)]
        word = [[0, 0, 1], [1, 1, 0], [2, 0, 1]]
        image = verify.apply_word((2, 2, 2), terms, word)
        self.assertNotEqual(terms, image)
        self.assertEqual(terms, verify.apply_word((2, 2, 2), image, word[::-1]))
        self.assertEqual(verify.identity((2, 2, 2), terms), verify.identity((2, 2, 2), terms[::-1]))
        with self.assertRaises(AssertionError):
            verify.apply_word((2, 2, 2), terms, [[0, 1, 1]])


if __name__ == '__main__':
    unittest.main()
