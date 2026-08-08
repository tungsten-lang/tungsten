#!/usr/bin/env python3
"""Regression tests for the SAT Competition output checker."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from check_output import check_output, parse_cnf


class CompetitionOutputTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="wassat-output-check-")
        self.tmp = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, name: str, text: str) -> Path:
        path = self.tmp / name
        path.write_text(text, encoding="ascii")
        return path

    def assert_rejected(self, cnf: Path, output: str, expected: str, code: int) -> None:
        stdout = self.write("solver.out", output)
        with self.assertRaises(SystemExit):
            check_output(cnf, stdout, expected, code)

    def test_accepts_split_partial_sat_model_that_satisfies_every_clause(self) -> None:
        cnf = self.write("sat.cnf", "c fixture\np cnf 4 3\n1 -2 0\n3 0\n-4 2 0\n")
        stdout = self.write(
            "sat.out",
            "c solver note\ns SATISFIABLE\nv 1 3\nv -4 0\n",
        )
        check_output(cnf, stdout, "SAT", 10)

    def test_accepts_unsat_without_model(self) -> None:
        cnf = self.write("unsat.cnf", "p cnf 1 2\n1 0\n-1 0\n")
        stdout = self.write("unsat.out", "s UNSATISFIABLE\nc conflicts 1\n")
        check_output(cnf, stdout, "UNSAT", 20)

    def test_rejects_wrong_exit_or_duplicate_status(self) -> None:
        cnf = self.write("sat.cnf", "p cnf 1 1\n1 0\n")
        self.assert_rejected(cnf, "s SATISFIABLE\nv 1 0\n", "SAT", 0)
        self.assert_rejected(
            cnf,
            "s SATISFIABLE\ns SATISFIABLE\nv 1 0\n",
            "SAT",
            10,
        )

    def test_rejects_invalid_model_terminators_and_conflicting_literals(self) -> None:
        cnf = self.write("sat.cnf", "p cnf 2 1\n1 2 0\n")
        self.assert_rejected(cnf, "s SATISFIABLE\nv 1\n", "SAT", 10)
        self.assert_rejected(cnf, "s SATISFIABLE\nv 1 0\nv 2 0\n", "SAT", 10)
        self.assert_rejected(cnf, "s SATISFIABLE\nv 1 -1 0\n", "SAT", 10)

    def test_rejects_out_of_range_or_non_satisfying_models(self) -> None:
        cnf = self.write("sat.cnf", "p cnf 2 2\n1 0\n-2 0\n")
        self.assert_rejected(cnf, "s SATISFIABLE\nv 1 -3 0\n", "SAT", 10)
        self.assert_rejected(cnf, "s SATISFIABLE\nv -1 -2 0\n", "SAT", 10)

    def test_rejects_model_lines_over_the_competition_limit(self) -> None:
        cnf = self.write("sat.cnf", "p cnf 1 1\n1 0\n")
        line = "v " + ("1 " * 2048) + "0\n"
        self.assertGreater(len(line.rstrip("\n")), 4096)
        self.assert_rejected(cnf, "s SATISFIABLE\n" + line, "SAT", 10)

    def test_rejects_non_competition_stdout(self) -> None:
        cnf = self.write("sat.cnf", "p cnf 1 1\n1 0\n")
        self.assert_rejected(
            cnf,
            "debug: starting\ns SATISFIABLE\nv 1 0\n",
            "SAT",
            10,
        )

    def test_dimacs_parser_rejects_malformed_or_unterminated_input(self) -> None:
        malformed = self.write("malformed.cnf", "p cnf 2 1\np cnf 2 1\n1 0\n")
        unterminated = self.write("unterminated.cnf", "p cnf 2 1\n1 2\n")
        wrong_count = self.write("wrong-count.cnf", "p cnf 2 2\n1 0\n")
        for cnf in (malformed, unterminated, wrong_count):
            with self.subTest(cnf=cnf.name), self.assertRaises(SystemExit):
                parse_cnf(cnf)


if __name__ == "__main__":
    unittest.main()
