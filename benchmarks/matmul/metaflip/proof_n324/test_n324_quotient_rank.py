#!/usr/bin/env python3
"""Regression checks for the n324 quotient-rank lemma and cut boundary."""

from __future__ import annotations

import unittest

from n324_common import RANK_ONE_A, rank_rows
from n324_quotient_rank import (
    factor_a,
    factor_b,
    quotient_column,
    quotient_r,
    rank_one_b_values,
    triangular_cut,
)


def direct_reordered_column(avalue: int, bvalue: int) -> int:
    """Build A tensor B in Q tensor R, then quotient R by <I2>."""
    full = 0
    for ai in range(6):
        i, j = divmod(ai, 2)
        if not ((avalue >> ai) & 1):
            continue
        for bi in range(8):
            jb, k = divmod(bi, 4)
            if (bvalue >> bi) & 1:
                q = 4 * i + k
                r = 2 * j + jb
                full ^= 1 << (4 * q + r)
    projected = 0
    for q in range(12):
        image = quotient_r((full >> (4 * q)) & 15)
        projected |= image << (3 * q)
    return projected


class QuotientRankTest(unittest.TestCase):
    def test_factorizations_and_quotient_kernel(self) -> None:
        self.assertEqual(len({factor_a(value) for value in RANK_ONE_A}), 21)
        bvalues = rank_one_b_values()
        self.assertEqual(len({factor_b(value) for value in bvalues}), 45)
        kernel = {value for value in range(16) if quotient_r(value) == 0}
        self.assertEqual(kernel, {0, 0b1001})

    def test_direct_48_bit_projection_matches_36_bit_encoder(self) -> None:
        for avalue in RANK_ONE_A:
            for bvalue in rank_one_b_values():
                self.assertEqual(
                    direct_reordered_column(avalue, bvalue),
                    quotient_column(avalue, bvalue),
                    (avalue, bvalue),
                )

    def test_target_slice_subspace_is_twelve_identity_lines(self) -> None:
        target_slices = tuple(
            (1 << (4 * q)) | (1 << (4 * q + 3)) for q in range(12)
        )
        self.assertEqual(rank_rows(list(target_slices), 48), 12)
        self.assertTrue(all(
            all(quotient_r((slice_ >> (4 * q)) & 15) == 0 for q in range(12))
            for slice_ in target_slices
        ))

    def test_triangular_cartesian_cut_is_uniformly_independent(self) -> None:
        missing = (1, 2)
        avalues = tuple(value for value in RANK_ONE_A if value not in missing)
        all_b = rank_one_b_values()
        source = tuple(all_b[(11 * term + 3) % 45] for term in range(19))
        columns = [
            quotient_column(a, b) for a, b in zip(avalues, source)
        ]
        basis_terms = []
        for term, column in enumerate(columns):
            if rank_rows([columns[index] for index in basis_terms] + [column], 36) > len(basis_terms):
                basis_terms.append(term)
            if len(basis_terms) == 8:
                break
        self.assertEqual(len(basis_terms), 8)
        cut = triangular_cut(missing, source, tuple(basis_terms))
        duals = cut["duals"]
        order = cut["order"]
        boxes = cut["boxes"]
        terms = cut["terms"]
        self.assertGreater(cut["box_product"], 1)
        for position, (term, allowed) in enumerate(boxes):
            dual_index = order[position]
            self.assertEqual(term, terms[dual_index])
            for bvalue in allowed:
                column = quotient_column(avalues[term], bvalue)
                self.assertEqual((duals[dual_index] & column).bit_count() & 1, 1)
                for earlier_position in range(position):
                    earlier_dual = order[earlier_position]
                    self.assertEqual(
                        (duals[earlier_dual] & column).bit_count() & 1, 0
                    )


if __name__ == "__main__":
    unittest.main()
