#!/usr/bin/env python3
"""Focused independent tensor check of the retained rank-962 witness."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
CHECKER = (ROOT / "bits/tungsten-metaflip/tools/"
           "check_7x13x16_directed_20260924.py")


class DirectedCertificateTest(unittest.TestCase):
    def test_retained_full_tensor(self):
        result = json.loads(subprocess.check_output(
            ["python3", str(CHECKER)], text=True))
        self.assertEqual((result["field"], result["record_claim"],
                          result["shape"], result["rank"], result["sha256"],
                          result["walks_replayed"], result["closure_gains"]),
                         ("GF(2)", False, [7, 16, 13], 962,
                          "7b44f3a6402e5d9a3c0e82c80215fa99ee0a964354d8a3c06885d924d3b7a4ca",
                          False, None))


if __name__ == "__main__":
    unittest.main()
