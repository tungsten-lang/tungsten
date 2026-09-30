"""Fit the impact model (tt_impact.impact: v_out = alpha vp + (1-mu)(v - alpha vp) - (1+e-mu)((v - alpha vp).n) n) on a run's episodes (agent T3).
    .venv-myo/bin/python scratchpad/tt3/fit_impact.py out/tt3/o4a_A.jsonl [more.jsonl ...]"""
import json, sys, os
import numpy as np
from scipy.optimize import least_squares
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import tt_impact as ti
rows = []
for f in sys.argv[1:]:
    rows += [json.loads(l) for l in open(f) if l.strip()]
H = [r for r in rows if r.get("hit") and r.get("ball_in_exact") and r.get("ball_out_exact") and r.get("pad_normal") and r.get("paddle_vel")]
vin = np.array([r["ball_in_exact"] for r in H]); vout = np.array([r["ball_out_exact"] for r in H]); n = np.array([r["pad_normal"] for r in H]); vp = np.array([r["paddle_vel"] for r in H])
print(len(H), "hits; mean |pad velocity| %.3f" % np.linalg.norm(vp, axis=1).mean())
def resid(x):
    e, mu, alpha = x
    return (ti.impact(vin, alpha * vp, n, e, mu) - vout).ravel()
sol = least_squares(resid, [0.95, 0.01, 0.9], bounds=([0.5, -0.2, 0.0], [1.2, 0.5, 1.2]))
r = resid(sol.x).reshape(-1, 3)
print("fit e %.4f mu %.4f alpha %.4f | rms residual %.3f m/s (median |resid| %.3f)" % (*sol.x, np.sqrt((r ** 2).mean()), np.median(np.linalg.norm(r, axis=1))))
r0 = (ti.impact(vin, 0.9 * vp, n, 0.95, 0.012) - vout)
print("T's model (e 0.95, mu 0.012, alpha 0.9): rms %.3f median %.3f" % (np.sqrt((r0 ** 2).mean()), np.median(np.linalg.norm(r0, axis=1))))
# outcome check of the offline model on these hits
ok = 0; agree = 0; n_l = 0
for i, rr in enumerate(H):
    lab, x, y, t = ti.flight(rr["ball_pos_out"], vout[i])
    agree += int((lab == "opp") == bool(rr.get("solved"))); n_l += 1
print("flight of the measured exit velocity reproduces `solved` on %d / %d hits" % (agree, n_l))
if os.environ.get("VERBOSE"):
    rn = np.linalg.norm(r, axis=1)
    idx = np.argsort(-rn)[:12]
    for i in idx:
        rr = H[i]
        un = (vin[i] @ n[i])
        print(f"seed {rr['seed']} |resid| {rn[i]:.2f} vin {np.round(vin[i],2)} vout {np.round(vout[i],2)} model {np.round(ti.impact(vin[i], 0*vp[i], n[i], sol.x[0], sol.x[1]),2)} n {np.round(n[i],2)} vin.n {un:+.2f} land {rr.get('landed')} miss_dist {rr.get('miss_dist')}")
    print("percentiles of |resid|:", np.percentile(rn, [10, 25, 50, 75, 90, 100]).round(3))
