#!/usr/bin/env python3

from __future__ import annotations

import re
import tempfile
import unittest
from itertools import product
from pathlib import Path

from inner2_direct_rank_audit import audit, matrix_rank
from inner2_direct_rank_opb import build, representative
from inner2_direct_rank_xnf import Xnf, build as build_xnf
from inner2_generate_campaign import generate
from inner2_run_xnf_campaign import last_integer
from inner2_stabilizer_orbits import CASES, enumerate_orbits
from inner2_verify_xnf_campaign import verify_checked_prerequisite, verify_coverage


class InnerTwoDirectRankTest(unittest.TestCase):
    def test_solver_counter_suffixes(self) -> None:
        transcript = "c propagations : 39.4M\nc propagations : 2G\n"
        self.assertEqual(last_integer(transcript, "propagations"), 2_000_000_000)
        self.assertEqual(last_integer("c conflicts : 62182\n", "conflicts"), 62182)

    def test_lex_leq_encoding(self) -> None:
        # Exhaust the helper variables too: a satisfying extension must exist
        # exactly for lexicographically ordered two-bit vectors.
        xnf = Xnf()
        variables = xnf.block(4)
        left = [variables, variables + 1]
        right = [variables + 2, variables + 3]
        xnf.lex_leq(left, right)
        auxiliaries = list(range(variables + 4, xnf.variables + 1))

        def clause_true(clause: list[int], assignment: dict[int, int]) -> bool:
            return any(
                assignment[abs(literal)] == int(literal > 0)
                for literal in clause
            )

        for left_value, right_value in product(range(4), repeat=2):
            bits = {
                left[0]: (left_value >> 1) & 1,
                left[1]: left_value & 1,
                right[0]: (right_value >> 1) & 1,
                right[1]: right_value & 1,
            }
            extendable = False
            for values in product((0, 1), repeat=len(auxiliaries)):
                assignment = dict(bits)
                assignment.update(zip(auxiliaries, values))
                if all(clause_true(clause, assignment) for clause in xnf.clauses):
                    extendable = True
                    break
            self.assertEqual(extendable, left_value <= right_value)

    def test_not_equal_encoding(self) -> None:
        xnf = Xnf()
        variables = xnf.block(4)
        left = [variables, variables + 1]
        right = [variables + 2, variables + 3]
        xnf.not_equal(left, right)
        auxiliaries = list(range(variables + 4, xnf.variables + 1))

        def clause_true(clause: list[int], assignment: dict[int, int]) -> bool:
            return any(
                assignment[abs(literal)] == int(literal > 0)
                for literal in clause
            )

        def xor_true(item: tuple[list[int], int], assignment: dict[int, int]) -> bool:
            literals, rhs = item
            return sum(assignment[literal] for literal in literals) % 2 == rhs

        for left_value, right_value in product(range(4), repeat=2):
            bits = {
                left[0]: (left_value >> 1) & 1,
                left[1]: left_value & 1,
                right[0]: (right_value >> 1) & 1,
                right[1]: right_value & 1,
            }
            extendable = False
            for values in product((0, 1), repeat=len(auxiliaries)):
                assignment = dict(bits)
                assignment.update(zip(auxiliaries, values))
                if all(clause_true(clause, assignment) for clause in xnf.clauses) and all(
                    xor_true(item, assignment) for item in xnf.xors
                ):
                    extendable = True
                    break
            self.assertEqual(extendable, left_value != right_value)

    def test_rank_representatives(self) -> None:
        for rows, columns in ((2, 2), (5, 2), (2, 4)):
            for rank in (1, 2):
                value = representative(rows, columns, rank)
                self.assertEqual(matrix_rank(value, rows, columns), rank)

    def test_checked_strassen_model(self) -> None:
        # Independently decoded from a RoundingSat model of the generated
        # rank-seven a1/b1/pairing1 shard.
        scheme = (
            (1, 1, 3),
            (2, 4, 5),
            (10, 15, 4),
            (15, 3, 2),
            (14, 11, 6),
            (12, 8, 10),
            (4, 10, 12),
        )
        a = c = 2
        terms = len(scheme)
        adim = bdim = 4
        targets = 4
        a_base = 1
        b_base = a_base + terms * adim
        product_base = b_base + terms * bdim
        coefficient_base = product_base + terms * adim * bdim
        positive = []
        for term, (avalue, bvalue, cvalue) in enumerate(scheme):
            positive.extend(
                a_base + term * adim + bit
                for bit in range(adim)
                if (avalue >> bit) & 1
            )
            positive.extend(
                b_base + term * bdim + bit
                for bit in range(bdim)
                if (bvalue >> bit) & 1
            )
            positive.extend(
                coefficient_base + term * targets + bit
                for bit in range(targets)
                if (cvalue >> bit) & 1
            )
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "model.txt"
            model.write_text(
                "s SATISFIABLE\n" + "v " + " ".join(f"x{x}" for x in positive) + "\n"
            )
            result = audit(model, a, c, terms)
        self.assertEqual(result["used_terms"], 7)
        self.assertEqual(result["fixed_a_rank"], 1)
        self.assertEqual(result["fixed_b_rank"], 1)
        self.assertEqual(result["fixed_pairing"], 1)
        self.assertEqual(result["quotient_rank"], result["quotient_cap"])

    def test_generator_header_and_pairing_shards(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outputs = []
            cases = ((1, 1, 0), (1, 1, 1), (1, 2, None), (2, 1, None), (2, 2, None))
            for index, (a_rank, b_rank, pairing) in enumerate(cases):
                output = root / f"case{index}.opb"
                stats = build(output, 2, 2, 7, a_rank, b_rank, pairing, True, True)
                lines = output.read_text().splitlines()
                header = re.fullmatch(
                    r"\* #variable= (\d+) #constraint= (\d+) #equal= 0 intsize= 64",
                    lines[0],
                )
                self.assertIsNotNone(header)
                assert header is not None
                self.assertEqual(int(header.group(1)), stats["variables"])
                self.assertEqual(int(header.group(2)), sum(line.endswith(";") for line in lines))
                outputs.append(output.read_bytes())
            self.assertEqual(len(set(outputs)), 5)

    def test_fixed_c_and_native_xor_headers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            free = build_xnf(root / "free.xnf", 2, 2, 7, 1, 1, 1)
            fixed = build_xnf(root / "fixed.xnf", 2, 2, 7, 1, 1, 1, 9)
            self.assertEqual(fixed["fixed_c"], 9)
            self.assertEqual(fixed["constraints"], free["constraints"] + 4)
            first = (root / "fixed.xnf").read_text().splitlines()
            header = next(line for line in first if line.startswith("p cnf "))
            self.assertEqual(
                header,
                f"p cnf {fixed['variables']} {fixed['constraints']}",
            )

    def test_exact_rank_nonzero_c_guard(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            free = build_xnf(root / "free.xnf", 2, 2, 7, 1, 1, 1)
            guarded = build_xnf(
                root / "guarded.xnf", 2, 2, 7, 1, 1, 1,
                nonzero_c=True,
            )
            self.assertTrue(guarded["nonzero_c"])
            self.assertEqual(guarded["constraints"], free["constraints"] + 7)
            comments = (root / "guarded.xnf").read_text().splitlines()
            self.assertIn("c every C factor nonzero=1", comments)

            minimal = build_xnf(
                root / "minimal.xnf", 2, 2, 7, 1, 1, 1,
                minimal_terms=True,
            )
            self.assertTrue(minimal["nonzero_c"])
            self.assertTrue(minimal["minimal_terms"])
            self.assertGreater(minimal["constraints"], guarded["constraints"])

    def test_dual_inner2_quotient_shape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = build_xnf(
                root / "base.xnf", 2, 2, 7, 1, 1, 1,
                quotient_rank=True,
            )
            dual = build_xnf(
                root / "dual.xnf", 2, 2, 7, 1, 1, 1,
                quotient_rank=True, dual_inner2_quotient=True,
            )
            self.assertTrue(dual["dual_inner2_quotient"])
            self.assertEqual(dual["dual_quotient_cap"], 3)
            self.assertEqual(dual["dual_quotient_coordinates"], 12)
            self.assertGreater(dual["variables"], base["variables"])
            self.assertGreater(dual["constraints"], base["constraints"])
            self.assertIn(
                "c cyclic B*C quotient rank <= 3 in dimension 12; "
                "nonvacuous=1 rref=1",
                (root / "dual.xnf").read_text().splitlines(),
            )
            with self.assertRaisesRegex(AssertionError, "requires <a,2,2>"):
                build_xnf(
                    root / "bad.xnf", 2, 3, 7, 1, 1, 1,
                    dual_inner2_quotient=True,
                )

    def test_factor_span_dependency_strengthening(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = build_xnf(
                root / "base.xnf", 2, 2, 7, 1, 1, 1,
                quotient_rank=True,
            )
            weight_one = build_xnf(
                root / "weight1.xnf", 2, 2, 7, 1, 1, 1,
                quotient_rank=True, span_dependency_weight=1,
            )
            weight_two = build_xnf(
                root / "weight2.xnf", 2, 2, 7, 1, 1, 1,
                quotient_rank=True, span_dependency_weight=2,
            )
            # Weight one adds one nonzero-row clause for each coordinate in
            # A, B, and C.  Higher weights use native XOR parity helpers.
            self.assertEqual(weight_one["variables"], base["variables"])
            self.assertEqual(weight_one["xors"], base["xors"])
            self.assertEqual(weight_one["clauses"], base["clauses"] + 12)
            self.assertGreater(weight_two["variables"], weight_one["variables"])
            self.assertGreater(weight_two["xors"], weight_one["xors"])
            self.assertIn(
                "c factor-span dependency exclusion through weight 2",
                (root / "weight2.xnf").read_text().splitlines(),
            )

    def test_campaign_covers_all_small_fixed_terms(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = generate(
                Path(directory),
                2,
                2,
                6,
                "xnf",
                {case[0] for case in CASES},
                None,
                True,
                False,
            )
        self.assertTrue(manifest["coverage_complete"])
        self.assertEqual(manifest["formula_count"], 29)
        self.assertEqual(manifest["covered_fixed_c_values"], 5 * 15)

        with self.assertRaisesRegex(ValueError, "only for XNF"):
            generate(
                Path(directory),
                2,
                2,
                6,
                "opb",
                {case[0] for case in CASES},
                None,
                True,
                True,
                True,
            )

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "known-lower-bound"):
                generate(
                    Path(directory), 5, 2, 17, "xnf",
                    {case[0] for case in CASES}, None, True, True,
                    nonzero_c=True,
                )
            guarded = generate(
                Path(directory), 5, 2, 17, "xnf",
                {case[0] for case in CASES}, None, True, True,
                nonzero_c=True, known_lower_bound=17,
            )
            self.assertEqual(guarded["prerequisite_checked_lower_bound"], 17)
            coverage_manifest = dict(guarded)
            coverage_manifest["enumerate_only"] = False
            verify_coverage(coverage_manifest)
            prerequisite = verify_checked_prerequisite(
                guarded, Path(__file__).resolve().parent,
            )
            assert prerequisite is not None
            self.assertEqual(prerequisite["verified_lower_bound_encoded"], 17)

            analytic = dict(guarded)
            analytic["a"] = 6
            analytic["tensor"] = "<6,2,2>"
            analytic["terms"] = 19
            analytic["prerequisite_checked_lower_bound"] = 19
            analytic_prerequisite = verify_checked_prerequisite(
                analytic, Path(__file__).resolve().parent,
            )
            assert analytic_prerequisite is not None
            self.assertEqual(analytic_prerequisite["kind"], "analytic-blaser")
            self.assertEqual(
                analytic_prerequisite["verified_lower_bound_encoded"], 19,
            )

            unsupported = dict(guarded)
            unsupported["a"] = 4
            unsupported["tensor"] = "<4,2,2>"
            with self.assertRaisesRegex(ValueError, "no pinned"):
                verify_checked_prerequisite(
                    unsupported, Path(__file__).resolve().parent,
                )

    def test_stabilizer_generators_match_bruteforce_n222(self) -> None:
        def rows(mask: int, count: int, width: int) -> tuple[int, ...]:
            return tuple(
                (mask >> (row * width)) & ((1 << width) - 1)
                for row in range(count)
            )

        def flatten(value: tuple[int, ...], width: int) -> int:
            return sum(row << (index * width) for index, row in enumerate(value))

        def multiply(
            left: tuple[int, ...], right: tuple[int, ...]
        ) -> tuple[int, ...]:
            result = []
            for row in left:
                value = 0
                for index in range(len(right)):
                    if (row >> index) & 1:
                        value ^= right[index]
                result.append(value)
            return tuple(result)

        invertibles = tuple(
            rows(mask, 2, 2)
            for mask in range(16)
            if matrix_rank(mask, 2, 2) == 2
        )
        identity = (1, 2)
        inverse = {
            value: next(
                candidate
                for candidate in invertibles
                if multiply(value, candidate) == identity
            )
            for value in invertibles
        }

        for _, a_rank, b_rank, pairing in CASES:
            a_value = representative(2, 2, a_rank)
            b_value = representative(2, 2, b_rank)
            if a_rank == b_rank == 1 and pairing == 0:
                b_value = 1 << 2
            aa = rows(a_value, 2, 2)
            bb = rows(b_value, 2, 2)
            stabilizer = []
            for n, g, ell in product(invertibles, repeat=3):
                if multiply(n, aa) != multiply(aa, g):
                    continue
                if multiply(bb, ell) != multiply(inverse[g], bb):
                    continue
                stabilizer.append((n, ell))

            unseen = set(range(1, 16))
            brute = []
            while unseen:
                root = min(unseen)
                cc = rows(root, 2, 2)
                orbit = {
                    flatten(multiply(multiply(ell, cc), n), 2)
                    for n, ell in stabilizer
                }
                unseen.difference_update(orbit)
                brute.append((min(orbit), len(orbit)))
            generated = [
                (orbit.representative, orbit.size)
                for orbit in enumerate_orbits(2, 2, a_rank, b_rank, pairing)
            ]
            self.assertEqual(generated, brute)


if __name__ == "__main__":
    unittest.main()
