"""mtab: muscle-level view of the right-leg stances (activation, contraction c, velocity, force fraction f = force / peak isometric)
by stance quarter, from one flying-start rollout; the vertical GRF and joint angles per quarter as well. DIAGNOSTIC.
  ROBOLAB_SNAP=run_v4_p95j .venv/bin/python scratchpad/sprint2/mtab.py PARAMS --controller C --seed 0 --seconds 12 [--task sprint_touch_v4x]
"""
import argparse, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground")); sys.path.insert(0, os.path.join(ROOT, "scratchpad", "sprint_knot")); sys.path.insert(0, HERE)
import numpy as np
from practice import load_task, read_params
from bridge import Sim
import stridetab as st

class Rec2(st.Rec):
    def __init__(self, sim):
        super().__init__(sim)
        self.mt = []
    def maybe_capture(self, sim):
        super().maybe_capture(sim)
        c, cd, f = sim.contraction()
        self.mt.append(np.concatenate([[sim.d.time], c, cd, f]))

ap = argparse.ArgumentParser()
ap.add_argument("params"); ap.add_argument("--controller"); ap.add_argument("--seed", type=int, default=0); ap.add_argument("--seconds", type=float, default=12)
ap.add_argument("--task", default="sprint_touch_v4x"); ap.add_argument("--attrs", default="objective=3,fly_touch=2,fall_pen=300"); ap.add_argument("--start", default="flying")
ap.add_argument("--muscles", default="r_knee_neg,r_ankle_pos,r_gas,r_hip_flex_neg,r_ham,r_rf,r_hip_flex_pos,r_knee_pos,r_ankle_neg,r_toe_pos")
ap.add_argument("--tail", type=float, default=0.5)
a = ap.parse_args()
task = load_task(a.task)
for kv in a.attrs.split(","):
    if kv: setattr(task, kv.split("=")[0], float(kv.split("=")[1]))
task.start = a.start; task.seed = a.seed
sim = Sim(task, params=read_params(a.params), controller=a.controller)
rec = Rec2(sim); rec.hook(task)
res = sim.run(a.seconds, recorder=rec)
print({k: res.get(k) for k in ("time", "fell", "peak_speed_1s", "steady_speed")})
S = np.array(rec.steps); T = np.array(rec.ticks); M = np.array(rec.mt)
n = len(rec.names)
t = S[:, 0]; tail_t = t[-1] * (1 - a.tail)
contact = S[:, 4] > 0.01
runs = [(x, y) for x, y in st.runs_of(contact, t) if t[x] >= tail_t]
mus = a.muscles.split(",")
mi = [rec.names.index(m) for m in mus]
rows = {m: {"act": [], "c": [], "cd": [], "f": []} for m in mus}
grf_q, jq = [], []
for a0, b0 in runs[1:]:
    ka = int(np.searchsorted(T[:, 0], t[a0])); kb = max(int(np.searchsorted(T[:, 0], t[b0 - 1])), ka + 1)
    if kb >= len(T): break
    q = np.array_split(np.arange(ka, kb + 1), 4)
    grf_q.append([S[np.searchsorted(t, T[qq[0], 0]):np.searchsorted(t, T[qq[-1], 0]) + 1, 4].mean() for qq in q])
    jq.append([[T[qq, 10].mean(), T[qq, 9].mean(), T[qq, 11].mean(), T[qq, 7].mean()] for qq in q])  # r_knee, r_hip, r_ankle, thigh
    for m, i in zip(mus, mi):
        acts = T[:, 26 + i]
        Mrow = M[:, 1:]
        cc = Mrow[:, i]; cdd = Mrow[:, n + i]; ff = Mrow[:, 2 * n + i]
        # align M with T by tick index (both appended once per tick)
        rows[m]["act"].append([acts[qq].mean() for qq in q]); rows[m]["c"].append([cc[qq].mean() for qq in q])
        rows[m]["cd"].append([cdd[qq].mean() for qq in q]); rows[m]["f"].append([ff[qq].mean() for qq in q])
print(f"{len(grf_q)} stances; per stance QUARTER means (q1 = touchdown .. q4 = lift-off)")
print("  vGRF (BW)              " + " ".join(f"{x:6.2f}" for x in np.mean(grf_q, axis=0)))
jqm = np.mean(jq, axis=0)
for k, nm in enumerate(["knee", "hip", "ankle", "thigh(world)"]):
    print(f"  {nm:22s} " + " ".join(f"{x:6.2f}" for x in jqm[:, k]))
for m in mus:
    r = rows[m]
    print(f"  {m:14s} act " + " ".join(f"{x:5.2f}" for x in np.mean(r['act'], axis=0)) + "  | c " + " ".join(f"{x:5.2f}" for x in np.mean(r['c'], axis=0)) +
          "  | cdot " + " ".join(f"{x:6.1f}" for x in np.mean(r['cd'], axis=0)) + "  | force frac " + " ".join(f"{x:5.2f}" for x in np.mean(r['f'], axis=0)))
