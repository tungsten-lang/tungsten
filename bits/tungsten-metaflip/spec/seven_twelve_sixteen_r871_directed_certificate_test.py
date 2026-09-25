#!/usr/bin/env python3
"""Focused independent tensor checks of three rank-871 representations."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
CHECKER = (ROOT / "bits/tungsten-metaflip/tools/"
           "check_7x12x16_r871_directed_20260925.py")


class DirectedCertificateTest(unittest.TestCase):
    def test_retained_full_tensors(self):
        result = json.loads(subprocess.check_output(
            ["python3", str(CHECKER)], text=True))
        self.assertEqual((result["field"], result["record_claim"],
                          result["shape"], result["rank"],
                          result["walks_replayed"], result["closure_gains"]),
                         ("GF(2)", False, [7, 16, 12], 871, False, None))
        self.assertEqual([(row["mode"], row["rank"], row["sha256"])
                          for row in result["results"]], [
            (6, 871, "aeebdf7274633ab44a4056a689cd1beccf349845ce60d20188972adb0a3b9a60"),
            (7, 871, "5810ce9f3c9b730570445a77208e3b323f72b5938c65f1fe559c7ed89767d18a"),
            (13, 871, "9d346cb913c1359b04cc98d9454d6dad336b805949746b79f7759dab497dd9c9")])


if __name__ == "__main__":
    unittest.main()
