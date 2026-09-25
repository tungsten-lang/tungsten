#!/usr/bin/env python3
"""Replay this retained wide-auto-loop lineage."""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from verify_retained_wide_auto_loop import verify_bundle  # noqa: E402

result = verify_bundle(HERE)
assert result == {"tensors": 5, "best": {
    "16x23x22": 4618, "16x23x21": 4497}}
print("PASS five exact GF(2) tensors and their projection/basis lineage")
