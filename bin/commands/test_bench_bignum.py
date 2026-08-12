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


class ExternalCellTimeoutTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        fixture = Path(self.temporary.name) / "fake-external"
        fixture.write_text(
            """#!/usr/bin/env python3
import sys
import time

_, marker, operation, limbs, runs, target_ms = sys.argv
assert marker == "--sweep"
if limbs == "2":
    time.sleep(0.5)
print(f"external\\todin\\t{operation}\\t{limbs}\\t17\\t3.5")
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
                "odin", "add", [1, 2, 3], 1, 1.0, 0.2
            )

        self.assertEqual(rows[1]["status"], "ok")
        self.assertEqual(rows[2], {
            "status": "timeout",
            "timeout_seconds": 0.2,
        })
        self.assertEqual(rows[3]["status"], "ok")
        self.assertIn("odin/add/2 timed out after 0.2s", stderr.getvalue())

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
            BENCH.add_external_lanes(rows, ["odin"], 1, 1.0, 0.2)
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


if __name__ == "__main__":
    unittest.main()
