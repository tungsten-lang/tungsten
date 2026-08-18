#!/usr/bin/env python3
"""Focused tests for optional bignum-lane cell deadlines."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import stat
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("bench-bignum.py")
SPEC = importlib.util.spec_from_file_location("bench_bignum", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
BENCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCH)


class SingleCellSelectionTest(unittest.TestCase):
    def test_cell_selects_one_operation_and_shape(self) -> None:
        parser = BENCH.build_parser()
        args = parser.parse_args(["--cell", "sub@48"])
        BENCH.apply_cell_selection(args, parser)

        self.assertEqual(args.operations, "sub")
        self.assertEqual(args.sizes, "48")
        self.assertTrue(args.no_capacity)

    def test_cell_keeps_measurement_options(self) -> None:
        parser = BENCH.build_parser()
        args = parser.parse_args(
            ["--cell", "mul@4", "--accurate", "--runs", "11"]
        )
        BENCH.apply_cell_selection(args, parser)

        self.assertTrue(args.accurate)
        self.assertEqual(args.runs, 11)

    def test_cell_rejects_matrix_selectors(self) -> None:
        parser = BENCH.build_parser()
        args = parser.parse_args(
            ["--cell", "sub@48", "--operations", "sub"]
        )
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                BENCH.apply_cell_selection(args, parser)

    def test_cell_rejects_invalid_shape(self) -> None:
        parser = BENCH.build_parser()
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                parser.parse_args(["--cell", "sub:48"])

    def test_cell_rejects_operation_size_cap(self) -> None:
        parser = BENCH.build_parser()
        args = parser.parse_args(["--cell", "pow@257"])
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                BENCH.apply_cell_selection(args, parser)


class ExternalCellTimeoutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        fixture = Path(self.temporary.name) / "fake-external"
        fixture.write_text(
            """#!/bin/sh
set -eu
test "$1" = "--sweep"
operation=$2
limbs=$3
if test "$limbs" = "2"; then
    sleep 2
