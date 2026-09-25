#!/usr/bin/env python3
"""Focused independent tensor check of the retained rank-872 witness."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
CHECKER = (ROOT / "bits/tungsten-metaflip/tools/"
           "check_7x12x16_directed_20260925.py")


class DirectedCertificateTest(unittest.TestCase):
    def test_retained_full_tensor(self):
        result = json.loads(subprocess.check_output(
            ["python3", str(CHECKER)], text=True))
        self.assertEqual((result["field"], result["record_claim"],
                          result["shape"], result["rank"], result["sha256"],
                          result["walks_replayed"], result["closure_gains"]),
                         ("GF(2)", False, [7, 16, 12], 872,
                          "8117a6eab7d35eefae49e4ca4165b3ca329e2880ddd91581443ea5caafc93fe8",
                          False, None))


if __name__ == "__main__":
    unittest.main()
