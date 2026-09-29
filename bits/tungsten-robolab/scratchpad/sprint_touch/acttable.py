"""Activation table of a run's steady tail (t > T0): per muscle group (both legs) the peak, % of time >= 0.9 and
mean of the MuJoCo activation state, plus a co-contraction index per antagonist pair, CCI = 2 sum(min(a, b)) /
sum(a + b) (0 = perfectly reciprocal, 1 = equal co-activation).
usage: acttable.py TASK PARAMS CONTROLLER [--seconds 16] [--t0 8] [--json out.json] [--label x]"""
import argparse, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
import numpy as np
GROUPS = [("hip extensors (glut.)", "hip_flex_neg"), ("hip flexors (iliops.)", "hip_flex_pos"), ("hamstrings", "ham"),
          ("rectus femoris", "rf"), ("vasti", "knee_neg"), ("knee flexors (mono)", "knee_pos"), ("soleus", "ankle_pos"),
          ("gastrocnemius", "gas"), ("dorsiflexors", "ankle_neg")]
PAIRS = [("hip", "hip_flex_neg", "hip_flex_pos"), ("knee", "knee_neg", "knee_pos"), ("ankle", "ankle_pos", "ankle_neg"),
         ("ham/rf", "ham", "rf")]
class R:
    def __init__(s): s.rows = []
    def maybe_capture(s, sim):
        ct = sim.contacts()
        s.rows.append((sim.d.time, sim.d.act.copy(), ct["l_foot"] > 0.05, ct["r_foot"] > 0.05))
ap = argparse.ArgumentParser()
ap.add_argument("task"); ap.add_argument("params"); ap.add_argument("controller")
ap.add_argument("--seconds", type=float, default=16.0); ap.add_argument("--t0", type=float, default=8.0)
ap.add_argument("--json"); ap.add_argument("--label", default=""); ap.add_argument("--seed", type=int, default=None)
a = ap.parse_args()
task = load_task(a.task); task.seed = a.seed
sim = Sim(task, params=read_params(a.params), controller=None if a.controller == "-" else a.controller)
r = R(); res = sim.run(a.seconds, recorder=r)
m = sim.m
names = [m.actuator(i).name for i in range(m.nu)]
adr = [m.actuator_actadr[i] for i in range(m.nu)]
T = np.array([x[0] for x in r.rows]); A = np.array([x[1] for x in r.rows]); tail = T > min(a.t0, 0.5 * T[-1])
ST = {"l_": np.array([x[2] for x in r.rows]), "r_": np.array([x[3] for x in r.rows])}
def col(n, phase=None):
    m = tail.copy()
    if phase is not None:
        m &= ST[n[:2]] if phase == "stance" else ~ST[n[:2]]
    return A[m, adr[names.index(n)]]
out = {"label": a.label, "time": res["time"], "fell": res["fell"], "steady_speed": res.get("steady_speed"),
       "peak_speed_1s": res.get("peak_speed_1s"), "groups": {}, "cci": {}}
print(f"{a.label}: t {res['time']} fell {res['fell']} steady {res.get('steady_speed')} peak {res.get('peak_speed_1s')}")
print(f"  {'group':24s} {'peak':>5s} {'%>=0.9':>7s} {'mean':>5s} | stance {'%>=0.9':>7s} {'mean':>5s} | swing {'%>=0.9':>7s} {'mean':>5s}")
for g, suf in GROUPS:
    x = np.concatenate([col(s + suf) for s in ("l_", "r_")])
    xs = np.concatenate([col(s + suf, "stance") for s in ("l_", "r_")])
    xw = np.concatenate([col(s + suf, "swing") for s in ("l_", "r_")])
    out["groups"][g] = {"peak": round(float(x.max()), 2), "pct90": round(100 * float(np.mean(x >= 0.9)), 1), "mean": round(float(x.mean()), 2),
                        "stance_pct90": round(100 * float(np.mean(xs >= 0.9)), 1), "stance_mean": round(float(xs.mean()), 2),
                        "swing_pct90": round(100 * float(np.mean(xw >= 0.9)), 1), "swing_mean": round(float(xw.mean()), 2)}
    print(f"  {g:24s} {x.max():5.2f} {100 * np.mean(x >= 0.9):6.1f}% {x.mean():5.2f} |        {100 * np.mean(xs >= 0.9):6.1f}% {xs.mean():5.2f} |       {100 * np.mean(xw >= 0.9):6.1f}% {xw.mean():5.2f}")
for ph in (None, "stance", "swing"):
    for p, ag, an in PAIRS:
        num = den = 0.0
        for s in ("l_", "r_"):
            u, v = col(s + ag, ph), col(s + an, ph)
            num += 2 * np.minimum(u, v).sum(); den += (u + v).sum()
        out["cci"][(ph or "all") + ":" + p] = round(num / max(den, 1e-9), 3)
    print(f"  CCI {ph or 'all':6s} " + "  ".join(f"{p} {out['cci'][(ph or 'all') + ':' + p]:.2f}" for p, _, _ in PAIRS))
if a.json:
    with open(a.json, "w") as f:
        json.dump(out, f, indent=1)
