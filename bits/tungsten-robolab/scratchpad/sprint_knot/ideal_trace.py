"""DIAGNOSTIC (not a controller): replay the ideal-control analysis's optimal stance
(out/sprint_limits/<name>_speeds.json, x_stance at speed v) through its own rig and record
every physics step: stance-leg joint angles / velocities, pelvis pitch, thigh angle, the 11
stance muscles' excitation, activation and contraction (the bridge's definition), vertical GRF.
usage: ideal_trace.py --profile p95 --runs p95_speeds,p95_hi_speeds,p95_top_speeds --v 7.5 --out trace.npz"""
import argparse, json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
import sprint_limits as SL

ap = argparse.ArgumentParser()
ap.add_argument("--profile", default=None); ap.add_argument("--parts", default=None)
ap.add_argument("--runs", required=True); ap.add_argument("--v", type=float, required=True); ap.add_argument("--out", required=True)
a = ap.parse_args()
run = None
for name in a.runs.split(","):
    d = json.load(open(os.path.join(ROOT, "out", "sprint_limits", name + ".json")))
    for r in d["runs"]:
        if abs(r["v"] - a.v) < 1e-6:
            run, flags = r, d.get("flags")
if run is None:
    sys.exit(f"no run at v {a.v}")
rig = SL.Rig(a.profile, a.parts)
m, dd = rig.m, rig.d
rows = []
orig = SL.mujoco.mj_step
names = SL.STANCE_MUSCLES
ids = [m.actuator(n).id for n in names]
lr = m.actuator_lengthrange
def rec_step(mm, d):
    orig(mm, d)
    q = [float(d.qpos[SL._addr(mm, j)[0]]) for j in SL.RIGHT_LEG]
    qd = [float(d.qvel[SL._addr(mm, j)[1]]) for j in SL.RIGHT_LEG]
    pitch = float(d.qpos[SL._addr(mm, "root_pitch")[0]])
    L = d.actuator_length[ids]
    c = (lr[ids, 1] - L) / (lr[ids, 1] - lr[ids, 0])
    act = [float(d.act[mm.actuator_actadr[i]]) for i in ids]
    rows.append((float(d.time), *q, *qd, pitch, *[float(d.ctrl[i]) for i in ids], *act, *c))
SL.mujoco.mj_step = rec_step
st = rig.stance(run["x_stance"], a.v, record=True, flags=flags)
SL.mujoco.mj_step = orig
R = np.array(rows)
tr = np.array(st["grf_trace"])  # (t - td, fz BW) per step from touchdown
td = R[len(R) - len(tr), 0] - tr[0, 0] if len(tr) else None
print("valid", st["valid"], "tc", round(st["tc"], 4), "vz_lo", round(st["vz_lo"], 3), "peak", round(st["peak_grf"], 2), "td", td)
np.savez_compressed(a.out, rows=R, td=td, tc=st["tc"], grf=tr, names=np.array(names), v=a.v,
                    weyand=json.dumps(run["weyand"]), x=json.dumps(run["x_stance"]))
t = R[:, 0] - td
nq = 4
thigh = R[:, 1] - R[:, 9]
print(" t(ms)  thigh  hip   knee  ankle  | hipv  kneev  anklev | " + " ".join(n[2:9] for n in names))
for k in range(0, len(R), 10):
    if -0.02 <= t[k] <= st["tc"] + 0.01:
        e = R[k, 10:10 + len(names)]
        print(f"{1000 * t[k]:6.0f} {thigh[k]:6.2f} {R[k,1]:5.2f} {R[k,2]:5.2f} {R[k,3]:6.2f} | {R[k,5]:5.1f} {R[k,6]:6.1f} {R[k,7]:6.1f} | "
              + " ".join(f"{x:7.2f}" for x in e))
