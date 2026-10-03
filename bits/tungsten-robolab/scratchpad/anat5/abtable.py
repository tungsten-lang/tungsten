"""abtable: summarise gait_probe json outputs (out/fly_<name>.json) side by side and, for two arms on the SAME starts, the paired differences.

  .venv/bin/python scratchpad/anat5/abtable.py NAME1 NAME2 ...           table of every named run
  .venv/bin/python scratchpad/anat5/abtable.py --pair A B                 paired v(B) - v(A) over the starts both survive: mean, 95 % bootstrap CI, sign-flip p
"""
import json, sys, numpy as np
KEYS = [("task_steady_speed", "steady m/s", 3), ("peak_speed_1s", "peak1s", 3), ("fold", "fold deg", 1), ("fold_max", "fold max", 0), ("gain100", "gain100", 1), ("heel_zpk", "heel@fold m", 3),
        ("heel_hip", "heel-hip m", 3), ("cadence", "touchdowns/s", 2), ("task_step_freq", "task step_freq", 2), ("swing_t", "swing s", 3), ("contact_t", "contact s", 3), ("task_step_length", "step m", 2)]
def load(n):
    d = json.load(open(f"scratchpad/anat5/out/fly_{n}.json")); return d["rows"]
def surv(rows): return [r for r in rows if not r["fell"]]
def table(names):
    print(f"{'run':38s} {'n':>3s} {'falls':>5s} " + " ".join(f"{k[1]:>14s}" for k in KEYS))
    for n in names:
        rows = load(n); s = surv(rows)
        print(f"{n:38s} {len(rows):3d} {len(rows) - len(s):5d} " + " ".join(f"{np.mean([r[k[0]] for r in s]):14.{k[2]}f}" if s and k[0] in s[0] else f"{'-':>14s}" for k in KEYS))
def pair(a, b, seed=0):
    ra = {r["seed"]: r for r in load(a)}; rb = {r["seed"]: r for r in load(b)}
    both = [s for s in ra if s in rb and not ra[s]["fell"] and not rb[s]["fell"]]
    print(f"paired {b} - {a} over {len(both)} starts both survive (falls A {sum(r['fell'] for r in ra.values())}, B {sum(r['fell'] for r in rb.values())} of {len(ra)})")
    rng = np.random.default_rng(seed)
    for k, lab, prec in KEYS:
        if k not in ra[both[0]]: continue
        d = np.array([rb[s][k] - ra[s][k] for s in both])
        bs = [rng.choice(d, len(d)).mean() for _ in range(4000)]
        flips = [(d * rng.choice([-1, 1], len(d))).mean() for _ in range(4000)]
        p = float(np.mean(np.abs(flips) >= abs(d.mean()) - 1e-12))
        print(f"  {lab:>16s}: {d.mean():+.{prec}f}  CI95 [{np.percentile(bs, 2.5):+.{prec}f}, {np.percentile(bs, 97.5):+.{prec}f}]  p {p:.4f}")
if sys.argv[1] == "--pair": pair(sys.argv[2], sys.argv[3])
else: table(sys.argv[1:])
