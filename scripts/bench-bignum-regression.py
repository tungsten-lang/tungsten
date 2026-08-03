#!/usr/bin/env python3
"""D6: bignum regression alarm — names op+size on any DECISIVE crossing.

Compares a fresh matrix JSON against the committed baseline and alarms
only when a cell moves across 1.0 by more than the noise floor (shared
runners and loaded boxes cannot adjudicate 1-5%; see the eng review's
P3 finding). A win (<0.95) that reads >=1.10, or the reverse, is a real
crossing; everything inside the band is reported as drift, not failure.

Usage:
  python3 bin/commands/bench-bignum.py --accurate --json --no-capacity \
      > /tmp/fresh.json
  scripts/bench-bignum-regression.py /tmp/fresh.json \
      [baseline.json]   # default: newest matrix-*.json in baselines/
Exit 1 on any decisive regression.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASELINES = ROOT / "benchmarks" / "big_math" / "baselines"

WIN_MAX = 0.95     # baseline had a real win
LOSS_MIN = 1.10    # fresh reading is a real loss


def cells(path):
    data = json.loads(pathlib.Path(path).read_text())
    return {
        (r["operation"], r["limbs"]): r["tungsten_over_gmp"]
        for r in data["results"]
        if r.get("tungsten_over_gmp", 0) > 0
    }


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    fresh = cells(sys.argv[1])
    if len(sys.argv) > 2:
        base_path = sys.argv[2]
    else:
        candidates = sorted(
            BASELINES.glob("matrix-*accurate*.json"),
            key=lambda p: p.stat().st_mtime,
        )
        if not candidates:
            print("no baseline matrix found in", BASELINES)
            return 2
        base_path = candidates[-1]
    base = cells(base_path)
    common = sorted(set(fresh) & set(base))
    regressions = []
    improvements = []
    drift = []
    for key in common:
        b, f = base[key], fresh[key]
        if b < WIN_MAX and f >= LOSS_MIN:
            regressions.append((key, b, f))
        elif b >= LOSS_MIN and f < WIN_MAX:
            improvements.append((key, b, f))
        elif (b < 1.0) != (f < 1.0):
            drift.append((key, b, f))
    print(f"regression check vs {base_path}: {len(common)} common cells")
    for (op, limbs), b, f in regressions:
        print(f"  REGRESSION {op}@{limbs}: {b:.3f} -> {f:.3f}")
    for (op, limbs), b, f in improvements:
        print(f"  improved   {op}@{limbs}: {b:.3f} -> {f:.3f}")
    for (op, limbs), b, f in drift:
        print(
            f"  drift      {op}@{limbs}: {b:.3f} -> {f:.3f}"
            " (inside noise band; not adjudicated)"
        )
    if regressions:
        print(f"FAIL: {len(regressions)} decisive regression(s)")
        return 1
    print("OK: no decisive regressions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
