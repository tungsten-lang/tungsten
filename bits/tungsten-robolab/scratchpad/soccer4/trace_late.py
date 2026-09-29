"""Time series of the stance state for one start, every `every` seconds until the end.
usage: trace_late.py <params> <controller> <seed> <seconds> [k=v,...]  -> prints a table and writes tr/late_<seed>_<tag>.json
columns: t, phase label, roll (pelvis lateral tilt, outward +), pelvis yaw, stance foot yaw, cp outward (cpo), cp forward (cpf),
loads l/r, pelvis height, COM velocity (lateral, forward in the stance foot's frame)"""
import math, os, sys, json
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

params = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); seed = int(sys.argv[3]); secs = float(sys.argv[4])
if len(sys.argv) > 5:
    for kv in sys.argv[5].split(","):
        if "=" in kv:
            k, v = kv.split("="); params[k] = float(v)
tag = os.environ.get("TAG", "x")
every = float(os.environ.get("EVERY", "0.5"))
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
os.environ["MYO_SOCCER_MAX_TIME"] = "310"
import mujoco
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask

rows = []
nxt = [0.0]


class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        m, d = sim.m, sim.d
        t = float(d.time)
        if t < nxt[0]:
            return
        nxt[0] = t + every
        lab = sim.label.split(":")[-1] if sim.label else ""
        pel = d.xmat[m.body("pelvis").id].reshape(3, 3)
        com = d.subtree_com[m.body("root").id].copy()
        mujoco.mj_subtreeVel(m, d)
        v = d.subtree_linvel[m.body("root").id].copy()
        ct = sim.foot_contacts()
        sd = "l" if "_l" in lab or lab.endswith("l") else "r"
        c = 0.5 * (d.xpos[m.body("calcn_" + sd).id] + d.xpos[m.body("toes_" + sd).id])
        R = d.xmat[m.body("calcn_" + sd).id].reshape(3, 3)
        h = math.atan2(R[1, 0], R[0, 0])
        sg = 1.0 if sd == "l" else -1.0
        dx = com[0] + v[0] * 0.311 - c[0]; dy = com[1] + v[1] * 0.311 - c[1]
        rm = d.body(sim.root).xmat.reshape(3, 3)
        up = sim._axis(rm, sim.root_up); fw = sim._axis(rm, sim.root_fwd)
        roll = sg * (fw[0] * up[1] - fw[1] * up[0])
        rows.append({"t": round(t, 2), "lab": lab, "roll": float(roll),
                     "yaw": float(math.atan2(pel[1, 0], pel[0, 0])), "fy": float(h),
                     "cpo": float(sg * (dy * math.cos(h) - dx * math.sin(h))), "cpf": float(dx * math.cos(h) + dy * math.sin(h)),
                     "ll": float(ct["l"]), "lr": float(ct["r"]), "pz": float(d.xpos[m.body("pelvis").id][2]),
                     "vo": float(sg * (v[1] * math.cos(h) - v[0] * math.sin(h))), "vf": float(v[0] * math.cos(h) + v[1] * math.sin(h))})


r = MyoSim(T(), params=params, controller=ctl, seed=seed).run(secs)
print("result:", {k: r.get(k) for k in ("bal1_s", "stand_time", "fallen")})
print(f"{'t':>6} {'phase':<10} {'roll':>7} {'yaw':>7} {'fyaw':>7} {'cpo':>7} {'cpf':>7} {'vo':>6} {'vf':>6} {'ll':>5} {'lr':>5} {'pz':>5}")
for w in rows:
    print(f"{w['t']:6.2f} {w['lab']:<10} {w['roll']:+7.3f} {w['yaw']:+7.3f} {w['fy']:+7.3f} {w['cpo']:+7.3f} {w['cpf']:+7.3f} {w['vo']:+6.2f} {w['vf']:+6.2f} {w['ll']:5.2f} {w['lr']:5.2f} {w['pz']:5.2f}")
json.dump(rows, open(f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4/tr/late_{seed}_{tag}.json", "w"))
