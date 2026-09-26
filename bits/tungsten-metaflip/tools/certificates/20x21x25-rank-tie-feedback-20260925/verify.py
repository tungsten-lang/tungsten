#!/usr/bin/env python3
"""Replay the retained rank-tie/projection/walk feedback lineage."""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from verify_retained_wide_auto_loop import verify_bundle  # noqa: E402

result = verify_bundle(HERE)
assert result == {"tensors": 4, "best": {
    "20x22x25": 6073, "20x21x25": 5829}}
print("PASS four exact GF(2) tensors and rank-tie feedback lineage")
