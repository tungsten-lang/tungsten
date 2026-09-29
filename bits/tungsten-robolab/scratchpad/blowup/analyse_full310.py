"""Unbiased 310 s statistics of the guarded runs: the real guarded runs of the passing starts (full310.py -> evals/full310-<entry>.json) joined with the
real re-runs of the failing starts (the arena rows of the 310_40_ng trial that carry telemetry), i.e. all 40 starts of an entry run for real.

usage: analyse_full310.py [lift shc ramp]
Per entry: pass count, NaN events (all tendons) and start-seconds, the sliver states of recfem_r (survived + NaN) with their exact 1 - dot, P(NaN | sliver state),
the expected events from the P(NaN | 1 - dot) table, and the hover fractions (substeps within 1e-4 / 1e-5 / 1e-6 of the tangent); then paired comparisons between entries."""
import glob
import json
import math
import os
import random
import sys

HERE = "/Users/erik/tungsten/bits/tungsten-robolab"
ARMS = {"lift": ("soccer5-lift", "lift"), "ramp": ("soccer6-i", "ramp"), "shc": ("soccer6-p", "brake")}
which = [a for a in sys.argv[1:] if a in ARMS] or ["lift", "shc"]
trial_seeds = list(range(89100, 89140))


def pois_ci(k, z=1.96):
    lo = 0.0 if k == 0 else k * (1 - 1 / (9 * k) - z / (3 * math.sqrt(k))) ** 3
    hi = (k + 1) * (1 - 1 / (9 * (k + 1)) + z / (3 * math.sqrt(k + 1))) ** 3
    return max(lo, 0.0), hi


def wilson(k, n, z=1.96):
    if n == 0:
        return 0.0, 1.0
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return c - h, c + h


def hist(r):
    h = r.get("wrap_r_hist")
    if not h:
        return None
    a, b = h.split("|")
    return [int(x) for x in a.split(",")], [int(x) for x in b.split(",")]


data = {}
for arm in which:
    tag, name = ARMS[arm]
    arena_file = sorted(glob.glob(os.path.join(HERE, "scratchpad", "blowup", "evals", f"bal1_300-{tag}-*.json")))[-1]
    A = json.load(open(arena_file))
    full = json.load(open(os.path.join(HERE, "scratchpad", "blowup", "evals", f"full310-{arm}.json"))) if os.path.exists(os.path.join(HERE, "scratchpad", "blowup", "evals", f"full310-{arm}.json")) else {}
    rows = {}
    for s, r in zip(A["seeds"], A["rows"]):
        if "primed_from" not in r:
            rows[s] = r                                   # a real guarded re-run of a failing start
        elif str(s) in full:
            rows[s] = full[str(s)]                        # a real guarded run of a passing start
    data[arm] = rows
    print(f"{arm}: {len(rows)} of 40 starts run for real under the guard ({sum(1 for s in rows if str(s) in full)} full 310 s passing runs + {sum(1 for s, r in zip(A['seeds'], A['rows']) if 'primed_from' not in r)} arena re-runs)")

for arm in which:
    rows = data[arm]
    if len(rows) < 40:
        print(f"  ({arm}: only {len(rows)} starts done, statistics are partial)")
    secs = sum(float(r.get("time") or 0) for r in rows.values())
    ev = sum(int(r.get("nan_events") or 0) for r in rows.values())
    starts_ev = sum(1 for r in rows.values() if (r.get("nan_events") or 0) > 0)
    tendons = sorted({t for r in rows.values() for t in (r.get("nan_tendons") or "").split(",") if t})
    mirror = sum(int(r.get("nan_mirror") or 0) for r in rows.values())
    other = sum(int(r.get("nan_other") or 0) for r in rows.values())
    passes = sum(1 for r in rows.values() if r.get("bal1_300") == 1.0)
    surv = sum(int(r.get("wrap_r_visits") or 0) for r in rows.values())
    ev_omd = [float(x) for r in rows.values() for x in (r.get("nan_omd") or "").split(";") if x]
    exp = sum(float(r.get("nan_expected") or 0) for r in rows.values())
    sub = sum(int(r.get("wrap_r_substeps") or 0) for r in rows.values())
    pos = [0] * 9
    neg = [0] * 9
    for r in rows.values():
        h = hist(r)
        if h:
            for i in range(9):
                pos[i] += h[0][i]
                neg[i] += h[1][i]
    lo, hi = pois_ci(ev)
    print(f"== {arm}: pass {passes}/{len(rows)}; NaN events {ev} (95 % {lo:.1f}..{hi:.1f}) in {starts_ev} starts, {secs:.0f} start-seconds = {1000 * ev / max(secs, 1):.2f} per 1000 start-seconds "
          f"(a hold of 310 s: {ev / max(secs, 1) * 310:.3f}); tendons {tendons}; mirror-first {mirror}, other resets {other}")
    nst = surv + len(ev_omd)
    print(f"   recfem_r sliver states (0 < margin < 1e-7): survived {surv} + NaN {len(ev_omd)} = {nst} in {sub} substeps; expected NaN from the exact-1-dot table {exp:.2f}; "
          f"P(NaN | sliver state) = {len(ev_omd) / max(nst, 1):.3f} (95 % {wilson(len(ev_omd), nst)[0]:.2f}..{wilson(len(ev_omd), nst)[1]:.2f})")
    if ev_omd:
        print("   exact 1-dot of the NaN states:", " ".join(f"{x:.1e}" for x in sorted(ev_omd)))
    for name, k in (("1e-4", 6), ("1e-5", 5), ("1e-6", 4)):
        tot = sum(pos[:k]) + sum(neg[:k])
        print(f"   substeps within {name} of the tangent: {tot} ({100 * tot / max(sub, 1):.3f} % of {sub})")

if len(which) >= 2:
    print()
    random.seed(2)

    def frac(r, k):
        h = hist(r)
        n = int(r.get("wrap_r_substeps") or 0)
        return None if not h or not n else (sum(h[0][:k]) + sum(h[1][:k])) / n
    for a, b in ((which[1], which[0]),):
        for name, k in (("1e-4", 6), ("1e-5", 5), ("1e-6", 4)):
            diffs = []
            for s in trial_seeds:
                if s in data[a] and s in data[b]:
                    fa, fb = frac(data[a][s], k), frac(data[b][s], k)
                    if fa is not None and fb is not None:
                        diffs.append(fa - fb)
            if diffs:
                m = sum(diffs) / len(diffs)
                ext = sum(1 for _ in range(20000) if abs(sum(d if random.random() < 0.5 else -d for d in diffs) / len(diffs)) >= abs(m) - 1e-15)
                print(f"paired fraction of substeps within {name} of the tangent, {a} - {b}: {m:+.5f} over {len(diffs)} starts, sign-flip p = {ext / 20000:.4f}")
