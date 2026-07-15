#!/usr/bin/env python3

from __future__ import annotations

import unittest
from itertools import product
from pathlib import Path

from n235_capacity import (
    Cnf,
    audit_rank_one_counting,
    audit_rank_two_multiset_model,
    build_fixed_rank_two_global_multiset_cnf,
    build_rank_two_multiset_cnf,
)
from n235_common import (
    RANK_ONE_A,
    RANK_TWO_A,
    expand_certificate,
    transpose_23_to_32,
)
from n235_verify import CNF_SHA256, audit_local, audit_upper_schemes
from n235_rank23_orbit_campaign import build_symmetry_branches


DIRECTORY = Path(__file__).resolve().parent
CERTIFICATE = DIRECTORY / "cert_matrix_q02_n235_lb22.pb.txt"


class N235CapacityTest(unittest.TestCase):
    def test_transpose_and_complete_geometry_cover(self) -> None:
        self.assertEqual(transpose_23_to_32(0b001010), 0b000110)
        parsed, lower_bounds, orbit_map = expand_certificate(CERTIFICATE)
        self.assertEqual(len(parsed), 31)
        self.assertEqual(len(lower_bounds), 2825)
        self.assertEqual(len(orbit_map), 2825)
        self.assertEqual(parsed[28], ((1,), 20))
        self.assertEqual(parsed[29], ((6,), 21))
        self.assertEqual(parsed[30], ((), 22))
        self.assertEqual(len(RANK_ONE_A), 21)
        self.assertEqual(len(RANK_TWO_A), 42)

    def test_capacity_cnf_reproduces_checked_artifact(self) -> None:
        data, metadata = build_rank_two_multiset_cnf(CERTIFICATE)
        self.assertEqual(metadata["cnf_sha256"], CNF_SHA256)
        self.assertEqual(metadata["variables"], 23452)
        self.assertEqual(metadata["clauses"], 46455)
        self.assertEqual(metadata["occurrence_slots"], 50)
        self.assertEqual(
            data, (DIRECTORY / "n235_rank2_multiset_r21.cnf").read_bytes()
        )

    def test_rank_one_incidence_contradiction(self) -> None:
        audit = audit_rank_one_counting(CERTIFICATE)
        self.assertEqual(audit["selected_subspaces"], 21)
        self.assertEqual(audit["incidence_degree"], 3)
        self.assertEqual(audit["summed_left_hand_side"], 66)
        self.assertEqual(audit["summed_right_hand_side"], 42)
        rank23 = audit_rank_one_counting(CERTIFICATE, hypothetical_rank=23)
        self.assertEqual(rank23["summed_left_hand_side"], 69)
        self.assertEqual(rank23["summed_right_hand_side"], 63)

    def test_rank23_quotient_capacity_sat_model(self) -> None:
        audit = audit_rank_two_multiset_model(
            CERTIFICATE, DIRECTORY / "n235_rank2_multiset_r22_model.json"
        )
        self.assertEqual(audit["status"], "SATISFIABLE")
        self.assertEqual(audit["total_occurrences"], 22)
        self.assertEqual(audit["support_points"], 20)
        self.assertEqual(audit["saturated_rows"], 28)

    def test_sinz_boundary_cases(self) -> None:
        cnf = Cnf(2)
        cnf.at_most([1, 2], 0)
        self.assertEqual(cnf.clauses, [[-1], [-2]])
        impossible = Cnf(0)
        impossible.at_most([], -1)
        self.assertEqual(impossible.clauses, [[]])

    def test_binary_lex_encoding(self) -> None:
        for left in product((0, 1), repeat=2):
            for right in product((0, 1), repeat=2):
                cnf = Cnf(4)
                cnf.lex_less_equal([1, 2], [3, 4])
                fixed = left + right
                satisfiable = False
                for auxiliary in product(
                    (0, 1), repeat=cnf.nvars - len(fixed)
                ):
                    values = fixed + auxiliary
                    if all(
                        any(
                            values[abs(literal) - 1]
                            == int(literal > 0)
                            for literal in clause
                        )
                        for clause in cnf.clauses
                    ):
                        satisfiable = True
                        break
                self.assertEqual(satisfiable, left <= right)

        identical_prefix = Cnf(3)
        identical_prefix.lex_less_equal([1, 2], [1, 3])
        self.assertEqual(identical_prefix.nvars, 3)
        self.assertEqual(identical_prefix.clauses, [[-2, 3]])

    def test_global_capacity_dominance_pruning(self) -> None:
        _, metadata = build_fixed_rank_two_global_multiset_cnf(
            CERTIFICATE, stabilizer_lex=True
        )
        self.assertEqual(metadata["ambient_subspaces"], 2825)
        self.assertEqual(metadata["active_ambient_rows"], 1567)
        self.assertEqual(
            metadata["redundant_ambient_rows"],
            {"dominated": 1193, "exact-total": 1, "tautology": 64},
        )
        self.assertEqual(
            metadata["dominance_audit_sha256"],
            "1e82259264710001c881722c46571c5bc39a055f823ad18c5d880a4d46f2938a",
        )

    def test_rank23_stabilizer_orbit_cover(self) -> None:
        branches, metadata = build_symmetry_branches(CERTIFICATE)
        self.assertEqual(metadata["root_orbit_sizes"], [3, 6, 3, 2, 12, 12, 24])
        self.assertEqual(metadata["refined_child_orbit_counts"], [14, 22, 9, 5, 25])
        self.assertEqual(metadata["direct_branches"], 12)
        self.assertEqual(metadata["refined_branches"], 75)
        self.assertEqual(len(branches), 87)

    def test_full_local_audit(self) -> None:
        audit, archive = audit_local(DIRECTORY)
        self.assertEqual(audit["checked_lower_bound"], 23)
        self.assertTrue(archive.startswith(b"BTPARCH\x00"))

    def test_rank25_upper_scheme_term_distances(self) -> None:
        audited = audit_upper_schemes(DIRECTORY)
        self.assertEqual(
            [row["rank"] for row in audited], [25, 25, 25, 25, 25]
        )
        self.assertEqual(
            [row["density"] for row in audited], [160, 170, 173, 210, 278]
        )


if __name__ == "__main__":
    unittest.main()
