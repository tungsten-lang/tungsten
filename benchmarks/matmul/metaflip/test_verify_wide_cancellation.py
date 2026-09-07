import copy
import unittest
import verify_wide_cancellation as check


class WideCancellationMetadataTest(unittest.TestCase):
    def data(self):
        return dict(initial_rank=8, rank=7, density=30, attempts=2000000, flips=1980000,
                    pluses=20000, best_at=600000, seconds=2.0, plus_every=32, restart_every=0,
                    restarts=0, compress_every=8192, compression_calls=244, compression_terms=10, checks=30)

    def test_correct_and_corrupted_counts(self):
        original = self.data(); source = dict(initial_rank=8, initial_density=24)
        report = dict(attempts_per_trial=2000000)
        check.validate_run(original, source, report)
        for key, value in [('rank', 9), ('attempts', 1), ('flips', 2000000), ('pluses', 100000),
                           ('best_at', 2000001), ('compression_calls', 243), ('checks', 1), ('restarts', 1)]:
            bad = copy.deepcopy(original); bad[key] = value
            with self.assertRaises(AssertionError, msg=key):
                check.validate_run(bad, source, report)

    def test_rank_tie_density_cannot_regress(self):
        bad = self.data(); bad['rank'] = 8
        with self.assertRaises(AssertionError):
            check.validate_run(bad, dict(initial_rank=8, initial_density=24), dict(attempts_per_trial=2000000))


if __name__ == '__main__':
    unittest.main()
