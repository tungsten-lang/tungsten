#!/usr/bin/env python3
"""Replay this retained direct-walk lineage."""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from verify_retained_wide_auto_loop import verify_bundle  # noqa: E402

result = verify_bundle(HERE)
assert result == {"tensors": 2, "best": {"20x22x25": 6073}}
print("PASS two exact GF(2) tensors and direct-walk provenance")
