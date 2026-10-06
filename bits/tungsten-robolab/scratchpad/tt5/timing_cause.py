#!/usr/bin/env python3
"""Where does the timing error come from? For every serve of sets A + B with a legal window in the shifted-replay sweep (out/tt5/shift_all.jsonl), the window's centre c (ms; negative = the stroke
would have to be EARLIER against the ball) is the timing error of that serve. Is it explained by when the ball arrives (a swing that does not follow the ball) or by the swing's own scatter?
Per serve from the champion's log: t_c = the contact tick (the ball's arrival at the pad; the closest approach for a miss), t_pk = the tick of the pad's peak speed (the swing's own clock).
    python3 scratchpad/tt5/timing_cause.py       from bits/tungsten-robolab"""
import collections
import json

import numpy as np

rows = [json.loads(l) for l in open("out/tt5/shift_all.jsonl")]
by = collections.defaultdict(dict)
for r in rows:
    by[r["seed"]][r["shift"]] = r
shifts = sorted({r["shift"] for r in rows})
rowsA = {}
for s in ("A", "B"):
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l)
        rowsA[r["seed"]] = r
feat = []
for sd in sorted(by):
    w = [x for x in shifts if (by[sd][x]["solved"] or 0) > 0]
    if not w:
        continue
    z = np.load(f"out/tt3/logs_o0/{sd}.npz", allow_pickle=True)
    L, k = z["L"], int(z["contact"])
    t = L[:, 0]
    pad = L[:, 7:10]
    ball = L[:, 1:4]
    tc = t[k - 1] if k >= 1 else t[int(np.argmin(np.linalg.norm(ball - pad, axis=1)))]
    sp = np.linalg.norm(np.gradient(pad, t, axis=0), axis=1)
    kmax = k + 3 if k >= 0 else len(t)
    tpk = t[int(np.argmax(sp[:kmax]))]
    # swing start: first tick the pad speed exceeds 0.6 m/s after 0.15 s
    st = t[next((i for i in range(len(t)) if t[i] > 0.15 and sp[i] > 0.6), 0)]
    serve = rowsA[sd]["serve"]
    feat.append(dict(seed=sd, c=1000 * float(np.mean(w)), tc=float(tc), tpk=float(tpk), tst=float(st), vx=serve[3], vz=serve[5], vy=serve[4], z0=serve[2], side=rowsA[sd].get("side"),
                     onset=rowsA[sd].get("pelvis_onset")))
c = np.array([f["c"] for f in feat])
print(f"{len(feat)} serves with a legal window; timing error c: median {np.median(c):+.0f} ms, sd {np.std(c):.0f} ms")
def col(k): return np.array([f[k] if f[k] is not None else np.nan for f in feat], float)
for name in ("tc", "tpk", "tst", "vx", "vz", "vy", "z0", "onset"):
    x = col(name)
    ok = ~np.isnan(x)
    r = np.corrcoef(x[ok], c[ok])[0, 1]
    print(f"   corr(c, {name:5s}) = {r:+.2f}   (sd of {name}: {np.std(x[ok]) * (1000 if name in ('tc', 'tpk', 'tst', 'onset') else 1):.1f}{' ms' if name in ('tc', 'tpk', 'tst', 'onset') else ''})")
tc, tpk, tst = col("tc"), col("tpk"), col("tst")
print(f"   ball arrival t_c: sd {1000 * np.std(tc):.0f} ms; swing clock t_pk: sd {1000 * np.std(tpk):.0f} ms; t_pk - t_c: median {1000 * np.median(tpk - tc):+.0f} ms, sd {1000 * np.std(tpk - tc):.0f} ms; corr(t_pk, t_c) = {np.corrcoef(tpk, tc)[0, 1]:+.2f}")
print("   (a swing that follows the ball has t_pk - t_c constant (sd ~ 0) and corr(t_pk, t_c) near 1; a swing on its own clock has sd(t_pk) small while sd(t_c) is not)")
# linear model of c on t_c and t_pk
A = np.c_[np.ones(len(c)), tc * 1000, tpk * 1000]
beta, *_ = np.linalg.lstsq(A, c, rcond=None)
res = c - A @ beta
print(f"   c ~ a + b t_c + d t_pk: b {beta[1]:+.2f}, d {beta[2]:+.2f}; residual sd {np.std(res):.0f} ms (of {np.std(c):.0f} ms)")
