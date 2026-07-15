import itertools
import json
from dataclasses import replace
import unittest
from unittest import mock

from bench_decomp import naive_scheme, verify as independent_verify
from cpu_seed_banks import (
    NearFrontierBank,
    build_symmetry_move_bank,
    raw_novelty,
    structural_signature,
)
from escape_portfolio import build_portfolio
from sym_escape import is_c3_closed


def split_seeds(n=2, count=40):
    base = naive_scheme(n, n, n)
    entries = build_portfolio(
        base,
        n,
        count=count,
        per_step=max(16, count),
        recipes=(("split",), ("split", "split")),
        include_base=False,
    )
    plus_one = [entry for entry in entries if len(entry.scheme) == len(base) + 1]
    plus_two = [entry for entry in entries if len(entry.scheme) == len(base) + 2]
    return base, plus_one, plus_two


class NearFrontierBankTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base, cls.plus_one, cls.plus_two = split_seeds()
        if not cls.plus_one or not cls.plus_two:
            raise AssertionError("test escape portfolio lacks +1/+2 seeds")

    def test_exact_gate_and_rank_tiers_never_adopt_a_frontier(self):
        bank = NearFrontierBank(2, len(self.base), capacity=8, signature_quota=4)
        one = self.plus_one[0].scheme
        two = self.plus_two[0].scheme
        self.assertTrue(bank.admit(one, source="walker", expected_rank=9))
        self.assertTrue(bank.admit(two, source="walker", expected_rank=10))
        self.assertFalse(bank.admit(one, source="duplicate"))
        self.assertFalse(bank.admit(self.base, source="frontier"))
        self.assertFalse(bank.admit(one[:-1], source="invalid"))
        self.assertFalse(bank.admit(two, source="rank-mismatch", expected_rank=9))

        self.assertEqual(bank.best_rank, 8)
        self.assertEqual([seed.rank for seed in bank.entries(1)], [9])
        self.assertEqual([seed.rank for seed in bank.entries(2)], [10])
        status = bank.status()
        self.assertEqual(status["size"], 2)
        self.assertEqual(status["counters"]["duplicate"], 1)
        self.assertEqual(status["counters"]["out_of_band"], 1)
        self.assertEqual(status["counters"]["invalid"], 2)
        json.dumps(status)

    def test_signature_quota_and_online_max_min_novelty(self):
        # Use only +1 splits. Axis-specific factor reuse gives three structural
        # signatures, each capped at two entries.
        candidates = [entry.scheme for entry in self.plus_one]
        bank = NearFrontierBank(2, 8, capacity=12, signature_quota=2)
        full_minima = []
        for terms in candidates:
            bank.admit(terms, source="split")
            if len(bank.entries(1)) == bank.capacities[1]:
                full_minima.append(bank.minimum_distance(1))
        retained = bank.entries(1)
        counts = {}
        for seed in retained:
            counts[seed.signature] = counts.get(seed.signature, 0) + 1
        self.assertEqual(len(retained), 6)
        self.assertEqual(set(counts.values()), {2})
        self.assertTrue(all(
            later >= earlier
            for earlier, later in zip(full_minima, full_minima[1:])))
        actual_minimum = min(
            raw_novelty(left.terms, right.terms)
            for left, right in itertools.combinations(retained, 2))
        self.assertEqual(bank.minimum_distance(1), actual_minimum)
        self.assertEqual(
            {seed.signature for seed in retained},
            {structural_signature(seed.terms) for seed in retained},
        )

    def test_quadratic_replacement_scores_match_brute_force(self):
        bank = NearFrontierBank(2, 8, capacity=12, signature_quota=6)
        current = tuple(
            bank._entry_from_terms(entry.scheme, "fixture")
            for entry in self.plus_one[:6]
        )
        candidate = bank._entry_from_terms(self.plus_one[6].scheme, "candidate")
        baseline, qualities = bank._replacement_qualities(
            current, candidate, current)
        self.assertEqual(bank._set_quality(current), baseline)
        for victim in current:
            replacement = tuple(row for row in current if row is not victim) + (candidate,)
            self.assertEqual(bank._set_quality(replacement),
                             qualities[victim.terms])

    def test_least_used_selection_is_balanced_and_reproducible(self):
        def populated():
            bank = NearFrontierBank(2, 8, capacity=8, signature_quota=4)
            for entry in self.plus_one[:12]:
                bank.admit(entry.scheme, source="split")
            return bank

        first, second = populated(), populated()
        sequence_one = [first.select(1, stable_key=index % 3).digest
                        for index in range(24)]
        sequence_two = [second.select(1, stable_key=index % 3).digest
                        for index in range(24)]
        self.assertEqual(sequence_one, sequence_two)
        uses = [seed.uses for seed in first.entries(1)]
        self.assertLessEqual(max(uses) - min(uses), 1)
        selected = first.select(1, stable_key="productive-walker")
        self.assertTrue(first.mark_success(selected, resulting_rank=8))
        self.assertEqual(selected.successes, 1)
        self.assertEqual(selected.best_result_rank, 8)

    def test_rebase_promotes_old_frontier_and_reclassifies_near_seed(self):
        bank = NearFrontierBank(2, 8, capacity=8, signature_quota=4)
        one = self.plus_one[0].scheme
        two = self.plus_two[0].scheme
        bank.admit(one, source="near-one")
        bank.admit(two, source="near-two")
        bank.select(1, stable_key=1)

        summary = bank.rebase(7, [self.base])
        self.assertEqual(summary["old_frontier_admitted"], 1)
        self.assertEqual(bank.best_rank, 7)
        self.assertEqual({seed.terms for seed in bank.entries(1)},
                         {tuple(sorted(self.base))})
        self.assertEqual({seed.terms for seed in bank.entries(2)}, {one})
        self.assertTrue(all(seed.uses == 0 for seed in bank.entries()))
        self.assertNotIn(two, {seed.terms for seed in bank.entries()})

        before = bank.status()
        broken = list(self.base[:-1])
        with self.assertRaisesRegex(ValueError, "old_frontier entry"):
            bank.rebase(6, [broken])
        self.assertEqual(bank.status(), before)

    def test_capacity_and_argument_validation(self):
        with self.assertRaises(ValueError):
            NearFrontierBank(2, 8, capacity=1)
        with self.assertRaises(ValueError):
            NearFrontierBank(2, 8, signature_quota=0)
        bank = NearFrontierBank(2, 8)
        with self.assertRaises(ValueError):
            bank.select(3)
        with self.assertRaises(ValueError):
            bank.rebase(9, [])


