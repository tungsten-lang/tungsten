#!/usr/bin/env python3
"""Replay the exact two-round projection/basis/walk feedback lineage."""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from verify_retained_wide_auto_loop import verify_bundle  # noqa: E402

result = verify_bundle(HERE)
if result != {"tensors": 9, "best": {
        "20x21x25": 5829, "20x21x24": 5563,
        "20x20x25": 5507, "20x19x25": 5364}}:
    raise ValueError(f"unexpected retained campaign: {result}")
print("PASS nine exact GF(2) tensors and two-round feedback lineage")
