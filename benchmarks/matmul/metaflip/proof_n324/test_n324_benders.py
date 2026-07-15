#!/usr/bin/env python3
"""Small regression tests for the n324 Gaussian-Benders cut boundary."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from n324_benders_cut import (
    all_dependencies,
    block_system,
    contradiction_witnesses,
    equations,
    lift_block_witness,
)
from n324_common import RANK_ONE_A, rank_rows


ROOT = Path(__file__).resolve().parent


class GaussianBendersTest(unittest.TestCase):
    def test_48_by_19_block_extractor_equals_576_row_extractor(self) -> None:
        a = tuple(value for value in RANK_ONE_A if value not in (1, 2))
        bvalues = tuple(
            value
            for value in range(1, 256)
            if rank_rows([value & 15, value >> 4], 4) == 1
        )
        # Several deterministic assignments exercise different row spaces.
        for offset in range(4):
            b = [bvalues[(7 * term + 11 * offset) % 45] for term in range(19)]
            full = all_dependencies(equations(a, b))
            _, block_dependencies, targets = block_system(a, b)
            self.assertEqual(len(full), 12 * len(block_dependencies))
            block_contradictions = {
                lift_block_witness(dependency, cbit)
                for cbit, target in enumerate(targets)
                for dependency in block_dependencies
                if (dependency & target).bit_count() & 1
            }
            full_contradictions = {
                witness for witness, rhs in full if rhs
            }
            self.assertEqual(block_contradictions, full_contradictions)

    def test_planted_consistent_system_refuses_extraction(self) -> None:
        # The equations are synthetic so consistency is known independently:
        # every rhs is the dot product with this planted 228-bit solution.
        solution = sum(1 << bit for bit in range(0, 228, 3))
        rows = []
        state = 0x9E3779B97F4A7C15
        mask228 = (1 << 228) - 1
        for _ in range(96):
            state = (state * 6364136223846793005 + 1442695040888963407)
            row = (state ^ (state << 73) ^ (state << 151)) & mask228
            rhs = (row & solution).bit_count() & 1
            rows.append((row, rhs))
        with self.assertRaisesRegex(AssertionError, "consistent"):
            contradiction_witnesses(rows)

    def test_emitted_clause_exactly_excludes_recorded_cartesian_region(self) -> None:
        # All B factors equal one is intentionally inconsistent with the n324
        # target.  It gives a tiny deterministic source model without relying
        # on any campaign artifact in /tmp.
        bvalues = tuple(
            value
            for value in range(1, 256)
            if rank_rows([value & 15, value >> 4], 4) == 1
        )
        self.assertEqual(len(bvalues), 45)
        bindex = {value: index for index, value in enumerate(bvalues)}
        source = [1] * 19
        positives = [term * 45 + bindex[value] + 1 for term, value in enumerate(source)]

        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            model = temporary / "source.out"
            cut = temporary / "cut.opb"
            witness = temporary / "cut.json"
            model.write_text(
                "s SATISFIABLE\n" + "v " + " ".join(f"x{x}" for x in positives) + "\n"
            )
            subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "n324_benders_cut.py"),
                    str(model),
                    str(cut),
                    str(witness),
                    "--missing", "1", "2",
                    "--fixed-b", "1",
                    "--max-cuts", "1",
                ],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            data = json.loads(witness.read_text())
            item = data["selected_cuts"][0]
            allowed = [set(values) for values in item["allowed_B_by_term"]]
            line = cut.read_text().strip()
            outside_variables = {
                int(value) for value in re.findall(r"\+1 x(\d+)", line)
            }

            def clause_is_violated(assignment: list[int]) -> bool:
                chosen = {
                    term * 45 + bindex[value] + 1
                    for term, value in enumerate(assignment)
                }
                return not bool(chosen & outside_variables)

            self.assertTrue(clause_is_violated(source))
            self.assertTrue(all(source[term] in allowed[term] for term in range(19)))

            # Exhaust every one-coordinate perturbation.  The emitted PB
            # clause is violated iff the whole assignment remains in the
            # recorded product Allowed_0 x ... x Allowed_18.
            saw_inside_change = False
            saw_outside_change = False
            for term in range(19):
                for value in bvalues:
                    assignment = source.copy()
                    assignment[term] = value
                    in_cartesian_region = all(
                        assignment[index] in allowed[index] for index in range(19)
                    )
                    self.assertEqual(
                        clause_is_violated(assignment), in_cartesian_region,
                        (term, value),
                    )
                    if value != source[term] and value in allowed[term]:
                        saw_inside_change = True
                    if value not in allowed[term]:
                        saw_outside_change = True
            self.assertTrue(saw_inside_change)
            self.assertTrue(saw_outside_change)

    def test_affine_samples_are_new_checked_contradictions(self) -> None:
        bvalues = tuple(
            value
            for value in range(1, 256)
            if rank_rows([value & 15, value >> 4], 4) == 1
        )
        positives = [term * 45 + 1 for term in range(19)]
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            model = temporary / "source.out"
            cut = temporary / "cut.opb"
            witness = temporary / "cut.json"
            model.write_text(
                "s SATISFIABLE\n" + "v " + " ".join(f"x{x}" for x in positives) + "\n"
            )
            subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "n324_benders_cut.py"),
                    str(model),
                    str(cut),
                    str(witness),
                    "--missing", "1", "2",
                    "--fixed-b", "1",
                    "--max-cuts", "32",
                    "--affine-samples", "64",
                    "--seed", "324",
                ],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            data = json.loads(witness.read_text())
            self.assertEqual(data["affine_samples"], 64)
            self.assertEqual(len(data["selected_cuts"]), 32)
            a = tuple(value for value in RANK_ONE_A if value not in (1, 2))
            rows = equations(a, [1] * 19)
            direct = set(contradiction_witnesses(rows))
            selected_witnesses = []
            for item in data["selected_cuts"]:
                selector = sum(1 << index for index in item["selected_equations"])
                selected_witnesses.append(selector)
                combined_row = 0
                combined_rhs = 0
                for index in item["selected_equations"]:
                    combined_row ^= rows[index][0]
                    combined_rhs ^= rows[index][1]
                self.assertEqual(combined_row, 0)
                self.assertEqual(combined_rhs, 1)
                self.assertTrue(
                    all(1 in allowed for allowed in item["allowed_B_by_term"])
                )
                self.assertTrue(
                    all(set(allowed) <= set(bvalues) for allowed in item["allowed_B_by_term"])
                )
            self.assertTrue(any(witness not in direct for witness in selected_witnesses))


if __name__ == "__main__":
    unittest.main()
