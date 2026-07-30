#!/usr/bin/env python3
"""Fast unit tests for the offline paired-router data contract."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import router_dataset as DATASET


class RouterDatasetTest(unittest.TestCase):
    def test_feature_abi_and_dimacs_statistics(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tiny.cnf"
            path.write_text(
                "c split clauses are legal\n"
                "p cnf 4 3\n"
                "1 -2 0\n"
                "3\n"
                "0\n"
                "-1 -3 4 0\n",
                encoding="ascii",
            )
            features = DATASET.static_features(path)
        self.assertEqual(list(features), DATASET.FEATURE_NAMES)
        self.assertEqual(features["nvars"], 4)
        self.assertEqual(features["nclauses"], 3)
        self.assertEqual(features["nlits"], 6)
        self.assertEqual(features["used_vars"], 4)
        self.assertEqual(features["units"], 1)
        self.assertEqual(features["binary"], 1)
        self.assertEqual(features["ternary"], 1)
        self.assertEqual(features["positive_literals"], 3)
        self.assertEqual(features["negative_literals"], 3)
        self.assertEqual(features["exact_one_sketch_candidates"], 0)
        self.assertEqual(features["exact_one_sketch_pair_coverage_ppm"], 0)
        self.assertEqual(features["exact_one_sketch_full_groups"], 0)
        self.assertEqual(features["binary_graph_edges"], 1)
        self.assertEqual(features["binary_graph_vertices"], 2)
        self.assertEqual(features["binary_graph_degree_max"], 1)
        self.assertEqual(features["variable_occurrence_top1_ppm"], 333333)
        self.assertEqual(features["variable_occurrence_top10_ppm"], 1000000)
        self.assertEqual(features["variable_occurrence_hhi_ppm"], 277777)
        self.assertEqual(
            DATASET.training_csv_header(),
            ",".join(DATASET.TRAINING_CSV_COLUMNS),
        )
        self.assertEqual(len(DATASET.FEATURE_NAMES), 31)
        self.assertEqual(len(DATASET.TRAINING_CSV_COLUMNS), 37)
        self.assertEqual(DATASET.FEATURE_SCHEMA_VERSION, 2)
        self.assertEqual(
            DATASET.FEATURE_SCHEMA_SHA256,
            "6c74c4ea6a670c9ff8aab655baa60243d4f34c2869d3accd91d9924afea244ca",
        )

    def test_exact_one_sketch_has_bounded_deterministic_pair_coverage(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "exact-one.cnf"
            path.write_text(
                "p cnf 4 4\n"
                "3 1 2 0\n"
                "-1 -2 0\n"
                "-3 -1 0\n"
                "4 4 0\n",
                encoding="ascii",
            )
            first = DATASET.static_features(path)
            second = DATASET.static_features(path)
        self.assertEqual(first, second)
        self.assertEqual(first["exact_one_sketch_candidates"], 1)
        self.assertEqual(
            first["exact_one_sketch_pair_coverage_ppm"],
            666666,
        )
        self.assertEqual(first["exact_one_sketch_full_groups"], 0)
        # The duplicate-variable binary clause is a loop and is intentionally
        # excluded from the occurrence-multigraph statistics.
        self.assertEqual(first["binary_graph_edges"], 2)
        self.assertEqual(first["binary_graph_vertices"], 3)
        self.assertEqual(first["binary_graph_degree_max"], 2)

    def test_policy_environment_cannot_inherit_stale_wassat_knobs(self) -> None:
        with patch.dict(
            os.environ,
            {"WASSAT_STALE_EXPERIMENT": "1", "ROUTER_TEST_SENTINEL": "kept"},
        ):
            env = DATASET.solver_environment({"WASSAT_STAGE_PRE": "0"})
        self.assertNotIn("WASSAT_STALE_EXPERIMENT", env)
        self.assertEqual(env["WASSAT_STAGE_PRE"], "0")
        self.assertEqual(env["ROUTER_TEST_SENTINEL"], "kept")

    def test_published_unknown_accepts_checked_sat_but_not_unchecked_unsat(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unit.cnf"
            path.write_text("p cnf 1 1\n1 0\n", encoding="ascii")
            sat = DATASET.classify_run(
                path,
                "unknown",
                [
                    "/bin/sh",
                    "-c",
                    "printf 's SATISFIABLE\\nv 1 0\\n'; exit 10",
                ],
                DATASET.solver_environment({}),
                1.0,
            )
            unsat = DATASET.classify_run(
                path,
                "unknown",
                ["/bin/sh", "-c", "printf 's UNSATISFIABLE\\n'; exit 20"],
                DATASET.solver_environment({}),
                1.0,
            )
        self.assertEqual(sat["status"], "sat")
        self.assertTrue(sat["verified"])
        self.assertEqual(unsat["status"], "unknown")
        self.assertFalse(unsat["verified"])
        self.assertIn("not proof-validated", unsat["error"])

    def test_resume_rejects_feature_schema_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runs.jsonl"
            path.write_text(
                json.dumps(
                    {
                        "record_type": "instance",
                        "schema_version": DATASET.SCHEMA_VERSION,
                        "feature_version": DATASET.FEATURE_VERSION,
                        "feature_schema_version": DATASET.FEATURE_SCHEMA_VERSION,
                        "feature_schema_sha256": "0" * 64,
                        "feature_names": DATASET.FEATURE_NAMES,
                        "instance_sha256": "0" * 64,
                    }
                )
                + "\n"
            )
            with self.assertRaisesRegex(ValueError, "incompatible"):
                DATASET.load_completed(path)


if __name__ == "__main__":
    unittest.main()
