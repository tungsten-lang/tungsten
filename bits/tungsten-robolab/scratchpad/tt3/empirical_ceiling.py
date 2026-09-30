"""What would the champion's ARM score with the best plan? (agent T3) Offline, on the 200 serves of sets A and B: each serve's plan is the robust nominal (pitch, yaw, retreat d) of plan_r_champ.json
(maximising the landing probability at the champion's noise level, fitted puppet model); the champion's own execution error on that serve (pass 1) is added to it:
  pitch / yaw error = pad normal - its aim normal at contact (deg), pad velocity error = the pad's world velocity at contact - the side-mean, in-plane position error = the ball's offset from the pad centre.
Serves the champion did not touch count as failures (hit 0). success = hit AND in-plane offset < r_ok AND the fitted flight model lands the return.
Also the same with the champion's errors scaled by k (0.5, 0.25) to see how the empirical errors compare with the Gaussian tolerance table."""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "tt3"))
import tt_impact as ti
from make_plans import record, orient, angles

E, MU, ALPHA = 1.0335, 0.0731, 1.0
plans = json.load(open("scratchpad/tt3/results/plan_r_champ.json"))
rows = {}
for s in "AB":
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l); rows[r["seed"]] = r
recs = {sd: record(sd, r) for sd, r in rows.items()}
mean_v = {}
for side in (1, 2):
    mean_v[side] = np.mean([recs[sd]["vp"] for sd, r in rows.items() if recs[sd]["hit"] and r.get("side") == side], axis=0)
mean_dp, mean_dy = {}, {}
for side in (1, 2):
    dps, dys = [], []
    for sd, r in rows.items():
        d = recs[sd]
        if d["hit"] and d["aim_n"] is not None and r.get("side") == side:
            pp, py = angles(d["pad_n"]); ap, ay = angles(d["aim_n"]); dps.append(pp - ap); dys.append(py - ay)
    mean_dp[side], mean_dy[side] = float(np.mean(dps)), float(np.mean(dys))
print("side-mean execution offsets removed (calibrated out): pitch", {k: round(v, 2) for k, v in mean_dp.items()}, "yaw", {k: round(v, 2) for k, v in mean_dy.items()})
def place(sd):
    z = np.load(f"out/tt3/logs_o0/{sd}.npz"); L = z["L"]; k = int(z["contact"])
    ball, pad, nrm = L[k, 1:4], L[k, 7:10], L[k, 13:16]; nrm = nrm / np.linalg.norm(nrm)
    off = ball - pad
    return off - (off @ nrm) * nrm
def evaluate(scale, r_ok=0.085):
    ok = 0; n = 0; details = {"nohit": 0, "rim": 0, "land_fail": 0}
    for sd, r in rows.items():
        n += 1
        d = recs[sd]
        if not d["hit"] or d["aim_n"] is None:
            details["nohit"] += 1; continue
        pp, py = angles(d["pad_n"]); ap, ay = angles(d["aim_n"])
        dp, dy = pp - ap - mean_dp[r['side']], py - ay - mean_dy[r['side']]
        dv = d["vp"] - mean_v[r["side"]]
        pos = place(sd)
        if np.linalg.norm(pos) * 1.0 > r_ok / max(scale, 1e-9) * 1.0 and scale >= 1.0:
            details["rim"] += 1; continue
        if scale < 1.0 and np.linalg.norm(pos) * scale > r_ok:
            details["rim"] += 1; continue
        pl = plans[str(sd)]
        n_pos = -np.array(pl["n_out"]); pit, yaw = angles(n_pos)
        nn = ti.normal_from_angles(np.radians(pit + scale * dp), np.radians(yaw + scale * dy))
        vp = np.array(pl["v"]) + scale * dv
        v = ti.impact(d["vb"], ALPHA * vp, nn, E, MU)
        if bool(ti.landing_ok(d["p"], v)):
            ok += 1
        else:
            details["land_fail"] += 1
    return ok / n, details
for k in (1.0, 0.75, 0.5, 0.35, 0.25):
    p, det = evaluate(k)
    print(f"champion's empirical execution errors x{k:.2f} with the robust plan: P(success) {100 * p:.1f} %  {det}")
