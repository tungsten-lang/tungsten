#!/usr/bin/env python3
"""Is a table-tennis MISS a timing problem? (Erik, 3 Oct 2026: "take a miss, then slice up the ball's path and hit the ball at each position in its path, see if we have a timing issue".)

Part A, from the champion's own per-tick logs (out/tt3/logs_o0/<seed>.npz, TT_SAVE_LOG of the plain champion on sets A 98000-98099 and B 830000-830099, 10 ms ticks): for every serve the
champion never touches (contact -1), the ball's free path is the path every other run of that serve would see until a contact. For every slice j of that path (ball centre b_j at t_j) and
every tick i of the pad's own trajectory (pad centre p_i, pad normal n_i), the pair (i, j) is a CONTACT CONFIGURATION when the ball centre sits within the pad disc (in-plane distance <= 0.093 + 0.00)
and within 0.04 + 0.01 of the pad's face along the normal. The TIME LAG of a contact configuration is t_i - t_j: how much earlier (<0) or later (>0) than the ball the pad is at that spot.
Per miss: the same-time closest approach (the miss distance) and the SMALLEST |lag| over contact configurations (None when the pad's path never passes through the ball's path).
    .venv-myo/bin/python scratchpad/tt5/miss_spacetime.py            from bits/tungsten-robolab. Read-only."""
import json
import os
import sys

import numpy as np

R_PAD, HALF_T, R_BALL = 0.093, 0.02, 0.02
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)


def load(seed):
    z = np.load(f"out/tt3/logs_o0/{seed}.npz", allow_pickle=True)
    return z["L"], int(z["contact"])


def config_lags(L, plane_tol=R_PAD, normal_tol=HALF_T + R_BALL + 0.01, t_min_ball=None):
    """All (lag, i, j, in-plane, normal) of contact configurations between the pad's trajectory (ticks i) and the ball's path (ticks j)."""
    t, ball, pad, nrm = L[:, 0], L[:, 1:4], L[:, 7:10], L[:, 13:16]
    n = nrm / np.linalg.norm(nrm, axis=1, keepdims=True)
    out = []
    for i in range(len(L)):
        d = ball - pad[i]                       # ball slices j relative to pad tick i
        dn = np.abs(d @ n[i])
        dp = np.linalg.norm(d - np.outer(d @ n[i], n[i]), axis=1)
        ok = (dp <= plane_tol) & (dn <= normal_tol)
        for j in np.nonzero(ok)[0]:
            out.append((t[i] - t[j], i, int(j), float(dp[j]), float(dn[j])))
    return out


def main():
    rows = {}
    for s in ("A", "B"):
        for l in open(f"out/tt3/o0_{s}.jsonl"):
            r = json.loads(l)
            rows[r["seed"]] = r
    res = []
    for sd in sorted(rows):
        L, k = load(sd)
        r = rows[sd]
        cls = "solved" if r.get("solved", 0) > 0 else ("touched, not returned" if k >= 0 else "MISS")
        res.append((sd, k, cls, L))
    n = len(res)
    cnt = {c: sum(1 for x in res if x[2] == c) for c in ("solved", "touched, not returned", "MISS")}
    print(f"champion plain stroke, sets A + B ({n} serves): {cnt}")
    misses = [x for x in res if x[2] == "MISS"]
    out = []
    for sd, k, cls, L in misses:
        t, ball, pad = L[:, 0], L[:, 1:4], L[:, 7:10]
        same = np.linalg.norm(ball - pad, axis=1)
        i0 = int(np.argmin(same))
        cf = config_lags(L)
        best = min(cf, key=lambda c: abs(c[0])) if cf else None
        out.append(dict(seed=sd, same_time_min=float(same[i0]), t_same=float(t[i0]), n_config=len(cf), best_lag=(best[0] if best else None),
                        best_inplane=(best[3] if best else None), best_normal=(best[4] if best else None), side=rows[sd].get("side")))
    json.dump(out, open("out/tt5/miss_spacetime.json", "w"), indent=1)
    with_cf = [o for o in out if o["n_config"] > 0]
    print(f"misses {len(out)}: pad path passes THROUGH the ball path (some contact configuration exists) on {len(with_cf)}; never on {len(out) - len(with_cf)}")
    if with_cf:
        lags = np.array([o["best_lag"] for o in with_cf])
        print("  smallest |lag| over contact configurations (ms): median %.0f, p25 %.0f, p75 %.0f, max %.0f; lag sign: pad EARLIER than the ball on %d, LATER on %d"
              % (1000 * np.median(np.abs(lags)), 1000 * np.percentile(np.abs(lags), 25), 1000 * np.percentile(np.abs(lags), 75), 1000 * np.abs(lags).max(), (lags < 0).sum(), (lags > 0).sum()))
        for tol in (0.01, 0.02, 0.03, 0.05, 0.08, 0.12):
            print(f"  a shift of the pad by at most {int(tol * 1000):3d} ms would make contact possible on {sum(1 for o in with_cf if abs(o['best_lag']) <= tol)} of {len(out)} misses")
    sm = np.array([o["same_time_min"] for o in out])
    print("  same-time closest approach of the pad centre to the ball centre (m): median %.3f, p25 %.3f, p75 %.3f" % (np.median(sm), np.percentile(sm, 25), np.percentile(sm, 75)))
    far = [o for o in out if o["n_config"] == 0]
    print("  misses whose pad path never meets the ball path:", [(o["seed"], round(o["same_time_min"], 2)) for o in far][:12])


if __name__ == "__main__":
    main()
