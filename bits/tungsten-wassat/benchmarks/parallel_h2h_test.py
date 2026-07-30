#!/usr/bin/env python3
"""Focused tests for the SC2026 Wassat/Green comparison harness."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import signal
import sys
import tempfile
import unittest

import parallel_h2h as h2h


class ParallelH2HTest(unittest.TestCase):
    def test_strict_output_accepts_4096_and_rejects_4097_character_value_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = "v 1" + (" " * (4096 - len("v 1") - len(" 0"))) + " 0"
            self.assertEqual(len(accepted), 4096)
            good = root / "good.out"
            good.write_text("s SATISFIABLE\n" + accepted + "\n", encoding="ascii")
            parsed = h2h.competition_output(good)
            self.assertEqual(parsed["verdict"], "sat")
            self.assertIsNone(parsed["error"])
            self.assertEqual(parsed["assignment"], {1: True})

            bad = root / "bad.out"
            bad.write_text(
                "s SATISFIABLE\n" + accepted[:-2] + "  0\n", encoding="ascii"
            )
            self.assertEqual(len(bad.read_text().splitlines()[1]), 4097)
            parsed = h2h.competition_output(bad)
            self.assertEqual(parsed["verdict"], "none")
            self.assertIn("exceeds 4096", parsed["error"])

    def test_streaming_model_check_requires_every_clause(self):
        with tempfile.TemporaryDirectory() as directory:
            cnf = Path(directory) / "tiny.cnf"
            cnf.write_text("p cnf 3 2\n1 -2 0\n2 3 0\n", encoding="ascii")
            self.assertEqual(
                h2h.model_satisfies(cnf, {1: True, 2: True}),
                (True, None),
            )
            valid, error = h2h.model_satisfies(cnf, {1: False, 2: True})
            self.assertFalse(valid)
            self.assertIn("unsatisfied clause", error)

    def test_exact_manifest_rejects_extra_cnf(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scores = root / "scores.csv"
            hashes = ["0" * 31 + "1", "0" * 31 + "2"]
            with scores.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(
                    stream,
                    fieldnames=[
                        "solverid",
                        "instanceid",
                        "runtime",
                        "status",
                        "score",
                        "vresult",
                    ],
                )
                writer.writeheader()
                writer.writerow(
                    {
                        "solverid": "solver",
                        "instanceid": hashes[0],
                        "runtime": "1",
                        "status": "sat-verified",
                        "score": "1",
                        "vresult": "sat",
                    }
                )
                writer.writerow(
                    {
                        "solverid": "solver",
                        "instanceid": hashes[1],
                        "runtime": "1",
                        "status": "solver-timeout",
                        "score": "2",
                        "vresult": "",
                    }
                )
            (root / "a.cnf").write_text("p cnf 1 1\n1 0\n", encoding="ascii")
            (root / "b.cnf").write_text("p cnf 1 1\n-1 0\n", encoding="ascii")
            (root / "index.json").write_text(
                json.dumps(
                    {
                        "a": {"hash": hashes[0], "verdict": "sat"},
                        "b": {"hash": hashes[1], "verdict": "unknown"},
                    }
                ),
                encoding="utf-8",
            )
            instances, _hashes = h2h.validate_manifest(
                root, scores, expected_count=2
            )
            self.assertEqual(len(instances), 2)

            (root / "extra.cnf").write_text("p cnf 0 0\n", encoding="ascii")
            with self.assertRaisesRegex(ValueError, "CNF/index coverage"):
                h2h.validate_manifest(root, scores, expected_count=2)

    def test_timeout_kills_process_group(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stdout = root / "stdout"
            stderr = root / "stderr"
            command = [
                sys.executable,
                "-c",
                (
                    "import subprocess,sys,time;"
                    "subprocess.Popen([sys.executable,'-c','import time;"
                    "time.sleep(60)']);"
                    "time.sleep(60)"
                ),
            ]
            result = h2h.run_process(
                command, stdout, stderr, timeout=0.1, term_grace=0.1
            )
            self.assertTrue(result["timed_out"])
            self.assertIn(
                result["sent_signal"], (int(signal.SIGTERM), int(signal.SIGKILL))
            )

    def test_unknown_unsat_is_unverified_and_par2_in_summary(self):
        process = {
            "timed_out": False,
            "launch_error": None,
            "exit_code": 20,
        }
        parsed = {
            "verdict": "unsat",
            "assignment": {},
            "error": None,
        }
        classified = h2h.classify_result(
            process, parsed, "unknown", Path("/does/not/matter")
        )
        self.assertEqual(classified["status"], "unverified")

        results = {
            ("a", "wassat"): {
                "status": "sat",
                "elapsed": 1.0,
                "par2": 1.0,
            },
            ("a", "green"): {
                "status": "sat",
                "elapsed": 2.0,
                "par2": 2.0,
            },
            ("b", "wassat"): {
                "status": "unverified",
                "elapsed": 1.0,
                "par2": 20.0,
            },
            ("b", "green"): {
                "status": "timeout",
                "elapsed": 10.0,
                "par2": 20.0,
            },
        }
        summary = h2h.summarize(results, 2, tie_band=1.10, tie_floor=0.05)
        self.assertEqual(summary["solvers"]["wassat"]["unverified"], 1)
        self.assertEqual(summary["solvers"]["wassat"]["par2"], 21.0)
        self.assertEqual(summary["overlap"]["wassat_wins"], 1)


if __name__ == "__main__":
    unittest.main()