class SymmetryMoveBankTests(unittest.TestCase):
    def test_bank_contains_only_replayable_exact_c3_single_moves(self):
        base = naive_scheme(2, 2, 2)
        entries = build_symmetry_move_bank(base, 2, 8)
        self.assertEqual(len(entries), 8)
        self.assertEqual(
            {entry.recipe for entry in entries},
            {("orbit-split",), ("polarize",)},
        )
        self.assertEqual(len({entry.scheme for entry in entries}), len(entries))
        for entry in entries:
            self.assertEqual(len(entry.moves), 1)
            self.assertEqual(entry.moves[0].kind, entry.recipe[0])
            self.assertTrue(independent_verify(entry.scheme, 2, 2, 2))
            self.assertTrue(is_c3_closed(entry.scheme, 2))
            self.assertTrue(entry.profile["c3"])

    def test_source_must_be_exact_and_c3_closed(self):
        base, plus_one, _ = split_seeds(count=4)
        self.assertFalse(is_c3_closed(plus_one[0].scheme, 2))
        with self.assertRaisesRegex(ValueError, "not closed"):
            build_symmetry_move_bank(plus_one[0].scheme, 2, 2)
        with self.assertRaisesRegex(ValueError, "not an exact"):
            build_symmetry_move_bank(base[:-1], 2, 2)

    def test_forged_move_provenance_is_rejected(self):
        base = naive_scheme(2, 2, 2)
        good = build_symmetry_move_bank(base, 2, 2)
        forged = replace(
            good[0], scheme=good[1].scheme, profile=good[1].profile)
        with mock.patch("cpu_seed_banks.build_portfolio", return_value=[forged]):
            with self.assertRaisesRegex(RuntimeError, "provenance does not replay"):
                build_symmetry_move_bank(base, 2, 1)


if __name__ == "__main__":
    unittest.main()
