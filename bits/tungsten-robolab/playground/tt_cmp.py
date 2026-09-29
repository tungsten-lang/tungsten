"""Paired comparison of two tt_eval.py runs on the same serves (round 10).

    .venv-myo/bin/python playground/tt_cmp.py base.jsonl new.jsonl [--seeds a:b]

Prints solved / hit counts, the paired difference with a one-sided sign-flip permutation p-value (the arena's
test), McNemar-style flips, and the split by side and by serve-speed quintile.
"""

import argparse
import json
import sys

import numpy as np


def load(path):
    out = {}
    for line in open(path):
        line = line.strip()
        if line:
            r = json.loads(line)
            if "error" not in r:
                out[r["seed"]] = r
    return out


def slack(r):
    """Continuous outcome: the landing margin (m) of a hit's return (tt_impact.margin), clipped to [-0.6, 0.3];
    a miss scores -0.6 - its closest approach (m)."""
    sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
    import tt_impact as ti
    if r.get("hit") and r.get("ball_out_exact") and r.get("ball_pos_out"):
        return float(np.clip(ti.margin(r["ball_pos_out"], r["ball_out_exact"]), -0.6, 0.3))
    return -0.6 - float(r.get("miss_dist", 0.5))


def perm_p(diffs, reps=20000, seed=0):
    rng = np.random.default_rng(seed)
    d = np.asarray(diffs, float)
    n = len(d)
    if n == 0 or np.all(d == 0):
        return 1.0
    obs = d.mean()
    s = rng.choice([-1.0, 1.0], size=(reps, n))
    return float(((s * d).mean(axis=1) >= obs - 1e-12).mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("new")
    ap.add_argument("--seeds", default="")
    a = ap.parse_args()
    A, B = load(a.base), load(a.new)
    seeds = sorted(set(A) & set(B))
    if a.seeds:
        lo, hi = [int(x) for x in a.seeds.split(":")]
        seeds = [s for s in seeds if lo <= s < hi]
    n = len(seeds)
    sa = np.array([A[s]["solved"] > 0 for s in seeds], float)
    sb = np.array([B[s]["solved"] > 0 for s in seeds], float)
    ha = np.array([A[s]["hit"] > 0 for s in seeds], float)
    hb = np.array([B[s]["hit"] > 0 for s in seeds], float)
    d = sb - sa
    print(f"n {n}: solved base {int(sa.sum())} ({sa.mean():.3f}), new {int(sb.sum())} ({sb.mean():.3f}); "
          f"diff {d.mean():+.3f} +- {d.std(ddof=1) / np.sqrt(n):.3f}, p {perm_p(d):.4f}; "
          f"flips: base only {int(((sa == 1) & (sb == 0)).sum())}, new only {int(((sa == 0) & (sb == 1)).sum())}")
    print(f"hit base {ha.mean():.3f}, new {hb.mean():.3f}")
    ma = np.array([slack(A[s]) for s in seeds])
    mb = np.array([slack(B[s]) for s in seeds])
    dm = mb - ma
    print(f"landing slack (clipped, m): base {ma.mean():+.3f}, new {mb.mean():+.3f}, diff {dm.mean():+.3f} +- {dm.std(ddof=1) / np.sqrt(n):.3f}")
    side = np.array([A[s].get("side", 0) for s in seeds])
    for sd, nm in ((1, "forehand"), (2, "backhand")):
        m = side == sd
        if m.any():
            print(f"  {nm}: n {int(m.sum())}, base {sa[m].mean():.3f}, new {sb[m].mean():.3f}, diff {d[m].mean():+.3f}, p {perm_p(d[m]):.3f}")
    sp = np.array([np.linalg.norm(A[s]["serve"][3:6]) for s in seeds])
    qs = np.quantile(sp, [0, .2, .4, .6, .8, 1.0])
    for i in range(5):
        m = (sp >= qs[i]) & (sp <= qs[i + 1])
        print(f"  serve speed {qs[i]:.2f}-{qs[i + 1]:.2f}: n {int(m.sum())}, base {sa[m].mean():.3f}, new {sb[m].mean():.3f}, diff {d[m].mean():+.3f}")


if __name__ == "__main__":
    main()
