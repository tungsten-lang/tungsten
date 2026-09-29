"""gaitprof: a rollout's mean posture at right touchdown and each leg muscle's mean activation
in windows after its own touchdown and toe-off (steady tail)."""
import argparse, math, os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params  # noqa
from bridge import Sim  # noqa
import numpy as np

class Rec:
    def __init__(self): self.rows = []
    def maybe_capture(self, sim):
        m, d = sim.m, sim.d
        ct = sim.contacts()
        J = ["r_hip_flex", "r_knee", "r_ankle", "r_toe", "l_hip_flex", "l_knee", "l_ankle", "l_toe", "spine_flex",
             "r_shoulder_flex", "l_shoulder_flex", "r_elbow", "l_elbow"]
        q = [math.degrees(d.qpos[m.joint(j).qposadr[0]]) for j in J]
        tor = d.body("torso").xmat.reshape(3, 3)[:, 2]
        self.rows.append((d.time, ct["l_foot"], ct["r_foot"], math.degrees(math.atan2(tor[0], tor[2])),
                          math.degrees(d.qpos[m.joint("root_pitch").qposadr[0]]), *q, *sim.log[-1][2]))

ap = argparse.ArgumentParser()
ap.add_argument("task"); ap.add_argument("params"); ap.add_argument("--controller"); ap.add_argument("--seconds", type=float, default=12)
a = ap.parse_args()
task = load_task(a.task); task.seed = None
sim = Sim(task, params=read_params(a.params), controller=a.controller)
rec = Rec(); res = sim.run(a.seconds, recorder=rec)
names = [sim.m.actuator(i).name for i in range(sim.m.nu)]
R = np.array(rec.rows); t = R[:, 0]; T = t[-1]
def events(c):
    on = c > 0.05; tds, tos = [], []
    for k in range(1, len(on)):
        if on[k] and not on[k - 1]: tds.append(t[k])
        if not on[k] and on[k - 1]: tos.append(t[k])
    return tds, tos
out = {"time": res["time"], "fell": res["fell"], "steady": res.get("steady_speed")}
tail = T - 6
kfJ = ["r_hip", "r_knee", "r_ankle", "r_toe", "l_hip", "l_knee", "l_ankle", "l_toe", "spine", "r_sh", "l_sh", "r_el", "l_el"]
rtd, rto = events(R[:, 2]); ltd, lto = events(R[:, 1])
idx = [np.searchsorted(t, x) for x in rtd if x > tail]
out["td_pose"] = {j: round(float(np.mean(R[idx, 5 + i])), 1) for i, j in enumerate(kfJ)}
out["td_trunk"] = round(float(np.mean(R[idx, 3])), 1); out["td_pelvis"] = round(float(np.mean(R[idx, 4])), 1)
# contact durations
cd = [b - a for a, b in zip(rtd, [x for x in rto if x > rtd[0]]) if a > tail]
out["contact"] = round(float(np.median(cd)), 3) if cd else None
# activation profiles for the right leg, 20 ms bins after TD (0..0.3) and after TO (0..0.3)
base = 5 + len(kfJ)
leg = ["r_hip_flex_pos", "r_hip_flex_neg", "r_rf", "r_ham", "r_knee_pos", "r_knee_neg", "r_gas", "r_ankle_pos", "r_ankle_neg"]
bins = np.arange(0, 0.36, 0.03)
for evname, evs in (("after_TD", rtd), ("after_TO", rto)):
    prof = {}
    for mu in leg:
        col = base + names.index(mu)
        row = []
        for b in bins:
            vals = [np.mean(R[(t >= e + b) & (t < e + b + 0.03), col]) for e in evs if e > tail and e + b + 0.03 < T]
            row.append(round(float(np.mean(vals)), 2) if vals else None)
        prof[mu] = row
    out[evname] = prof
print(json.dumps(out["td_pose"]), out["td_trunk"], out["td_pelvis"], out["contact"], out["steady"])
print("bins(s):", [round(b, 2) for b in bins])
for ev in ("after_TD", "after_TO"):
    print(ev)
    for mu, row in out[ev].items():
        print(f"  {mu:15s}", " ".join(f"{v:4.2f}" if v is not None else "  - " for v in row))
