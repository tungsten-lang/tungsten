"""trace: one rollout with a per-tick timeline (label, contacts, pelvis z, pitch, speed, joints, key activations)."""
import argparse, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params  # noqa
from bridge import Sim  # noqa
import numpy as np

MUS = ["r_hip_flex_neg", "r_ankle_pos", "r_knee_neg", "r_hip_flex_pos", "r_ham"]

class Tr:
    def __init__(self, every):
        self.rows = []; self.every = every; self.k = 0
    def maybe_capture(self, sim):
        self.k += 1
        if self.k % self.every:
            return
        m, d = sim.m, sim.d
        def q(j):
            return math.degrees(d.qpos[m.joint(j).qposadr[0]])
        tor = d.body("torso").xmat.reshape(3, 3)[:, 2]
        names = [m.actuator(i).name for i in range(m.nu)]
        act = sim.log[-1][2]
        def a(n):
            return act[names.index(n)] if n in names else float("nan")
        ct = sim.contacts()
        self.rows.append((d.time, sim.label.split(":")[-1][:8], ct["l_foot"], ct["r_foot"], d.body("pelvis").xpos[2],
                          math.degrees(math.atan2(tor[0], tor[2])), d.subtree_linvel[m.body("pelvis").id][0],
                          q("r_hip_flex"), q("r_knee"), q("r_ankle"), q("l_hip_flex"), q("l_knee"), q("l_ankle"),
                          *[a(n) for n in MUS],
                          math.degrees(d.qpos[m.joint("root_pitch").qposadr[0]]), q("spine_flex"), a("spine_flex_pos"), a("spine_flex_neg"),
                          *self.gl(sim, names)))
    def gl(self, sim, names):
        i = names.index("r_hip_flex_neg")
        c, cd, f = sim.contraction()
        return sim.targets[i] - c[i], cd[i], float(sim.d.body("l_foot").xpos[2]), float(sim.d.body("r_foot").xpos[2]), \
            float(sim.d.subtree_linvel[sim.m.body("pelvis").id][2]), float(sim.d.body("l_foot").xpos[0] - sim.d.subtree_com[sim.m.body("pelvis").id][0]), \
            float(sim.d.body("r_foot").xpos[0] - sim.d.subtree_com[sim.m.body("pelvis").id][0])

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("task"); ap.add_argument("params")
    ap.add_argument("--seed", default=None); ap.add_argument("--seconds", type=float, default=2.0)
    ap.add_argument("--start"); ap.add_argument("--set"); ap.add_argument("--every", type=int, default=5)
    ap.add_argument("--controller"); ap.add_argument("--attr")
    ap.add_argument("--mus")
    a = ap.parse_args()
    if a.mus:
        MUS[:] = a.mus.split(",")
    p = read_params(a.params) if a.params != "-" else {}
    for kv in (a.set or "").split(","):
        if kv:
            k, v = kv.split("="); p[k] = float(v)
    task = load_task(a.task)
    if a.start:
        task.start = a.start
    for kv in (a.attr or "").split(","):
        if kv:
            setattr(task, kv.split("=")[0], float(kv.split("=")[1]))
    task.seed = int(a.seed) if a.seed else None
    sim = Sim(task, params=p, controller=a.controller)
    tr = Tr(a.every)
    res = sim.run(a.seconds, recorder=tr)
    n = len(MUS)
    hdr = ["t", "label", "lc", "rc", "pz", "pitch", "vx", "rhip", "rknee", "rank", "lhip", "lknee", "lank"] + [m.replace("_flex", "").replace("hip_pos", "hipF").replace("hip_neg", "hipE")[:8] for m in MUS] + ["pelv", "spine", "spP", "spN", "gl_err", "gl_cd", "lfz", "rfz", "vz", "lfx", "rfx"]
    print(" ".join(f"{h:>8s}" if k != 1 else f"{h:8s}" for k, h in enumerate(hdr)))
    for r in tr.rows:
        out = []
        for k, v in enumerate(r):
            if k == 1:
                out.append(f"{v:8s}")
            elif 7 <= k <= 12:
                out.append(f"{v:8.0f}")
            else:
                out.append(f"{v:8.2f}")
        print(" ".join(out))
    print({k: res.get(k) for k in ("time", "fell", "distance", "steady_speed", "peak_speed_1s", "step_freq", "contact_time", "flight_time")})