fi
printf 'external\\todin\\t%s\\t%s\\t17\\t3.5\\n' "$operation" "$limbs"
"""
        )
        fixture.chmod(fixture.stat().st_mode | stat.S_IXUSR)
        self.original = BENCH.EXTERNAL_BINARIES["odin"]
        BENCH.EXTERNAL_BINARIES["odin"] = fixture

    def tearDown(self) -> None:
        BENCH.EXTERNAL_BINARIES["odin"] = self.original
        self.temporary.cleanup()

    def test_timeout_is_recorded_and_later_cells_continue(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rows = BENCH.external_sweep(
                "odin", "add", [1, 2, 3], 1, 1.0, 1.0
            )

        self.assertEqual(rows[1]["status"], "ok")
        self.assertEqual(rows[2], {
            "status": "timeout",
            "timeout_seconds": 1.0,
        })
        self.assertEqual(rows[3]["status"], "ok")
        self.assertIn("odin/add/2 timed out after 1s", stderr.getvalue())

    def test_timeout_is_excluded_from_ratios_and_printed(self) -> None:
        rows = [
            {
                "operation": "add",
                "limbs": limbs,
                "bits": limbs * 64,
                "native_iterations": 17,
                "tungsten_ns": 2.0,
                "gmp_ns": 2.5,
                "tungsten_over_gmp": 0.8,
                "fastest": "tungsten",
            }
            for limbs in (1, 2, 3)
        ]
        with contextlib.redirect_stderr(io.StringIO()):
            BENCH.add_external_lanes(rows, ["odin"], 1, 1.0, 1.0)
        for row in rows:
            BENCH.update_fastest(row, ["tungsten", "gmp", "odin"])

        aggregate = BENCH.aggregate_results(
            rows, ["tungsten", "gmp", "odin"]
        )
        self.assertEqual(aggregate["overall"]["odin"]["cases"], 2)
        self.assertEqual(aggregate["overall"]["odin"]["timeouts"], 1)
        self.assertNotIn("tungsten_over_odin", rows[1])

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            BENCH.print_result_row(
                rows[1], ["tungsten", "gmp", "odin"]
            )
        self.assertIn("TIMEOUT", output.getvalue())


class ExternalUnsupportedOperationTest(unittest.TestCase):
    """Per-language unsupported operations must not invoke the harness."""

    def setUp(self) -> None:
        self.original = BENCH.EXTERNAL_BINARIES["node"]
        # Any attempt to execute the lane fails loudly.
        BENCH.EXTERNAL_BINARIES["node"] = Path("/nonexistent-node-harness")

    def tearDown(self) -> None:
        BENCH.EXTERNAL_BINARIES["node"] = self.original

    @staticmethod
    def make_rows(operation: str) -> list[dict]:
        return [
            {
                "operation": operation,
                "limbs": limbs,
                "bits": limbs * 64,
                "native_iterations": 17,
                "tungsten_ns": 2.0,
                "gmp_ns": 2.5,
                "tungsten_over_gmp": 0.8,
                "fastest": "tungsten",
            }
            for limbs in (1, 2)
        ]

    def test_node_gcd_is_marked_unsupported_without_running(self) -> None:
        for operation in sorted(BENCH.EXTERNAL_UNSUPPORTED["node"]):
            rows = self.make_rows(operation)
            BENCH.add_external_lanes(rows, ["node"], 1, 1.0, 0.0)
            for row in rows:
                self.assertEqual(row["node_status"], "unsupported")
                self.assertNotIn("node_ns", row)

    def test_asymmetric_rows_run_on_supporting_lanes(self) -> None:
        # Every external harness implements the one-limb word rows; the
        # fixture stands in for the odin binary and must be invoked.
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "fake-external"
            fixture.write_text(
                "#!/bin/sh\n"
                "printf 'external\\todin\\t%s\\t%s\\t17\\t3.5\\n' \"$2\" \"$3\"\n"
            )
            fixture.chmod(fixture.stat().st_mode | stat.S_IXUSR)
            original = BENCH.EXTERNAL_BINARIES["odin"]
            BENCH.EXTERNAL_BINARIES["odin"] = fixture
            try:
                rows = self.make_rows("add1")
                BENCH.add_external_lanes(rows, ["odin"], 1, 1.0, 0.0)
            finally:
                BENCH.EXTERNAL_BINARIES["odin"] = original
        for row in rows:
            self.assertEqual(row["odin_status"], "ok")
            self.assertEqual(row["odin_ns"], 3.5)

    def test_unsupported_cells_are_printed_as_na(self) -> None:
        rows = self.make_rows("gcd")
        BENCH.add_external_lanes(rows, ["node"], 1, 1.0, 0.0)
        BENCH.update_fastest(rows[0], ["tungsten", "gmp", "node"])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            BENCH.print_result_row(rows[0], ["tungsten", "gmp", "node"])
        self.assertIn("N/A", output.getvalue())


class ExternalCommandTest(unittest.TestCase):
    def test_node_lane_runs_through_the_interpreter(self) -> None:
        command = BENCH.external_command("node")
        self.assertEqual(command[0], "node")
        self.assertEqual(Path(command[1]).name, "main.mjs")

    def test_native_lanes_execute_their_binary(self) -> None:
        for language in ("tungsten_native", "rust", "odin", "go", "boost"):
            command = BENCH.external_command(language)
            self.assertEqual(len(command), 1)


class TungstenNativeLaneTest(unittest.TestCase):
    def test_strong_isqrt_seam_is_checked_before_lto_internalization(self) -> None:
        self.assertTrue(
            BENCH.tungsten_native_ir_has_strong_isqrt(
                "define i64 @__w_bigint_isqrt_src(i64 %a) nounwind {\n}"
            )
        )
        self.assertFalse(
            BENCH.tungsten_native_ir_has_strong_isqrt(
                "declare i64 @__w_bigint_isqrt_src(i64) nounwind"
            )
        )

    def test_closed_world_contracts_follow_all_definitions(self) -> None:
        program = BENCH.TUNGSTEN_NATIVE_SOURCE.read_text()
        protect = program.index("Tungsten.PROTECT_THE_CORE!")
        lock = program.index("Tungsten.LOCK_THE_DOORS!")

        self.assertLess(protect, lock)
        self.assertLess(program.rindex("-> ", 0, protect), protect)
        self.assertNotIn("-> ", program[lock:])

    def test_native_lane_is_distinct_from_the_c_runtime_lane(self) -> None:
        self.assertEqual(BENCH.LANE_LABELS["tungsten"], "Tungsten C")
        self.assertEqual(
            BENCH.LANE_LABELS["tungsten_native"], "Tungsten"
        )
        self.assertEqual(BENCH.RATIO_LABELS["tungsten_native"], "C/native")

    def test_native_fastest_label_is_clear_in_the_table(self) -> None:
        row = {
            "operation": "gcd",
            "limbs": 1,
            "bits": 64,
            "native_iterations": 7,
            "tungsten_ns": 2.0,
            "tungsten_native_ns": 1.0,
            "gmp_ns": 3.0,
            "tungsten_over_tungsten_native": 2.0,
            "tungsten_over_gmp": 2.0 / 3.0,
            "fastest": "tungsten_native",
        }
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            BENCH.print_result_row(
                row, ["tungsten", "tungsten_native", "gmp"]
            )
        self.assertTrue(
            output.getvalue().rstrip().endswith("tungsten-native")
        )
        self.assertNotIn("tungsten_native", output.getvalue())

        row["fastest"] = "tungsten"
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            BENCH.print_result_row(
                row, ["tungsten", "tungsten_native", "gmp"]
            )
        self.assertTrue(output.getvalue().rstrip().endswith("tungsten"))


if __name__ == "__main__":
    unittest.main()
