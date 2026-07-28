#!/usr/bin/env python3
"""Per-row noise floor: how big must an effect be before it is real?

    WASSAT=/path/to/wassat python3 benchmarks/noise.py [--reps 11]

wassat's --fast path races nondeterministic arms, so several benchmark rows are
multi-modal: two full-suite runs of the SAME configuration, each already a
median of 3, have differed by up to 4.1x. That makes a 3-rep median useless for
deciding anything on those rows, and it is why two conclusions in this
campaign had to be retracted.

This runs ONE configuration many times per row and reports the spread, so a
later A/B can be judged against a number instead of a hope. The key column is
`min-detect`: the ratio a change must beat on that row before it can be
distinguished from run-to-run variation at all. It is derived from the
bootstrap spread of the median, not from the raw range, because the median of
k reps is what an A/B actually compares.

Rows default to the ones every open question lives on plus two stable
controls; pass --rows a,b,c to override.
"""
from __future__ import annotations

import argparse
import os
import random
import statistics
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reference as R  # noqa: E402

DEFAULT_ROWS = [
    # the rows every open question lives on
    "em_7_3_6_fbc", "bench_1614.smt2", "crusti_g2io_200_0.1_127_14.af_151",
    "Carry_Bits_Fast_12", "qg5-13", "qg3-09", "ais8.mis-97.debugged",
    "shuffling-1-s1722048485-of-bench-s", "minand064",
    # controls that have looked stable all campaign
    "uuf250-01", "bmc-ibm-6",
]

ap = argparse.ArgumentParser()
ap.add_argument("--reps", type=int, default=11)
ap.add_argument("--budget", type=float, default=120.0)
ap.add_argument("--rows", default="")
ap.add_argument("--sub-reps", type=int, default=3,
                help="k in 'median of k' -- the statistic an A/B would use")
args = ap.parse_args()

WASSAT = os.environ.get("WASSAT", str(R.ROOT / "bin" / "wassat"))
want = [r.strip() for r in args.rows.split(",") if r.strip()] or DEFAULT_ROWS

paths: dict[str, str] = {}
for name, path in R.PARITY:
    if Path(path).exists():
        paths[name] = path
for _fam, name, rel, _e in R.SURVEY:
    p = R.EXT / rel
    if p.exists():
        paths[name] = str(p)
for _fam, name, rel, _e, *_ in R.COMPETITION:
    p = R.SC2026 / rel
    if p.exists():
        paths[name] = str(p)

rows = [(n, paths[n]) for n in want if n in paths]
missing = [n for n in want if n not in paths]
print(f"binary: {WASSAT}")
print(f"{len(rows)} rows x {args.reps} reps, budget {args.budget}s"
      + (f"   MISSING: {', '.join(missing)}" if missing else ""))
print()


def once(path: str) -> float:
    t0 = time.perf_counter()
    try:
        subprocess.run([WASSAT, path, "--fast"], capture_output=True,
                       text=True, timeout=args.budget)
    except subprocess.TimeoutExpired:
        return args.budget
    return time.perf_counter() - t0


def median_of_k_spread(samples: list[float], k: int, trials: int = 2000) -> float:
    """Bootstrap: ratio between the 90th and 10th percentile of median-of-k.

    This is the quantity that matters -- an A/B compares two median-of-k
    numbers, so an effect smaller than this spread cannot be told from luck.
    """
    rng = random.Random(20260728)
    meds = [statistics.median(rng.choices(samples, k=k)) for _ in range(trials)]
    meds.sort()
    lo = meds[int(0.10 * trials)]
    hi = meds[int(0.90 * trials)]
    return hi / max(lo, 1e-9)


print(f"{'row':<36}{'median':>9}{'min':>8}{'max':>8}{'raw':>7}{'min-detect':>12}")
print("-" * 80)
results = []
for name, path in rows:
    samples = [once(path) for _ in range(args.reps)]
    med = statistics.median(samples)
    detect = median_of_k_spread(samples, args.sub_reps)
    results.append((name, med, min(samples), max(samples), detect))
    print(f"{name[:35]:<36}{med:9.2f}{min(samples):8.2f}{max(samples):8.2f}"
          f"{max(samples)/max(min(samples),0.01):7.1f}x{detect:11.2f}x", flush=True)

print()
noisy = [r for r in results if r[4] > 1.15]
if noisy:
    print(f"Rows where a median-of-{args.sub_reps} A/B cannot resolve better than "
          f"the stated ratio -- do NOT trust single-row results here:")
    for n, _m, _lo, _hi, d in sorted(noisy, key=lambda r: -r[4]):
        print(f"  {n[:38]:<40} needs > {d:.2f}x to be real")
else:
    print(f"No row exceeds 1.15x at median-of-{args.sub_reps}.")
