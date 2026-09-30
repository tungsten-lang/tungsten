"""How much execution noise can the best plan tolerate? (agent T3) Offline Monte Carlo with the impact model fitted on the kinematic-paddle runs (fit_impact.py: e 1.0335, mu 0.0731, alpha 1)
on the 200 serves' contact states (pass-1 ball state at the last tick before contact, sets A and B). Per serve and noise level: the nominal plan (pitch, yaw, retreat d along +x)
is either the max-margin plan of the noise-free model (`margin`) or the plan maximising the Monte Carlo success at that noise (`robust`); success = P(pad centre within r_ok of the ball's
centre) x P(return lands | contact), the pad normal / velocity drawn around the plan (pitch sd, yaw sd, velocity sd per axis), position sd per in-plane axis (Rayleigh).
    .venv-myo/bin/python scratchpad/tt3/tolerance.py [--E 1.0335 --MU 0.0731 --ALPHA 1.0] [--n 200] [--K 48]"""
import argparse, json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "tt3"))
import tt_impact as ti
from make_plans import record, orient, margin_grid

ap = argparse.ArgumentParser()
ap.add_argument("--E", type=float, default=1.0335); ap.add_argument("--MU", type=float, default=0.0731); ap.add_argument("--ALPHA", type=float, default=1.0)
ap.add_argument("--n", type=int, default=200); ap.add_argument("--K", type=int, default=48); ap.add_argument("--r_ok", type=float, default=0.085)
ap.add_argument("--json")
a = ap.parse_args()
rows = {}
for s in "AB":
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l); rows[r["seed"]] = r
seeds = sorted(rows)[:a.n] if a.n < 200 else sorted(rows)
recs = [record(sd, rows[sd]) for sd in seeds]
PIT = np.arange(-30.0, 51.0, 3.0); YAW = np.arange(-28.0, 29.0, 4.0); DEL = np.arange(-0.25, 1.51, 0.25)
rng = np.random.default_rng(5)
Z = rng.standard_normal((a.K, 5))

def land_prob(p0, vin, sp, sy, sv, pit0, yaw0, d0):
    """P(lands) for nominal (pit0, yaw0, d0) arrays broadcast; noise draws Z"""
    P = np.radians(pit0[..., None] + sp * Z[:, 0]); Y = np.radians(yaw0[..., None] + sy * Z[:, 1])
    n = np.stack([np.cos(P) * np.cos(Y), np.cos(P) * np.sin(Y), np.sin(P) + 0 * Y], axis=-1)
    vp = np.stack([d0[..., None] + sv * Z[:, 2], sv * Z[:, 3] + 0 * P, sv * Z[:, 4] + 0 * P], axis=-1)
    v = ti.impact(vin, a.ALPHA * vp, n, a.E, a.MU)
    return ti.landing_ok(p0, v).mean(axis=-1)

def serve_success(rec, sp, sy, sv, spos, robust):
    p0, vin = rec["p"], rec["vb"]
    PG, YG, DG = np.meshgrid(PIT, YAW, DEL, indexing="ij")
    if robust:
        pl = land_prob(p0, vin, sp, sy, sv, PG, YG, DG)
        best = float(pl.max())
    else:
        M = margin_grid(p0, vin, [np.array([d, 0.0, 0.0]) for d in DEL], a.E, a.ALPHA, a.MU, np.arange(-40.0, 60.1, 1.0), np.arange(-35.0, 35.1, 1.0))
        i, j, k = np.unravel_index(int(np.argmax(M)), M.shape)
        pl = land_prob(p0, vin, sp, sy, sv, np.array(np.arange(-40.0, 60.1, 1.0)[j]), np.array(np.arange(-35.0, 35.1, 1.0)[k]), np.array(DEL[i]))
        best = float(pl)
    rim = 1.0 if spos <= 0 else 1 - np.exp(-a.r_ok ** 2 / (2 * spos ** 2))
    return best * rim

def table(levels, robust):
    out = []
    for (sp, sy, sv, spos) in levels:
        out.append(np.mean([serve_success(r, sp, sy, sv, spos, robust) for r in recs]))
    return out

levels = [(0, 0, 0, 0), (11, 3.5, 0.5, 0.043), (8, 3.0, 0.4, 0.035), (6, 2.5, 0.35, 0.03), (4, 2.0, 0.25, 0.03), (3, 1.5, 0.2, 0.02), (2, 1.0, 0.12, 0.015)]
res = {}
for robust in (False, True):
    t = table(levels, robust)
    res["robust" if robust else "margin"] = t
    print(("robust plan (max MC success at the noise)" if robust else "max-margin plan (noise-free optimum)") + f": {len(recs)} serves")
    for lv, v in zip(levels, t):
        print(f"   pitch sd {lv[0]:>4} deg, yaw sd {lv[1]:>3} deg, velocity sd {lv[2]:>4} m/s, position sd {100 * lv[3]:>4.1f} cm  ->  P(success) {100 * v:5.1f} %")
# one factor at a time at the champion's level, best-margin and robust plans
print("one noise source at a time at the champion's level (others 0):")
single = {"pitch 11 deg": (11, 0, 0, 0), "yaw 3.5 deg": (0, 3.5, 0, 0), "velocity 0.5 m/s": (0, 0, 0.5, 0), "position 4.3 cm": (0, 0, 0, 0.043)}
for nm, lv in single.items():
    print(f"   {nm:<18} margin plan {100 * table([lv], False)[0]:5.1f} %   robust plan {100 * table([lv], True)[0]:5.1f} %")
# grid pitch sd x velocity sd with yaw 2 deg, position 3 cm, robust plan
print("robust plan, yaw sd 2 deg, position sd 3 cm: rows pitch sd (deg), cols velocity sd (m/s)")
VS = [0.1, 0.25, 0.4, 0.5]
print("        " + "  ".join(f"{v:5.2f}" for v in VS))
for sp in (2, 4, 6, 8, 11):
    print(f"   {sp:>4} " + "  ".join(f"{100 * table([(sp, 2.0, v, 0.03)], True)[0]:5.1f}" for v in VS))
if a.json:
    json.dump(res, open(a.json, "w"))
