#!/usr/bin/env python3
"""Replay this retained wide-auto-loop lineage."""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from verify_retained_wide_auto_loop import verify_bundle  # noqa: E402

result = verify_bundle(HERE)
assert result == {"tensors": 5, "best": {
    "16x17x21": 3321, "16x17x20": 3138, "16x17x19": 3045}}
print("PASS five exact GF(2) tensors and their projection/basis lineage")
